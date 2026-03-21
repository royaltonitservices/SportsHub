//
//  TeamLobbyView.swift
//  SportsHub
//
//  Team formation and team-based challenges
//

import SwiftUI

struct TeamLobbyView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    
    let sport: Sport
    
    @State private var teamSize: TeamSize = .threeVthree
    @State private var lobbyType: LobbyType = .open
    @State private var teamName = ""
    @State private var teamMembers: [TeamMember] = []
    @State private var availableLobbies: [TeamLobby] = []
    @State private var selectedTab: LobbyTab = .create
    @State private var isCreatingLobby = false
    @State private var isJoiningLobby = false
    @State private var showInviteFriends = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Selector
                Picker("", selection: $selectedTab) {
                    ForEach(LobbyTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(Spacing.md)
                
                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    createTeamView
                        .tag(LobbyTab.create)
                    
                    joinTeamView
                        .tag(LobbyTab.join)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color.appBackground)
            .navigationTitle("Team Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showInviteFriends) {
                FriendSelectionView(selectedFriends: .constant([]))
            }
        }
    }
    
    // MARK: - Create Team View
    
    private var createTeamView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Team Configuration
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(icon: "person.3.fill", title: "Team Configuration")
                    
                    VStack(spacing: Spacing.sm) {
                        // Team Name
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Team Name")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            TextField("Enter team name", text: $teamName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Sport (Fixed)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Sport")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            HStack {
                                Image(systemName: sport.icon)
                                Text(sport.rawValue)
                            }
                            .foregroundStyle(Color.appPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.appCardBackground)
                            .cornerRadius(8)
                        }
                        
                        // Team Size
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Team Size")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            Picker("Team Size", selection: $teamSize) {
                                ForEach(TeamSize.allCases, id: \.self) { size in
                                    Text(size.rawValue).tag(size)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Lobby Type
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Lobby Type")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            Picker("Lobby Type", selection: $lobbyType) {
                                ForEach(LobbyType.allCases, id: \.self) { type in
                                    HStack {
                                        Image(systemName: type.icon)
                                        Text(type.rawValue)
                                    }
                                    .tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Current Team Members
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(icon: "person.2.fill", title: "Team Members (\(teamMembers.count + 1)/\(teamSize.playersPerTeam))")
                    
                    VStack(spacing: Spacing.sm) {
                        // Captain (current user)
                        TeamMemberRow(
                            name: sessionManager.currentUser?.displayName ?? "You",
                            username: sessionManager.currentUser?.username ?? "",
                            role: "Captain",
                            isConfirmed: true
                        )
                        
                        // Team members
                        ForEach(teamMembers) { member in
                            TeamMemberRow(
                                name: member.name,
                                username: member.username,
                                role: "Member",
                                isConfirmed: member.isConfirmed
                            )
                        }
                        
                        // Empty slots
                        ForEach(0..<(teamSize.playersPerTeam - teamMembers.count - 1), id: \.self) { _ in
                            EmptySlotRow()
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Invite Friends Button
                Button(action: {
                    showInviteFriends = true
                }) {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Invite Friends")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.appPrimary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appPrimary.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal, Spacing.md)
                
                // Create Lobby Button
                Button(action: {
                    createLobby()
                }) {
                    HStack {
                        if isCreatingLobby {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Create Team Lobby")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isCreateFormValid ? Color.appPrimary : Color.appTextSecondary.opacity(0.3))
                    .cornerRadius(12)
                }
                .disabled(!isCreateFormValid || isCreatingLobby)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .padding(.vertical, Spacing.md)
        }
    }
    
    // MARK: - Join Team View
    
    private var joinTeamView: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if availableLobbies.isEmpty {
                    // Empty State
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.appTextSecondary.opacity(0.3))
                        
                        Text("No Active Lobbies")
                            .font(.headline)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Text("Be the first to create a team lobby for \(sport.rawValue)!")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl * 2)
                } else {
                    ForEach(availableLobbies) { lobby in
                        LobbyCard(lobby: lobby, onJoin: {
                            joinLobby(lobby)
                        })
                    }
                }
            }
            .padding(Spacing.md)
        }
        .onAppear {
            loadAvailableLobbies()
        }
    }
    
    // MARK: - Form Validation
    
    private var isCreateFormValid: Bool {
        !teamName.isEmpty && teamName.count >= 3
    }
    
    // MARK: - Actions
    
    private func createLobby() {
        isCreatingLobby = true
        
        // TODO: API call to create team lobby
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isCreatingLobby = false
            // Switch to join tab or dismiss
            selectedTab = .join
            loadAvailableLobbies()
        }
    }
    
    private func joinLobby(_ lobby: TeamLobby) {
        isJoiningLobby = true
        
        // TODO: API call to join lobby
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isJoiningLobby = false
        }
    }
    
    private func loadAvailableLobbies() {
        // TODO: Load from API
        availableLobbies = [
            TeamLobby(
                id: "1",
                name: "Elite Squad",
                captain: "Alex J",
                sport: sport,
                teamSize: .fiveVfive,
                currentPlayers: 3,
                lobbyType: .open
            ),
            TeamLobby(
                id: "2",
                name: "Weekend Warriors",
                captain: "Sam T",
                sport: sport,
                teamSize: .threeVthree,
                currentPlayers: 2,
                lobbyType: .open
            )
        ]
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.appPrimary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
        }
    }
}

