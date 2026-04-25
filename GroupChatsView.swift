//
//  GroupChatsView.swift
//  SportsHub
//
//  Group messaging interface
//

import SwiftUI

struct GroupChatsView: View {
    @State private var groups: [GroupChat] = []
    @State private var isLoading = false
    @State private var showingCreateGroup = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading && groups.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groups.isEmpty {
                    emptyState
                } else {
                    groupsList
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Group Chats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateGroup = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView { newGroup in
                    groups.insert(newGroup, at: 0)
                }
            }
            .task {
                await loadGroups()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 64))
                .foregroundColor(.appSecondary)
            
            Text("No Group Chats")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Create a group to start chatting with multiple friends")
                .foregroundColor(.appSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            
            Button {
                showingCreateGroup = true
            } label: {
                Text("Create Group")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(Color.appPrimary)
                    .cornerRadius(CornerRadius.md)
            }
        }
    }
    
    private var groupsList: some View {
        List(groups) { group in
            NavigationLink {
                GroupChatDetailView(group: group)
            } label: {
                GroupChatRow(group: group)
            }
        }
        .refreshable {
            await loadGroups()
        }
    }
    
    private func loadGroups() async {
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await APIClient.shared.getGroups()
        } catch {
            // Stay empty — user can create a group
            groups = []
        }
    }
}

struct GroupChat: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let creatorId: String
    let avatarSeed: String?
    let memberCount: Int
    let lastMessage: String?
    let lastMessageAt: String?
    let unreadCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case creatorId = "creator_id"
        case avatarSeed = "avatar_seed"
        case memberCount = "member_count"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
    }
}

struct GroupChatRow: View {
    let group: GroupChat
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Group avatar
            Circle()
                .fill(LinearGradient(
                    colors: [.appPrimary, .appAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.white)
                        .font(.title3)
                )
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.appTextPrimary)
                    
                    if group.unreadCount > 0 {
                        Circle()
                            .fill(Color.appPrimary)
                            .frame(width: 8, height: 8)
                    }
                }
                
                if let lastMessage = group.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.appSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(group.memberCount) members")
                        .font(.subheadline)
                        .foregroundColor(.appSecondary)
                }
            }
            
            Spacer()
            
            if group.unreadCount > 0 {
                Text("\(group.unreadCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appPrimary)
                    .cornerRadius(12)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var groupDescription = ""
    @State private var selectedFriends: Set<UUID> = []
    @State private var friends: [User] = []
    @State private var isCreating = false
    @State private var createError: String? = nil

    let onCreate: (GroupChat) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Group Details") {
                    TextField("Group Name", text: $groupName)
                    TextField("Description (optional)", text: $groupDescription)
                }
                
                Section("Add Members") {
                    if friends.isEmpty {
                        Text("Loading friends...")
                            .foregroundColor(.appSecondary)
                    } else {
                        ForEach(friends) { friend in
                            HStack {
                                Circle()
                                    .fill(Color.appPrimary.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                
                                Text(friend.username)
                                
                                Spacer()
                                
                                if selectedFriends.contains(friend.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.appPrimary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedFriends.contains(friend.id) {
                                    selectedFriends.remove(friend.id)
                                } else {
                                    selectedFriends.insert(friend.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Create") {
                        createGroup()
                    }
                    .disabled(groupName.isEmpty || selectedFriends.isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(createError ?? "")
            }
            .task {
                await loadFriends()
            }
        }
    }
    
    private func loadFriends() async {
        do {
            let friendships = try await APIClient.shared.getFriends()
            let currentUserId = SessionManager.shared.currentUser?.id.uuidString ?? ""
            friends = friendships.compactMap { f -> User? in
                let friendId = f.userAId == currentUserId ? f.userBId : f.userAId
                guard let uuid = UUID(uuidString: friendId) else { return nil }
                return User(id: uuid, email: "", username: "User \(friendId.prefix(8))", displayName: "", role: .user)
            }
        } catch {
            friends = []
        }
    }
    
    private func createGroup() {
        guard !groupName.isEmpty, !selectedFriends.isEmpty else { return }
        isCreating = true
        
        Task {
            defer { isCreating = false }
            do {
                let memberIds = selectedFriends.map { $0.uuidString }
                let group = try await APIClient.shared.createGroup(
                    name: groupName,
                    description: groupDescription.isEmpty ? nil : groupDescription,
                    memberIds: memberIds
                )
                await MainActor.run {
                    onCreate(group)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    createError = "Couldn't create group. Please try again."
                }
            }
        }
    }
}

struct GroupChatDetailView: View {
    let group: GroupChat
    @State private var messages: [GroupMessage] = []
    @State private var messageText = ""
    @State private var sendError: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(messages) { message in
                        GroupMessageBubble(message: message)
                    }
                }
                .padding(Spacing.md)
            }
            
            // Send error banner
            if let err = sendError {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.appTextPrimary)
                    Spacer()
                    Button("Dismiss") { sendError = nil }
                        .font(.caption)
                        .foregroundStyle(Color.appPrimary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.red.opacity(0.1))
            }

            // Message input
            HStack(spacing: Spacing.sm) {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .gray : .appPrimary)
                }
                .disabled(messageText.isEmpty)
            }
            .padding(Spacing.md)
            .background(Color.appCardBackground)
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMessages()
        }
    }
    
    private func loadMessages() async {
        do {
            messages = try await APIClient.shared.getGroupMessages(groupId: group.id)
        } catch {
            messages = []
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageText = ""
        
        Task {
            do {
                let sent = try await APIClient.shared.sendGroupMessage(groupId: group.id, content: text)
                await MainActor.run {
                    messages.append(sent)
                }
            } catch {
                await MainActor.run {
                    messageText = text  // Restore on failure
                    sendError = "Message failed to send. Tap to retry."
                }
            }
        }
    }
}

struct GroupMessage: Identifiable, Codable {
    let id: String
    let groupId: String
    let senderId: String
    let senderName: String
    let content: String
    let sentAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case content
        case sentAt = "sent_at"
    }
}

struct GroupMessageBubble: View {
    let message: GroupMessage
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(message.senderName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.appPrimary)
                
                Text(message.content)
                    .padding(Spacing.sm)
                    .background(Color.appCardBackground)
                    .cornerRadius(CornerRadius.sm)
            }
            
            Spacer()
        }
    }
}

#Preview {
    GroupChatsView()
}
