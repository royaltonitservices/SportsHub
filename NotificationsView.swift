//
//  NotificationsView.swift
//  SportsHub
//
//  Notifications feed — backed by /activity/feed
//

import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.appPrimary)
                } else if let error = errorMessage {
                    errorState(message: error)
                } else if notifications.isEmpty {
                    emptyState
                } else {
                    notificationsList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadNotifications()
            }
            .refreshable {
                await loadNotifications()
            }
        }
    }

    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                ForEach(notifications) { notification in
                    NotificationRow(notification: notification)
                }
            }
            .padding(Spacing.md)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.appTextSecondary.opacity(0.3))

            Text("No Notifications")
                .font(.headline)
                .foregroundStyle(Color.appTextSecondary)

            Text("You're all caught up!")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary.opacity(0.8))
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.appError)

            Text("Couldn't load notifications")
                .font(.headline)

            Button("Retry") {
                Task { await loadNotifications() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.appPrimary)
        }
    }

    private func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let feed = try await APIClient.shared.getActivityFeed(limit: 50)
            notifications = feed.enumerated().map { index, item in
                activityToNotification(item, index: index)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activityToNotification(_ item: ActivityItem, index: Int) -> NotificationItem {
        let (title, message) = titleAndMessage(for: item)
        // Stable ID: combine userId + createdAt so it's deterministic
        let id = "\(item.userId)-\(item.createdAt)-\(index)"
        return NotificationItem(
            id: id,
            type: notificationType(for: item.type),
            title: title,
            message: message,
            timestamp: item.createdAt,
            isRead: false,
            avatarSeed: item.username
        )
    }

    private func notificationType(for activityType: String) -> String {
        switch activityType {
        case "match_completed", "match_result": return "match"
        case "friend_request", "friend_accepted": return "friend"
        case "challenge_received", "challenge_accepted", "challenge_declined": return "challenge"
        case "badge_earned": return "achievement"
        case "message": return "message"
        default: return "activity"
        }
    }

    private func titleAndMessage(for item: ActivityItem) -> (String, String) {
        let sport = item.sport.capitalized
        switch item.type {
        case "match_completed", "match_result":
            let opponent = item.opponentUsername.map { "@\($0)" } ?? "an opponent"
            let isWin = item.winnerUsername == item.username
            let title = isWin ? "Match Won" : "Match Result"
            var msg = isWin ? "You beat \(opponent) in \(sport)" : "You played \(opponent) in \(sport)"
            if let us = item.userScore, let them = item.opponentScore {
                msg += " (\(us)-\(them))"
            }
            if let delta = item.ratingChange, delta != 0 {
                msg += delta > 0 ? " +\(delta) rating" : " \(delta) rating"
            }
            return (title, msg)
        case "challenge_received":
            let sender = item.opponentUsername.map { "@\($0)" } ?? "Someone"
            return ("New Challenge", "\(sender) challenged you to a \(sport) match")
        case "challenge_accepted":
            let opponent = item.opponentUsername.map { "@\($0)" } ?? "Your opponent"
            return ("Challenge Accepted", "\(opponent) accepted your \(sport) challenge")
        case "challenge_declined":
            let opponent = item.opponentUsername.map { "@\($0)" } ?? "Your opponent"
            return ("Challenge Declined", "\(opponent) declined your \(sport) challenge")
        case "friend_request":
            return ("Friend Request", "@\(item.username) sent you a friend request")
        case "friend_accepted":
            return ("New Friend", "@\(item.username) accepted your friend request")
        case "badge_earned":
            return ("Badge Earned", "You earned a new \(sport) badge")
        default:
            return ("Activity", "\(item.username) had activity in \(sport)")
        }
    }
}

struct NotificationItem: Identifiable, Codable {
    let id: String
    let type: String
    let title: String
    let message: String
    let timestamp: String
    let isRead: Bool
    let avatarSeed: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, message, timestamp
        case isRead = "is_read"
        case avatarSeed = "avatar_seed"
    }
}

struct NotificationRow: View {
    let notification: NotificationItem

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: iconForType(notification.type))
                .font(.title3)
                .foregroundColor(.appPrimary)
                .frame(width: 40, height: 40)
                .background(Color.appPrimary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(notification.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.appTextPrimary)

                Text(notification.message)
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(2)

                Text(timeAgo(from: notification.timestamp))
                    .font(.caption2)
                    .foregroundColor(.appTextSecondary.opacity(0.6))
            }

            Spacer()

            if !notification.isRead {
                Circle()
                    .fill(Color.appPrimary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(Spacing.md)
        .background(Color.appSurface)
        .cornerRadius(CornerRadius.md)
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "match": return "gamecontroller.fill"
        case "friend": return "person.fill"
        case "challenge": return "flag.fill"
        case "message": return "message.fill"
        case "achievement": return "trophy.fill"
        default: return "bell.fill"
        }
    }

    private func timeAgo(from timestamp: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: timestamp)
        if date == nil {
            // Fallback: without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: timestamp)
        }
        guard let date else { return "Just now" }

        let seconds = Int(-date.timeIntervalSinceNow)
        switch seconds {
        case ..<5: return "Just now"
        case 5..<60: return "\(seconds)s ago"
        case 60..<3600: return "\(seconds / 60)m ago"
        case 3600..<86400: return "\(seconds / 3600)h ago"
        case 86400..<604800: return "\(seconds / 86400)d ago"
        default: return "\(seconds / 604800)w ago"
        }
    }
}

#Preview {
    NotificationsView()
}
