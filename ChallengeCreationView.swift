//
//  ChallengeCreationView.swift
//  SportsHub
//
//  User-created training challenges
//

import SwiftUI

struct ChallengeCreationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sessionManager: SessionManager

    let sport: Sport

    // Only fields that actually reach the backend
    @State private var challengeType: ChallengeType = .individual
    @State private var selectedMetric: ChallengeMetric = .reps  // solo only: passed as challenge category to AI
    @State private var isPublic = true                          // maps to "ranked"/"unranked"
    @State private var inviteFriends: [String] = []             // group only: one request per friend

    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                // Challenge mode
                Section("Challenge Type") {
                    Picker("Type", selection: $challengeType) {
                        ForEach(ChallengeType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if challengeType == .group {
                        NavigationLink {
                            FriendSelectionView(selectedFriends: $inviteFriends)
                        } label: {
                            HStack {
                                Text("Invite Friends")
                                Spacer()
                                Text("\(inviteFriends.count) selected")
                                    .foregroundStyle(Color.appSecondary)
                            }
                        }
                    }
                }

                // Metric — only meaningful for solo (AI uses it to pick challenge category)
                if challengeType == .individual {
                    Section("What to Measure") {
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(ChallengeMetric.allCases, id: \.self) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        Text("The AI will generate a challenge focused on this metric.")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }

                // Visibility — maps public→"ranked", private→"unranked"
                Section("Visibility") {
                    Toggle(isOn: $isPublic) {
                        HStack {
                            Image(systemName: isPublic ? "globe" : "lock.fill")
                                .foregroundStyle(isPublic ? .green : Color.appSecondary)
                            VStack(alignment: .leading) {
                                Text(isPublic ? "Public Challenge" : "Private Challenge")
                                Text(isPublic ? "Anyone can join" : "Invite only")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLoading ? "Creating…" : "Create") {
                        Task { await createChallenge() }
                    }
                    .disabled(!isFormValid || isLoading)
                }
            }
            .alert("Challenge Created!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your challenge has been created successfully!")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        // Group mode requires at least one friend selected; solo is always ready
        if challengeType == .group { return !inviteFriends.isEmpty }
        return true
    }

    // MARK: - Submit

    private func createChallenge() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if challengeType == .group && !inviteFriends.isEmpty {
                // One match request per invited friend.
                // matchType must be "ranked" or "unranked" — the only values the backend MatchType enum accepts.
                for friendId in inviteFriends {
                    let request = CreateChallengeRequest(
                        opponentId: friendId,
                        sport: sport.rawValue,
                        matchType: isPublic ? "ranked" : "unranked"
                    )
                    _ = try await APIClient.shared.createChallenge(request: request)
                }
            } else {
                // Solo: AI generates a sport-specific challenge based on metric category.
                _ = try await APIClient.shared.generateChallenge(
                    sport: sport,
                    challengeType: selectedMetric.rawValue.lowercased()
                )
            }
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Supporting Types

enum ChallengeType: String, CaseIterable {
    case individual = "Solo"
    case group = "Group"

    var icon: String {
        switch self {
        case .individual: return "person.fill"
        case .group: return "person.3.fill"
        }
    }
}

enum ChallengeMetric: String, CaseIterable {
    case reps = "Repetitions"
    case makes = "Makes"
    case accuracy = "Accuracy"
    case distance = "Distance"
    case time = "Time"
    case sets = "Sets"
    case points = "Points"

    var unit: String {
        switch self {
        case .reps: return "reps"
        case .makes: return "makes"
        case .accuracy: return "%"
        case .distance: return "m"
        case .time: return "sec"
        case .sets: return "sets"
        case .points: return "pts"
        }
    }
}

// MARK: - Friend Selection View

struct FriendSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedFriends: [String]

    @State private var friends: [FriendPreview] = []
    @State private var searchText = ""

    var body: some View {
        List {
            ForEach(filteredFriends) { friend in
                Button(action: { toggleFriend(friend.id) }) {
                    HStack {
                        AvatarView(name: friend.name, size: 40)

                        VStack(alignment: .leading) {
                            Text(friend.name)
                                .foregroundStyle(Color.appTextPrimary)
                            Text("@\(friend.username)")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }

                        Spacer()

                        if selectedFriends.contains(friend.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search friends")
        .navigationTitle("Invite Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { loadFriends() }
    }

    private var filteredFriends: [FriendPreview] {
        if searchText.isEmpty { return friends }
        return friends.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func toggleFriend(_ id: String) {
        if let index = selectedFriends.firstIndex(of: id) {
            selectedFriends.remove(at: index)
        } else {
            selectedFriends.append(id)
        }
    }

    private func loadFriends() {
        Task {
            do {
                let friendships = try await APIClient.shared.getFriends()
                let currentUserId = SessionManager.shared.currentUser?.id.uuidString ?? ""
                friends = friendships.map { friendship in
                    let friendId = friendship.userAId == currentUserId ? friendship.userBId : friendship.userAId
                    return FriendPreview(
                        id: friendId,
                        name: "User \(friendId.prefix(8))",
                        username: friendId.prefix(8).lowercased()
                    )
                }
            } catch {
                friends = []
            }
        }
    }
}

struct FriendPreview: Identifiable {
    let id: String
    let name: String
    let username: String
}

#Preview {
    ChallengeCreationView(sport: .basketball)
        .environmentObject(SessionManager.shared)
}
