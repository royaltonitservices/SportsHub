//
//  NotificationManager.swift
//  SportsHub
//
//  Local notification framework setup
//

import Foundation
import UserNotifications
import Combine

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    /// Retained delegate — must be a stored property so ARC keeps it alive.
    private let notificationDelegate = NotificationDelegate()

    private init() {
        // Register action categories and set delegate at startup
        registerNotificationCategories()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Task {
            await checkAuthorization()
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            isAuthorized = granted
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }
    
    func checkAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - Schedule Notifications

    /// Checks the user's in-app notification preference (SettingsView toggle).
    private var areNotificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    }
    
    func scheduleMatchNotification(opponentName: String, sport: String, matchId: String) {
        guard areNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "New Match Challenge!"
        content.body = "\(opponentName) has challenged you to a \(sport) match"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "MATCH_CHALLENGE"
        content.userInfo = ["matchId": matchId, "type": "challenge"]
        
        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "match-\(matchId)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    func scheduleResultNotification(opponentName: String, won: Bool, ratingChange: Int) {
        guard areNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = won ? "Victory!" : "Match Complete"
        let ratingText = ratingChange >= 0 ? "+\(ratingChange)" : "\(ratingChange)"
        if opponentName.isEmpty {
            content.body = won
                ? "You won the match! Rating: \(ratingText)"
                : "Match submitted. Rating: \(ratingText)"
        } else {
            content.body = won
                ? "You defeated \(opponentName)! Rating: \(ratingText)"
                : "You lost to \(opponentName). Rating: \(ratingText)"
        }
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "MATCH_RESULT"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "result-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    func scheduleFriendRequestNotification(fromUser: String, friendshipId: String) {
        guard areNotificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "New Friend Request"
        content.body = "\(fromUser) wants to connect with you"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "FRIEND_REQUEST"
        content.userInfo = ["friendshipId": friendshipId, "type": "friend_request"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        // Use friendshipId as identifier so duplicate requests don't stack
        let request = UNNotificationRequest(
            identifier: "friend-\(friendshipId)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    // MARK: - Manage Notifications
    
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        setBadgeCount(0)
    }
    
    func clearNotification(identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    func setBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
                print("Failed to set badge count: \(error)")
            }
        }
    }
    
    // MARK: - Register Categories
    
    func registerNotificationCategories() {
        let matchChallengeCategory = UNNotificationCategory(
            identifier: "MATCH_CHALLENGE",
            actions: [
                UNNotificationAction(
                    identifier: "ACCEPT_MATCH",
                    title: "Accept",
                    options: .foreground
                ),
                UNNotificationAction(
                    identifier: "DECLINE_MATCH",
                    title: "Decline",
                    options: .destructive
                )
            ],
            intentIdentifiers: []
        )
        
        let friendRequestCategory = UNNotificationCategory(
            identifier: "FRIEND_REQUEST",
            actions: [
                UNNotificationAction(
                    identifier: "ACCEPT_FRIEND",
                    title: "Accept",
                    options: .foreground
                ),
                UNNotificationAction(
                    identifier: "DECLINE_FRIEND",
                    title: "Decline",
                    options: .destructive
                )
            ],
            intentIdentifiers: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            matchChallengeCategory,
            friendRequestCategory
        ])
    }
}

// MARK: - Notification Delegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "ACCEPT_MATCH":
            if let matchId = userInfo["matchId"] as? String {
                Task {
                    do {
                        _ = try await APIClient.shared.acceptChallenge(challengeId: matchId)
                        NotificationCenter.default.post(name: .challengeListDidChange, object: nil)
                    } catch {
                        print("Failed to accept challenge from notification: \(error)")
                    }
                }
            }

        case "DECLINE_MATCH":
            if let matchId = userInfo["matchId"] as? String {
                Task {
                    do {
                        _ = try await APIClient.shared.declineChallenge(challengeId: matchId)
                        NotificationCenter.default.post(name: .challengeListDidChange, object: nil)
                    } catch {
                        print("Failed to decline challenge from notification: \(error)")
                    }
                }
            }

        case "ACCEPT_FRIEND":
            if let friendshipId = userInfo["friendshipId"] as? String {
                Task {
                    do {
                        _ = try await APIClient.shared.acceptFriendRequest(friendshipId: friendshipId)
                        NotificationCenter.default.post(name: .friendListDidChange, object: nil)
                    } catch {
                        print("Failed to accept friend request from notification: \(error)")
                    }
                }
            }

        case "DECLINE_FRIEND":
            if let friendshipId = userInfo["friendshipId"] as? String {
                Task {
                    do {
                        _ = try await APIClient.shared.declineFriendRequest(friendshipId: friendshipId)
                        NotificationCenter.default.post(name: .friendListDidChange, object: nil)
                    } catch {
                        print("Failed to decline friend request from notification: \(error)")
                    }
                }
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body — signal navigation to the relevant screen
            if let type = userInfo["type"] as? String {
                NotificationCenter.default.post(
                    name: .notificationTapped,
                    object: nil,
                    userInfo: ["type": type, "data": userInfo]
                )
            }

        default:
            break
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the challenge list has changed (e.g., accepted/declined from notification action).
    /// Observers (PlayView) should reload active challenges.
    static let challengeListDidChange = Notification.Name("sportshub.challengeListDidChange")

    /// Posted when the friend list has changed (e.g., accepted/declined from notification action).
    /// Observers (FriendsListView) should reload friend requests.
    static let friendListDidChange = Notification.Name("sportshub.friendListDidChange")

    /// Posted when the user taps a notification body (not an action button).
    /// userInfo contains "type" (String) and "data" (dictionary with original notification payload).
    static let notificationTapped = Notification.Name("sportshub.notificationTapped")
}
