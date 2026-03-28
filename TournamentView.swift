// Tournament View
// Premium Feature - Browse, create, and manage tournaments

import SwiftUI

struct TournamentView: View {
    @State private var tournaments: [Tournament] = []
    @State private var selectedSport: String = "basketball"
    @State private var selectedFilter: TournamentFilter = .upcoming
    @State private var isLoading = false
    @State private var showCreateSheet = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum TournamentFilter: String, CaseIterable {
        case upcoming = "Upcoming"
        case inProgress = "In Progress"
        case completed = "Completed"
        case myTournaments = "My Tournaments"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Sport Selector
                sportSelector
                
                // Filter Tabs
                filterTabs
                
                // Tournament List
                if isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else if tournaments.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(tournaments) { tournament in
                                NavigationLink(destination: TournamentDetailView(tournament: tournament)) {
                                    TournamentCard(tournament: tournament)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Tournaments")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showCreateSheet = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateTournamentView(sport: selectedSport)
            }
            .task {
                await loadTournaments()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Sport Selector
    
    private var sportSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(["basketball", "football", "soccer", "tennis"], id: \.self) { sport in
                    SportChip(
                        sport: sport,
                        isSelected: selectedSport == sport
                    ) {
                        selectedSport = sport
                        Task {
                            await loadTournaments()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemBackground))
    }
    
    // MARK: - Filter Tabs
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(TournamentFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        selectedFilter = filter
                        Task {
                            await loadTournaments()
                        }
                    }) {
                        Text(filter.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedFilter == filter ? .semibold : .regular)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(selectedFilter == filter ? Color.blue : Color(.systemGray6))
                            .foregroundStyle(selectedFilter == filter ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGray6))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundStyle(.gray)
            
            Text("No Tournaments Yet")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Be the first to create a tournament!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: {
                showCreateSheet = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Tournament")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Data Loading
    
    private func loadTournaments() async {
        isLoading = true
        defer { isLoading = false }
        
        let status: String? = {
            switch selectedFilter {
            case .upcoming: return "registration_open"
            case .inProgress: return "in_progress"
            case .completed: return "completed"
            case .myTournaments: return nil
            }
        }()
        
        do {
            tournaments = try await APIClient.shared.listTournaments(
                sport: selectedSport,
                status: status
            )
        } catch {
            errorMessage = "We couldn't load tournaments right now. Check your connection and try again."
            showError = true
        }
    }
}

// MARK: - Tournament Card

struct TournamentCard: View {
    let tournament: Tournament
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(tournament.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: sportIcon(tournament.sport))
                            .font(.caption)
                        Text(tournament.sport.capitalized)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                statusBadge(tournament.status)
            }
            
            // Info Grid
            HStack(spacing: Spacing.lg) {
                infoItem(icon: "person.3.fill", label: "\(tournament.participantCount)/\(tournament.maxParticipants)")
                infoItem(icon: "trophy.fill", label: tournament.format.replacingOccurrences(of: "_", with: " ").capitalized)
                
                if tournament.isSchool {
                    infoItem(icon: "building.2.fill", label: "School")
                }
            }
            
            // Date
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                Text(formatDate(tournament.startsAt))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    private func infoItem(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.blue)
    }
    
    private func statusBadge(_ status: String) -> some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.2))
            .foregroundStyle(statusColor(status))
            .cornerRadius(6)
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "upcoming", "registration_open": return .blue
        case "in_progress": return .orange
        case "completed": return .green
        default: return .gray
        }
    }
    
    private func sportIcon(_ sport: String) -> String {
        switch sport.lowercased() {
        case "basketball": return "basketball.fill"
        case "football": return "football.fill"
        case "soccer": return "soccerball"
        case "tennis": return "tennisball.fill"
        default: return "sportscourt.fill"
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - Sport Chip

struct SportChip: View {
    let sport: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: sportIcon(sport))
                    .font(.title2)
                
                Text(sport.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .frame(width: 80)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func sportIcon(_ sport: String) -> String {
        switch sport.lowercased() {
        case "basketball": return "basketball.fill"
        case "football": return "football.fill"
        case "soccer": return "soccerball"
        case "tennis": return "tennisball.fill"
        default: return "sportscourt.fill"
        }
    }
}

// MARK: - Tournament Detail View

struct TournamentDetailView: View {
    let tournament: Tournament
    @State private var isRegistered = false
    @State private var bracket: TournamentBracket?
    @State private var standings: [TournamentParticipant] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                tournamentHeader
                
                // Actions
                actionButtons
                
                // Tabs
                TabView {
                    // Info Tab
                    infoTab
                        .tag(0)
                    
                    // Bracket Tab
                    if let bracket = bracket {
                        BracketView(bracket: bracket)
                            .tag(1)
                    }
                    
                    // Standings Tab
                    standingsTab
                        .tag(2)
                }
                .frame(height: 500)
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .padding()
        }
        .navigationTitle(tournament.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBracket()
            await loadStandings()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header
    
    private var tournamentHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: sportIcon(tournament.sport))
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading) {
                    Text(tournament.sport.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(tournament.format.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.headline)
                }
                
                Spacer()
            }
            
            if let description = tournament.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: Spacing.md) {
            if tournament.status == "registration_open" && !isRegistered {
                Button(action: {
                    Task {
                        await register()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.badge.plus.fill")
                            Text("Register")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(isLoading)
            } else if isRegistered {
                Text("Registered ✓")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Info Tab
    
    private var infoTab: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Tournament Details")
                .font(.headline)
            
            detailRow(icon: "person.3.fill", label: "Participants", value: "\(tournament.participantCount) / \(tournament.maxParticipants)")
            detailRow(icon: "calendar", label: "Starts", value: formatDate(tournament.startsAt))
            detailRow(icon: "trophy.fill", label: "Format", value: tournament.format.replacingOccurrences(of: "_", with: " ").capitalized)
            detailRow(icon: "number", label: "Current Round", value: "\(tournament.currentRound)")
            
            if let minElo = tournament.minElo {
                detailRow(icon: "chart.line.uptrend.xyaxis", label: "Min ELO", value: "\(minElo)")
            }
            
            if let maxElo = tournament.maxElo {
                detailRow(icon: "chart.line.uptrend.xyaxis", label: "Max ELO", value: "\(maxElo)")
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
    
    // MARK: - Standings Tab
    
    private var standingsTab: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Standings")
                .font(.headline)
            
            if standings.isEmpty {
                Text("No participants yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, participant in
                    standingRow(rank: index + 1, participant: participant)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
    
    private func standingRow(rank: Int, participant: TournamentParticipant) -> some View {
        HStack {
            Text("#\(rank)")
                .font(.headline)
                .foregroundStyle(rank <= 3 ? .orange : .secondary)
                .frame(width: 40)
            
            Text(participant.username ?? participant.teamName ?? "Unknown")
                .font(.subheadline)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(participant.wins)-\(participant.losses)")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                if let seed = participant.seed {
                    Text("Seed: \(seed)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }
    
    // MARK: - Data Functions
    
    private func loadBracket() async {
        do {
            bracket = try await APIClient.shared.getTournamentBracket(tournamentId: tournament.id)
        } catch {
            // Bracket not generated yet
        }
    }
    
    private func loadStandings() async {
        do {
            standings = try await APIClient.shared.getTournamentStandings(tournamentId: tournament.id)
        } catch {
            // No standings yet
        }
    }
    
    private func register() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await APIClient.shared.registerForTournament(tournamentId: tournament.id)
            isRegistered = true
            await loadStandings()
        } catch {
            errorMessage = "We couldn't register you for this tournament. Please try again."
            showError = true
        }
    }
    
    private func sportIcon(_ sport: String) -> String {
        switch sport.lowercased() {
        case "basketball": return "basketball.fill"
        case "football": return "football.fill"
        case "soccer": return "soccerball"
        case "tennis": return "tennisball.fill"
        default: return "sportscourt.fill"
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

// MARK: - Bracket View

struct BracketView: View {
    let bracket: TournamentBracket
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Round \(bracket.currentRound) of \(bracket.totalRounds)")
                    .font(.headline)
                    .padding()
                
                // Group matches by round
                ForEach(1...bracket.totalRounds, id: \.self) { round in
                    roundSection(round: round)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func roundSection(round: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Round \(round)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            let roundMatches = bracket.matches.filter { $0.roundNumber == round }
            
            ForEach(roundMatches) { match in
                matchCard(match)
            }
        }
    }
    
    private func matchCard(_ match: TournamentMatch) -> some View {
        VStack(spacing: 0) {
            matchupRow(
                name: match.participant1Name ?? "TBD",
                score: match.participant1Score,
                isWinner: match.winnerId == match.participant1Id
            )
            
            Divider()
            
            matchupRow(
                name: match.participant2Name ?? "TBD",
                score: match.participant2Score,
                isWinner: match.winnerId == match.participant2Id
            )
        }
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(match.isComplete ? Color.green : Color(.systemGray4), lineWidth: 1)
        )
    }
    
    private func matchupRow(name: String, score: Int?, isWinner: Bool) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(isWinner ? .primary : .secondary)
            
            Spacer()
            
            if let score = score {
                Text("\(score)")
                    .font(.headline)
                    .fontWeight(isWinner ? .bold : .regular)
                    .foregroundStyle(isWinner ? .green : .secondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Create Tournament View

struct CreateTournamentView: View {
    let sport: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var description = ""
    @State private var format: TournamentFormat = .singleElim
    @State private var maxParticipants = 8
    @State private var isRanked = true
    @State private var startDate = Date().addingTimeInterval(86400 * 7) // 1 week from now
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum TournamentFormat: String, CaseIterable {
        case singleElim = "Single Elimination"
        case doubleElim = "Double Elimination"
        case roundRobin = "Round Robin"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Info") {
                    TextField("Tournament Name", text: $name)
                    TextField("Description (Optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Format") {
                    Picker("Type", selection: $format) {
                        ForEach(TournamentFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    
                    Stepper("Max Participants: \(maxParticipants)", value: $maxParticipants, in: 4...64, step: 4)
                    
                    Toggle("Ranked (ELO-based)", isOn: $isRanked)
                }
                
                Section("Schedule") {
                    DatePicker("Start Date", selection: $startDate, in: Date()...)
                }
                
                Section {
                    Button(action: {
                        Task {
                            await createTournament()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Create Tournament")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(name.isEmpty || isLoading)
                }
            }
            .navigationTitle("Create Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func createTournament() async {
        isLoading = true
        defer { isLoading = false }
        
        let formatter = ISO8601DateFormatter()
        let regOpens = Date()
        let regCloses = startDate.addingTimeInterval(-86400) // 1 day before start
        
        let request = CreateTournamentRequest(
            name: name,
            description: description.isEmpty ? nil : description,
            sport: sport,
            tournamentType: "solo",
            format: formatAPIValue(format),
            rankedType: isRanked ? "ranked" : "unranked",
            maxParticipants: maxParticipants,
            teamSize: 1,
            minElo: nil,
            maxElo: nil,
            registrationOpens: formatter.string(from: regOpens),
            registrationCloses: formatter.string(from: regCloses),
            startsAt: formatter.string(from: startDate),
            isPublic: true,
            isSchool: false,
            isRegional: false,
            region: nil,
            schoolName: nil,
            prizes: [:]
        )
        
        do {
            _ = try await APIClient.shared.createTournament(request: request)
            dismiss()
        } catch {
            errorMessage = "We couldn't create your tournament. Please try again."
            showError = true
        }
    }
    
    private func formatAPIValue(_ format: TournamentFormat) -> String {
        switch format {
        case .singleElim: return "single_elimination"
        case .doubleElim: return "double_elimination"
        case .roundRobin: return "round_robin"
        }
    }
}