struct TeamMemberRow: View {
    let name: String
    let username: String
    let role: String
    let isConfirmed: Bool
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            AvatarView(name: name, size: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    if role == "Captain" {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(Color.appSecondary)
                    }
                }
                
                Text("@\(username)")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            
            Spacer()
            
            if isConfirmed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Pending")
                    .font(.caption)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.appSecondary.opacity(0.2))
                    .foregroundStyle(Color.appSecondary)
                    .cornerRadius(8)
            }
        }
        .padding(Spacing.sm)
        .background(Color.appCardBackground)
        .cornerRadius(10)
    }
}

struct EmptySlotRow: View {
    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(Color.appTextSecondary.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.fill.questionmark")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary.opacity(0.5))
                )
            
            Text("Open Slot")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            
            Spacer()
        }
        .padding(Spacing.sm)
        .background(Color.appCardBackground.opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.appTextSecondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}

struct LobbyCard: View {
    let lobby: TeamLobby
    let onJoin: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(lobby.name)
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Image(systemName: lobby.lobbyType.icon)
                            .font(.caption)
                            .foregroundStyle(lobby.lobbyType == .open ? .green : Color.appSecondary)
                    }
                    
                    Text("Captain: \(lobby.captain)")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(lobby.currentPlayers)/\(lobby.teamSize.playersPerTeam)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appPrimary)
                    
                    Text("players")
                        .font(.caption2)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            
            HStack {
                Label(lobby.sport.rawValue, systemImage: lobby.sport.icon)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                Text("•")
                    .foregroundStyle(Color.appTextSecondary)
                
                Text(lobby.teamSize.rawValue)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                Spacer()
                
                Button(action: onJoin) {
                    Text("Join")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.appPrimary)
                        .cornerRadius(8)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

// MARK: - Supporting Types

enum LobbyTab: String, CaseIterable {
    case create = "Create"
    case join = "Join"
}

enum TeamSize: String, CaseIterable {
    case twoVtwo = "2v2"
    case threeVthree = "3v3"
    case fiveVfive = "5v5"
    
    var playersPerTeam: Int {
        switch self {
        case .twoVtwo: return 2
        case .threeVthree: return 3
        case .fiveVfive: return 5
        }
    }
}

enum LobbyType: String, CaseIterable {
    case open = "Open"
    case inviteOnly = "Invite Only"
    
    var icon: String {
        switch self {
        case .open: return "globe"
        case .inviteOnly: return "lock.fill"
        }
    }
}

struct TeamMember: Identifiable {
    let id = UUID()
    let name: String
    let username: String
    let isConfirmed: Bool
}

struct TeamLobby: Identifiable {
    let id: String
    let name: String
    let captain: String
    let sport: Sport
    let teamSize: TeamSize
    let currentPlayers: Int
    let lobbyType: LobbyType
}

#Preview {
    TeamLobbyView(sport: .basketball)
        .environmentObject(SessionManager.shared)
}
