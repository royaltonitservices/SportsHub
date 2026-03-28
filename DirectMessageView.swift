//
//  DirectMessageView.swift
//  SportsHub
//
//  Direct message chat interface with a specific friend
//

import SwiftUI

struct DirectMessageView: View {
    let friendId: String
    let friendUsername: String
    let friendDisplayName: String

    @StateObject private var sessionManager = SessionManager.shared
    @State private var messages: [DirectMessageResponse] = []
    @State private var messageText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            if isLoading {
                ProgressView("Loading messages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    loadMessages()
                }
            } else {
                messagesScrollView
            }

            // Message Input
            messageInputView
        }
        .navigationTitle(friendDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadMessages()
        }
    }

    // MARK: - Messages Scroll View
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    if messages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(messages) { message in
                            MessageBubbleView(
                                message: message,
                                isFromCurrentUser: message.senderId == sessionManager.currentUser?.id.uuidString
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                // Auto-scroll to bottom when new message arrives
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No messages yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Send a message to start the conversation")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    // MARK: - Message Input
    private var messageInputView: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(Spacing.sm)
                .background(Color(.systemGray6))
                .cornerRadius(CornerRadius.lg)
                .focused($isTextFieldFocused)
                .lineLimit(1...5)

            Button {
                sendMessage()
            } label: {
                if isSending {
                    ProgressView()
                        .frame(width: 36, height: 36)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, Spacing.sm)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }

    // MARK: - Actions
    private func loadMessages() {
        Task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            messages = try await APIClient.shared.getConversation(withUserId: friendId)
        } catch {
            errorMessage = "We couldn't load your messages. Check your connection and try again."
        }

        isLoading = false
    }

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        isSending = true
        let tempMessage = messageText
        messageText = ""

        Task {
            do {
                let newMessage = try await APIClient.shared.sendMessage(receiverId: friendId, content: content)
                messages.append(newMessage)
            } catch {
                // Restore message text on error
                messageText = tempMessage
                errorMessage = "We couldn't send your message. Check your connection and try again."
            }
            isSending = false
        }
    }
}

// MARK: - Message Bubble View
struct MessageBubbleView: View {
    let message: DirectMessageResponse
    let isFromCurrentUser: Bool

    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer(minLength: 50)
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                    .cornerRadius(CornerRadius.lg)

                HStack(spacing: 4) {
                    Text(formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if isFromCurrentUser && message.readAt != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }

            if !isFromCurrentUser {
                Spacer(minLength: 50)
            }
        }
    }

    private var formattedTime: String {
        let dateFormatter = ISO8601DateFormatter()
        guard let date = dateFormatter.date(from: message.sentAt) else {
            return ""
        }

        let timeFormatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            timeFormatter.dateFormat = "h:mm a"
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            timeFormatter.dateFormat = "'Yesterday' h:mm a"
            return timeFormatter.string(from: date)
        } else {
            timeFormatter.dateFormat = "MMM d, h:mm a"
            return timeFormatter.string(from: date)
        }
    }
}

#Preview {
    NavigationView {
        DirectMessageView(
            friendId: "123",
            friendUsername: "testuser",
            friendDisplayName: "Test User"
        )
    }
}
