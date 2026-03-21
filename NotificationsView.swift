//
//  NotificationsView.swift
//  SportsHub
//
//  Notifications feed
//

import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notifications: [NotificationItem] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                if notifications.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(notifications) { notification in
                                NotificationRow(notification: notification)
                            }
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadNotifications()
            }
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
    
    private func loadNotifications() async {
        // TODO: Fetch notifications from API
        // notifications = await APIClient.shared.getNotifications()
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
            // Icon based on type
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
        // TODO: Proper date parsing
        return "Just now"
    }
}

#Preview {
    NotificationsView()
}
