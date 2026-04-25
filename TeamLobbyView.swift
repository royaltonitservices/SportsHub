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
    @State private var myTeams: [TeamResponse] = []
    @State private var selectedTab: LobbyTab = .create
    @State private var isCreatingLobby = false
    @State private var isLoadingLobbies = false
    @State private var showInviteFriends = false
    @State private var createError: String?
    @State private var joinError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("", selection: $selectedTab) {
                    ForEach(LobbyTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(Spacing.md)
                .background(Color.appBackground)

                if selectedTab == .create {
                    createTeamView
                } else {
                    joinTeamView
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Team Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .join { Task { await loadAvailableLobbies() } }
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
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Team Name")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            TextField("Enter team name", text: $teamName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Sport")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            HStack {
                                Image(systemName: sport.icon)
                                Text(sport.rawValue.capitalized)
                            }
                            .foregroundStyle(Color.appPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.appCardBackground)
                            .cornerRadius(8)
                        }

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
                    }
                }
                .padding(Spacing.md)
                .cardBackground()

                // Current Team Members
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader(icon: "person.2.fill", title: "Team Members (1/\(teamSize.playersPerTeam))")

                    VStack(spacing: Spacing.sm) {
                        TeamMemberRow(
                            name: sessionManager.currentUser?.displayName ?? "You",
                            username: sessionManager.currentUser?.username ?? "",
                            role: "Captain",
                            isConfirmed: true
                        )

                        ForEach(teamMembers) { member in
                            TeamMemberRow(name: member.name, username: member.username, role: "Member", isConfirmed: member.isConfirmed)
                        }

                        ForEach(0..<(teamSize.playersPerTeam - teamMembers.count - 1), id: \.self) { _ in
                            EmptySlotRow()
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()

                if let error = createError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.appError)
                        .padding(.horizontal, Spacing.md)
                }

                // My Teams (existing)
                if !myTeams.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SectionHeader(icon: "list.bullet", title: "Your Teams")
                        VStack(spacing: Spacing.sm) {
                            ForEach(myTeams) { team in
                                myTeamRow(team)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .cardBackground()
                }

                // Create Lobby Button
                Button(action: { Task { await createLobby() } }) {
                    HStack {
                        if isCreatingLobby {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Create Team")
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
        .task {
            await loadMyTeams()
        }
    }

    private func myTeamRow(_ team: TeamResponse) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)
                Text("Rating: \(team.rating) • W\(team.wins)/L\(team.losses)")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            Spacer()
            Image(systemName: "crown.fill")
                .font(.caption)
                .foregroundStyle(Color.appSecondary)
        }
        .padding(Spacing.sm)
        .background(Color.appCardBackground)
        .cornerRadius(10)
    }

    // MARK: - Join Team View

    private var joinTeamView: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if isLoadingLobbies {
                    ProgressView()
                        .padding(.vertical, Spacing.xl)
                } else if availableLobbies.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.appTextSecondary.opacity(0.3))
                        Text("No Active Lobbies")
                            .font(.headline)
                            .foregroundStyle(Color.appTextSecondary)
                        Text("Be the first to create a team lobby for \(sport.rawValue.capitalized)!")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl * 2)
                } else {
                    if let error = joinError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.appError)
                            .padding(.horizontal, Spacing.md)
                    }
                    ForEach(availableLobbies) { lobby in
                        LobbyCard(lobby: lobby, onJoin: {
                            Task { await joinLobby(lobby) }
                        })
                    }
                }
            }
            .padding(Spacing.md)
        }
        .task {
            await loadAvailableLobbies()
        }
        .refreshable {
            await loadAvailableLobbies()
        }
    }

    // MARK: - Form Validation

    private var isCreateFormValid: Bool {
        !teamName.isEmpty && teamName.count >= 3
    }

    // MARK: - Actions

    private func loadMyTeams() async {
        do {
            myTeams = try await APIClient.shared.getMyTeams()
        } catch {
            // Non-critical — user may have no teams
        }
    }

    private func createLobby() async {
        isCreatingLobby = true
        createError = nil
        defer { isCreatingLobby = false }

        do {
            let team = try await APIClient.shared.createTeam(name: teamName, sport: sport.rawValue)
            myTeams.insert(team, at: 0)
            teamName = ""
            selectedTab = .join
            await loadAvailableLobbies()
        } catch let apiError as APIError {
            createError = apiError.localizedDescription
        } catch {
            createError = "Couldn't create team. Please try again."
        }
    }

    private func joinLobby(_ lobby: TeamLobby) async {
        // Team-vs-team challenges require a dedicated matchmaking flow that is not yet built.
        // Direct the user to the Play tab where 1v1 challenges with any opponent are available.
        joinError = "Team challenges are coming soon. To play against \(lobby.captain), find them through the Play tab and send a 1v1 challenge."
    }

    private func loadAvailableLobbies() async {
        isLoadingLobbies = true
        joinError = nil
        defer { isLoadingLobbies = false }

        do {
            let openTeams = try await APIClient.shared.getOpenTeams(sport: sport.rawValue)
            availableLobbies = openTeams.map { team in
                TeamLobby(
                    id: team.id,
                    name: team.name,
                    captain: "@\(team.captainUsername)",
                    sport: sport,
                    teamSize: .threeVthree,
                    currentPlayers: team.memberCount,
                    lobbyType: .open
                )
            }
        } catch {
            joinError = "Couldn't load lobbies. Pull to refresh."
        }
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
                Label(lobby.sport.rawValue.capitalized, systemImage: lobby.sport.icon)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                Text("•")
                    .foregroundStyle(Color.appTextSecondary)
                Text(lobby.teamSize.rawValue)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Button(action: onJoin) {
                    Text("Challenge")
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
    case join = "Browse"
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
