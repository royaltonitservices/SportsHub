//
//  FriendsListView.swift
//  SportsHub
//
//  Friends management interface with tabs for friends, requests, and blocked users
//

import SwiftUI

struct FriendsListView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var selectedTab = FriendTab.friends
    @State private var friendships: [FriendshipResponse] = []
    @State private var pendingRequests: [FriendshipResponse] = []
    @State private var receivedRequests: [FriendshipResponse] = []
    @State private var blockedUsers: [FriendshipResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAddFriend = false

    enum FriendTab: String, CaseIterable {
        case friends = "Friends"
        case requests = "Requests"
        case blocked = "Blocked"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Friend Tab", selection: $selectedTab) {
                    ForEach(FriendTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    ErrorView(message: error) {
                        loadDataTask()
                    }
                } else {
                    tabContent
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddFriend) {
                AddFriendView(onRequestSent: {
                    loadDataTask()
                })
            }
            .task {
                loadDataTask()
            }
            .onReceive(NotificationCenter.default.publisher(for: .friendListDidChange)) { _ in
                loadDataTask()
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .friends:
            friendsListView
        case .requests:
            requestsListView
        case .blocked:
            blockedListView
        }
    }

    // MARK: - Friends List
    private var friendsListView: some View {
        Group {
            if friendships.isEmpty {
                EmptyStateView(
                    icon: "person.2.fill",
                    title: "No Friends Yet",
                    message: "Add friends to start playing together"
                )
            } else {
                List {
                    ForEach(friendships) { friendship in
                        FriendRowView(friendship: friendship, currentUserId: sessionManager.currentUser?.id.uuidString ?? "") {
                            removeFriend(friendship)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Requests List
    private var requestsListView: some View {
        Group {
            if receivedRequests.isEmpty && pendingRequests.isEmpty {
                EmptyStateView(
                    icon: "envelope.fill",
                    title: "No Pending Requests",
                    message: "You'll see friend requests here"
                )
            } else {
                List {
                    if !receivedRequests.isEmpty {
                        Section("Received") {
                            ForEach(receivedRequests) { request in
                                ReceivedRequestRowView(request: request, currentUserId: sessionManager.currentUser?.id.uuidString ?? "") {
                                    await acceptRequest(request)
                                } onDecline: {
                                    await declineRequest(request)
                                }
                            }
                        }
                    }

                    if !pendingRequests.isEmpty {
                        Section("Sent") {
                            ForEach(pendingRequests) { request in
                                SentRequestRowView(request: request, currentUserId: sessionManager.currentUser?.id.uuidString ?? "")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Blocked List
    private var blockedListView: some View {
        Group {
            if blockedUsers.isEmpty {
                EmptyStateView(
                    icon: "hand.raised.fill",
                    title: "No Blocked Users",
                    message: "Blocked users will appear here"
                )
            } else {
                List {
                    ForEach(blockedUsers) { block in
                        BlockedUserRowView(block: block, currentUserId: sessionManager.currentUser?.id.uuidString ?? "") {
                            await unblockUser(block)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Data Loading
    private func loadDataTask() {
        Task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let friends = APIClient.shared.getFriendsList()
            async let received = APIClient.shared.getReceivedRequests()
            async let pending = APIClient.shared.getPendingRequests()
            async let blocked = APIClient.shared.getBlockedUsers()

            friendships = try await friends
            let newReceived = try await received
            pendingRequests = try await pending.filter { $0.userAId == sessionManager.currentUser?.id.uuidString }
            blockedUsers = try await blocked

            scheduleNotificationsForNewRequests(newReceived)
            receivedRequests = newReceived
        } catch {
            errorMessage = "We couldn't load your friends list. Check your connection and try again."
        }

        isLoading = false
    }

    /// Schedule a local notification for each new incoming friend request that hasn't been seen before.
    private func scheduleNotificationsForNewRequests(_ requests: [FriendshipResponse]) {
        let seenKey = "seen_friend_request_ids"
        let seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let newOnes = requests.filter { !seen.contains($0.id) }

        for request in newOnes {
            NotificationManager.shared.scheduleFriendRequestNotification(
                fromUser: "Someone",
                friendshipId: request.id
            )
        }

        UserDefaults.standard.set(requests.map(\.id), forKey: seenKey)
    }

    // MARK: - Actions
    private func removeFriend(_ friendship: FriendshipResponse) {
        Task {
            do {
                _ = try await APIClient.shared.removeFriend(friendshipId: friendship.id)
                await loadData()
            } catch {
                errorMessage = "We couldn't remove this friend. Please try again."
            }
        }
    }

    private func acceptRequest(_ request: FriendshipResponse) async {
        do {
            _ = try await APIClient.shared.acceptFriendRequest(friendshipId: request.id)
            await loadData()
        } catch {
            errorMessage = "We couldn't accept this friend request. Please try again."
        }
    }

    private func declineRequest(_ request: FriendshipResponse) async {
        do {
            _ = try await APIClient.shared.declineFriendRequest(friendshipId: request.id)
            await loadData()
        } catch {
            errorMessage = "We couldn't decline this friend request. Please try again."
        }
    }

    private func unblockUser(_ block: FriendshipResponse) async {
        let currentUserId = sessionManager.currentUser?.id.uuidString ?? ""
        let userId = block.userAId == currentUserId ? block.userBId : block.userAId
        do {
            _ = try await APIClient.shared.unblockUser(userId: userId)
            await loadData()
        } catch {
            errorMessage = "We couldn't unblock this user. Please try again."
        }
    }
}

// MARK: - Friend Row View
struct FriendRowView: View {
    let friendship: FriendshipResponse
    let currentUserId: String
    let onRemove: () -> Void

    private var friendUserId: String {
        friendship.userAId == currentUserId ? friendship.userBId : friendship.userAId
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Avatar placeholder
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(friendUserId.prefix(2).uppercased())
                        .font(.headline)
                        .foregroundColor(.blue)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("User \(friendUserId.prefix(8))")
                    .font(.headline)
                Text("Friends since \(formattedDate(friendship.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Menu {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove Friend", systemImage: "person.fill.xmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func formattedDate(_ dateString: String) -> String {
        // Simple date formatting
        String(dateString.prefix(10))
    }
}

// MARK: - Received Request Row View
struct ReceivedRequestRowView: View {
    let request: FriendshipResponse
    let currentUserId: String
    let onAccept: () async -> Void
    let onDecline: () async -> Void

    private var senderUserId: String {
        request.userAId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(senderUserId.prefix(2).uppercased())
                            .font(.headline)
                            .foregroundColor(.green)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("User \(senderUserId.prefix(8))")
                        .font(.headline)
                    Text("Sent \(formattedDate(request.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                Button {
                    Task {
                        await onAccept()
                    }
                } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.green)
                        .cornerRadius(CornerRadius.md)
                }

                Button {
                    Task {
                        await onDecline()
                    }
                } label: {
                    Text("Decline")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(CornerRadius.md)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private func formattedDate(_ dateString: String) -> String {
        String(dateString.prefix(10))
    }
}

// MARK: - Sent Request Row View
struct SentRequestRowView: View {
    let request: FriendshipResponse
    let currentUserId: String

    private var recipientUserId: String {
        request.userBId
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Color.orange.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Text(recipientUserId.prefix(2).uppercased())
                        .font(.headline)
                        .foregroundColor(.orange)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("User \(recipientUserId.prefix(8))")
                    .font(.headline)
                Text("Pending since \(formattedDate(request.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("Pending")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(CornerRadius.sm)
        }
        .padding(.vertical, Spacing.sm)
    }

    private func formattedDate(_ dateString: String) -> String {
        String(dateString.prefix(10))
    }
}

// MARK: - Blocked User Row View
struct BlockedUserRowView: View {
    let block: FriendshipResponse
    let currentUserId: String
    let onUnblock: () async -> Void

    private var blockedUserId: String {
        block.userAId == currentUserId ? block.userBId : block.userAId
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Color.red.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.red)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("User \(blockedUserId.prefix(8))")
                    .font(.headline)
                Text("Blocked")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            Button {
                Task {
                    await onUnblock()
                }
            } label: {
                Text("Unblock")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Add Friend View
struct AddFriendView: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var searchResults: [UserResponse] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    let onRequestSent: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: Spacing.md) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search by username", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task {
                                await searchUsers()
                            }
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(CornerRadius.md)
                .padding(.horizontal)

                // Results
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    Text("No users found")
                        .foregroundColor(.secondary)
                        .frame(maxHeight: .infinity)
                } else {
                    List(searchResults, id: \.id) { user in
                        UserSearchRowView(user: user) {
                            await sendFriendRequest(to: user)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func searchUsers() async {
        guard !searchText.isEmpty else { return }

        isSearching = true
        errorMessage = nil

        do {
            // Using the search endpoint
            searchResults = try await APIClient.shared.get("/users/search?query=\(searchText)")
        } catch {
            errorMessage = "We couldn't search right now. Check your connection and try again."
        }

        isSearching = false
    }

    private func sendFriendRequest(to user: UserResponse) async {
        do {
            _ = try await APIClient.shared.sendFriendRequest(targetUserId: user.id)
            onRequestSent()
            dismiss()
        } catch {
            errorMessage = "We couldn't send your friend request. Please try again."
        }
    }
}

// MARK: - User Search Row View
struct UserSearchRowView: View {
    let user: UserResponse
    let onAddFriend: () async -> Void
    @State private var isLoading = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(user.username.prefix(2).uppercased())
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.headline)
                Text(user.fullName ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isLoading {
                ProgressView()
            } else {
                Button {
                    isLoading = true
                    Task {
                        await onAddFriend()
                        isLoading = false
                    }
                } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text(title)
                .font(.title2.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error View
struct ErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)

            Text("Error")
                .font(.title2.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FriendsListView()
}
