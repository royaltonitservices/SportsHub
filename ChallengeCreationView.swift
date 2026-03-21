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
    
    @State private var challengeName = ""
    @State private var description = ""
    @State private var difficulty: ChallengeDifficulty = .intermediate
    @State private var duration = 30
    @State private var challengeType: ChallengeType = .individual
    @State private var requiresProof = true
    @State private var selectedMetric: ChallengeMetric = .reps
    @State private var targetValue = ""
    @State private var isPublic = true
    @State private var inviteFriends: [String] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showSuccess = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Information
                Section("Challenge Details") {
                    TextField("Challenge Name", text: $challengeName)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    Picker("Sport", selection: .constant(sport)) {
                        Text(sport.rawValue).tag(sport)
                    }
                    .disabled(true)
                    
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(ChallengeDifficulty.allCases, id: \.self) { diff in
                            HStack {
                                Image(systemName: diff.icon)
                                Text(diff.rawValue)
                            }
                            .tag(diff)
                        }
                    }
                }
                
                // Goal & Metrics
                Section("Challenge Goal") {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Stepper("\(duration) min", value: $duration, in: 5...120, step: 5)
                    }
                    
                    Picker("Metric Type", selection: $selectedMetric) {
                        ForEach(ChallengeMetric.allCases, id: \.self) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    
                    HStack {
                        Text("Target")
                        Spacer()
                        TextField("Value", text: $targetValue)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text(selectedMetric.unit)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                
                // Challenge Type & Settings
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
                
                // Verification Settings
                Section("Verification") {
                    Toggle(isOn: $requiresProof) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(Color.appPrimary)
                            VStack(alignment: .leading) {
                                Text("Require Photo/Video Proof")
                                Text("Participants must submit evidence")
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                            }
                        }
                    }
                    
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
                
                // Preview
                Section("Preview") {
                    ChallengePreviewCard(
                        name: challengeName.isEmpty ? "Challenge Name" : challengeName,
                        description: description.isEmpty ? "Challenge description will appear here" : description,
                        sport: sport,
                        difficulty: difficulty,
                        duration: duration,
                        metric: selectedMetric,
                        target: targetValue.isEmpty ? "?" : targetValue,
                        requiresProof: requiresProof
                    )
                }
            }
            .navigationTitle("Create Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createChallenge()
                        }
                    }
                    .disabled(!isFormValid || isLoading)
                }
            }
            .alert("Challenge Created!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
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
    
    // MARK: - Form Validation
    
    private var isFormValid: Bool {
        !challengeName.isEmpty &&
        !description.isEmpty &&
        !targetValue.isEmpty &&
        Int(targetValue) != nil &&
        Int(targetValue)! > 0
    }
    
    // MARK: - Create Challenge
    
    private func createChallenge() async {
        isLoading = true
        
        // TODO: API call to create challenge
        // For now, simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        isLoading = false
        showSuccess = true
    }
}

// MARK: - Supporting Types

enum ChallengeDifficulty: String, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case expert = "Expert"
    
    var icon: String {
        switch self {
        case .beginner: return "star"
        case .intermediate: return "star.leadinghalf.filled"
        case .advanced: return "star.fill"
        case .expert: return "flame.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .beginner: return .green
        case .intermediate: return Color.appSecondary
        case .advanced: return .red
        case .expert: return .purple
        }
    }
}

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

// MARK: - Challenge Preview Card

struct ChallengePreviewCard: View {
    let name: String
    let description: String
    let sport: Sport
    let difficulty: ChallengeDifficulty
    let duration: Int
    let metric: ChallengeMetric
    let target: String
    let requiresProof: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: sport.icon)
                            .font(.caption)
                        Text(sport.rawValue)
                            .font(.caption)
                        
                        Text("•")
                        
                        HStack(spacing: 4) {
                            Image(systemName: difficulty.icon)
                                .font(.caption)
                            Text(difficulty.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(difficulty.color)
                    }
                    .foregroundStyle(Color.appTextSecondary)
                }
                
                Spacer()
                
                // Target badge
                VStack(spacing: 2) {
                    Text(target)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appPrimary)
                    Text(metric.unit)
                        .font(.caption2)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color.appPrimary.opacity(0.1))
                .cornerRadius(8)
            }
            
            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(2)
            
            HStack(spacing: Spacing.md) {
                Label("\(duration) min", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                if requiresProof {
                    Label("Proof Required", systemImage: "camera")
                        .font(.caption)
                        .foregroundStyle(Color.appSecondary)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.appCardBackground)
        .cornerRadius(12)
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
                Button(action: {
                    toggleFriend(friend.id)
                }) {
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
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadFriends()
        }
    }
    
    private var filteredFriends: [FriendPreview] {
        if searchText.isEmpty {
            return friends
        }
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
        // TODO: Load from API
        friends = [
            FriendPreview(id: "1", name: "Alex Johnson", username: "alexj"),
            FriendPreview(id: "2", name: "Sam Taylor", username: "samtay"),
            FriendPreview(id: "3", name: "Jordan Lee", username: "jlee")
        ]
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
