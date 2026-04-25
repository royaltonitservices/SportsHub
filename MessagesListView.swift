//
//  MessagesListView.swift
//  SportsHub
//
//  Messages list showing all conversations with friends
//

import SwiftUI

struct MessagesListView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var conversations: [ConversationPreview] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedConversation: ConversationPreview?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading conversations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ErrorView(message: error) {
                        loadConversations()
                    }
                } else if conversations.isEmpty {
                    emptyStateView
                } else {
                    conversationsList
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.large)
            .task {
                loadConversations()
            }
            .refreshable {
                await loadData()
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Messages")
                .font(.title2.weight(.semibold))

            Text("Start a conversation with your friends")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                FriendsListView()
            } label: {
                Text("View Friends")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(Color.blue)
                    .cornerRadius(CornerRadius.md)
            }
            .padding(.top, Spacing.md)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conversations List
    private var conversationsList: some View {
        List {
            ForEach(conversations) { conversation in
                NavigationLink {
                    DirectMessageView(
                        friendId: conversation.friendId,
                        friendUsername: conversation.friendUsername,
                        friendDisplayName: conversation.friendDisplayName
                    )
                } label: {
                    ConversationRowView(conversation: conversation)
                }

            }
        }
        .listStyle(.plain)
    }

    // MARK: - Data Loading
    private func loadConversations() {
        Task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            conversations = try await APIClient.shared.getAllConversations()
        } catch {
            errorMessage = "We couldn't load your messages. Check your connection and try again."
        }

        isLoading = false
    }
}

// MARK: - Conversation Row View
struct ConversationRowView: View {
    let conversation: ConversationPreview

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Avatar
            Circle()
                .fill(avatarColor)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(initials)
                        .font(.headline)
                        .foregroundColor(.white)
                }

            // Message Preview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.friendDisplayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text(conversation.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)

                    Spacer()

                    if conversation.unreadCount > 0 {
                        unreadBadge
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private var initials: String {
        let words = conversation.friendDisplayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else {
            return String(conversation.friendDisplayName.prefix(2)).uppercased()
        }
    }

    private var avatarColor: Color {
        // Generate consistent color based on friend ID
        let hash = abs(conversation.friendId.hashValue)
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .indigo, .teal]
        return colors[hash % colors.count]
    }

    private var formattedTime: String {
        // Simple time formatting - show time if today, date otherwise
        let dateFormatter = ISO8601DateFormatter()
        guard let date = dateFormatter.date(from: conversation.lastMessageTime) else {
            return ""
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            return dateFormatter.string(from: date)
        }
    }

    private var unreadBadge: some View {
        Text("\(conversation.unreadCount)")
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue)
            .clipShape(Capsule())
    }
}

#Preview {
    MessagesListView()
}
