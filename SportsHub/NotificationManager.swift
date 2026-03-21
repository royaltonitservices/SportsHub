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
    
    private init() {
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
    
    func scheduleMatchNotification(opponentName: String, sport: String, matchId: String) {
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
        let content = UNMutableNotificationContent()
        content.title = won ? "Victory!" : "Match Complete"
        content.body = won
            ? "You defeated \(opponentName)! Rating: +\(ratingChange)"
            : "You lost to \(opponentName). Rating: \(ratingChange)"
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
    
    func scheduleFriendRequestNotification(fromUser: String) {
        let content = UNMutableNotificationContent()
        content.title = "New Friend Request"
        content.body = "\(fromUser) wants to connect with you"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "FRIEND_REQUEST"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "friend-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    func scheduleLeaderboardUpdateNotification(newRank: Int, sport: String) {
        let content = UNMutableNotificationContent()
        content.title = "Leaderboard Update"
        content.body = "You're now ranked #\(newRank) in \(sport)!"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "LEADERBOARD"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "leaderboard-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
    
    func scheduleBadgeEarnedNotification(badgeName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Badge Unlocked! 🏆"
        content.body = "You earned the '\(badgeName)' badge!"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "BADGE_EARNED"
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "badge-\(UUID().uuidString)",
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
            // TODO: Navigate to match acceptance
            print("Accept match tapped")
        case "DECLINE_MATCH":
            // TODO: Decline match
            print("Decline match tapped")
        case "ACCEPT_FRIEND":
            // TODO: Accept friend request
            print("Accept friend tapped")
        case "DECLINE_FRIEND":
            // TODO: Decline friend request
            print("Decline friend tapped")
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification
            if let type = userInfo["type"] as? String {
                print("Notification tapped: \(type)")
                // TODO: Navigate to appropriate screen
            }
        default:
            break
        }
        
        completionHandler()
    }
}
