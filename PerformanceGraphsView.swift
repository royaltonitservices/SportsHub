//
//  PerformanceGraphsView.swift
//  SportsHub
//
//  Performance analytics with charts
//

import SwiftUI
import Charts

struct PerformanceGraphsView: View {
    let sport: Sport
    @State private var ratingHistory: [RatingDataPoint] = []
    @State private var matchStats: [MatchStat] = []
    @State private var selectedTimeRange: TimeRange = .month
    @State private var isLoading = false
    @State private var loadFailed = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Time range selector
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.md)

                // Period-level info card: data exists globally but nothing in selected window
                if !matchStats.isEmpty && filteredMatchStats.isEmpty && !isLoading && !loadFailed {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Color.appPrimary)
                        Text("No matches in this period — try a wider time range.")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(Color.appPrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    .padding(.horizontal, Spacing.md)
                }

                // No matches at all
                if matchStats.isEmpty && !isLoading && !loadFailed {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.appTextSecondary.opacity(0.4))
                        Text("No match history yet")
                            .font(.headline)
                            .foregroundStyle(Color.appTextSecondary)
                        Text("Play some games to see your performance stats appear here.")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                    .cardBackground()
                    .padding(.horizontal, Spacing.md)
                }

                // Rating over time
                ratingChart
                
                // Win/Loss ratio
                winLossChart
                
                // Performance breakdown
                performanceBreakdown
                
                // Recent matches
                recentMatchesSection
            }
            .padding(.bottom, Spacing.xl)
        }
        .overlay(alignment: .top) {
            if isLoading {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Loading your stats…")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(Spacing.sm)
                .background(Color.appPrimary.opacity(0.85))
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if loadFailed {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text("Couldn't load data.")
                        .font(.caption)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Retry") {
                        Task {
                            loadFailed = false
                            await loadData()
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.25))
                    .clipShape(Capsule())
                }
                .padding(Spacing.sm)
                .background(Color.appError)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.3), value: loadFailed)
        .navigationTitle("Performance Analytics")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadData()
        }
        .refreshable {
            loadFailed = false
            await loadData()
        }
    }
    
    private var ratingChart: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rating Progression (Estimated)")
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)
                Text("Based on standard Elo estimates · not a stored snapshot")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.horizontal, Spacing.md)

            if filteredRatingHistory.count <= 1 {
                Text(ratingHistory.count <= 1 ? "No matches yet" : "No matches in this period")
                    .foregroundColor(.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 120)
            } else {
                Chart(filteredRatingHistory) { dataPoint in
                    LineMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Rating", dataPoint.rating)
                    )
                    .foregroundStyle(Color.appPrimary)
                    .interpolationMethod(.catmullRom)
                    
                    AreaMark(
                        x: .value("Date", dataPoint.date),
                        y: .value("Rating", dataPoint.rating)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appPrimary.opacity(0.3), Color.appPrimary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
                .frame(height: 200)
                .chartYScale(domain: minRating...maxRating)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: strideCount)) { value in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.vertical, Spacing.md)
        .background(Color.appCardBackground)
        .cornerRadius(CornerRadius.md)
        .padding(.horizontal, Spacing.md)
    }
    
    private var winLossChart: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Win/Loss Distribution")
                .font(.headline)
                .foregroundColor(.appTextPrimary)
                .padding(.horizontal, Spacing.md)
            
            if filteredMatchStats.isEmpty {
                Text(matchStats.isEmpty ? "No matches yet" : "No matches in this period")
                    .foregroundColor(.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 150)
            } else {
                HStack(spacing: Spacing.xl) {
                    // Pie chart using Charts
                    Chart(winLossPieData) { item in
                        SectorMark(
                            angle: .value("Count", item.count),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .foregroundStyle(item.color)
                    }
                    .frame(width: 150, height: 150)
                    
                    // Legend
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(winLossPieData) { item in
                            HStack(spacing: Spacing.sm) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 12, height: 12)
                                
                                Text(item.label)
                                    .font(.subheadline)
                                    .foregroundColor(.appTextPrimary)
                                
                                Spacer()
                                
                                Text("\(item.count)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.appTextPrimary)
                                
                                Text("(\(item.percentage, specifier: "%.1f")%)")
                                    .font(.caption)
                                    .foregroundColor(.appSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.vertical, Spacing.md)
        .background(Color.appCardBackground)
        .cornerRadius(CornerRadius.md)
        .padding(.horizontal, Spacing.md)
    }
    
    private var performanceBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Performance Breakdown")
                .font(.headline)
                .foregroundColor(.appTextPrimary)
                .padding(.horizontal, Spacing.md)
            
            if filteredMatchStats.isEmpty {
                Text(matchStats.isEmpty ? "No matches yet" : "No matches in this period")
                    .foregroundColor(.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.md)
            } else {
                VStack(spacing: Spacing.sm) {
                    StatRow(title: "Matches Played", value: "\(totalMatches)")
                    StatRow(title: "Win Rate", value: String(format: "%.1f%%", winRate))
                    StatRow(title: "Average Rating Change", value: averageRatingChangeText)
                    StatRow(title: "Best Win Streak", value: "\(bestStreak)")
                    StatRow(title: "Current Form", value: currentForm)
                }
                .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.vertical, Spacing.md)
        .background(Color.appCardBackground)
        .cornerRadius(CornerRadius.md)
        .padding(.horizontal, Spacing.md)
    }
    
    private var recentMatchesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Recent Matches")
                .font(.headline)
                .foregroundColor(.appTextPrimary)
                .padding(.horizontal, Spacing.md)
            
            if filteredMatchStats.isEmpty {
                Text(matchStats.isEmpty ? "No matches yet" : "No matches in this period")
                    .foregroundColor(.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.md)
            } else {
                ForEach(filteredMatchStats.prefix(5)) { match in
                    RecentMatchRow(match: match)
                }
            }
        }
        .padding(.vertical, Spacing.md)
        .background(Color.appCardBackground)
        .cornerRadius(CornerRadius.md)
        .padding(.horizontal, Spacing.md)
    }
    
    // Computed properties
    private var minRating: Int {
        let minValue = filteredRatingHistory.map(\.rating).min() ?? 1500
        return max(minValue - 100, 0)
    }
    
    private var maxRating: Int {
        let maxValue = filteredRatingHistory.map(\.rating).max() ?? 1500
        return maxValue + 100
    }
    
    private var strideCount: Int {
        switch selectedTimeRange {
        case .week: return 1
        case .month: return 7
        case .threeMonths: return 14
        case .year: return 30
        }
    }

    private func cutoffDate(for range: TimeRange) -> Date {
        let calendar = Calendar.current
        let now = Date()
        switch range {
        case .week: return calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .year: return calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }

    /// Rating history filtered to the selected time range.
    private var filteredRatingHistory: [RatingDataPoint] {
        let cutoff = cutoffDate(for: selectedTimeRange)
        return ratingHistory.filter { $0.date >= cutoff }
    }

    /// Match stats filtered to the selected time range.
    private var filteredMatchStats: [MatchStat] {
        let cutoff = cutoffDate(for: selectedTimeRange)
        return matchStats.filter { $0.date >= cutoff }
    }
    
    private var winLossPieData: [PieChartData] {
        let wins = filteredMatchStats.filter { $0.result == .win }.count
        let losses = filteredMatchStats.filter { $0.result == .loss }.count
        let total = wins + losses
        
        guard total > 0 else { return [] }
        
        return [
            PieChartData(label: "Wins", count: wins, color: .green, percentage: Double(wins) / Double(total) * 100),
            PieChartData(label: "Losses", count: losses, color: .red, percentage: Double(losses) / Double(total) * 100)
        ]
    }
    
    private var totalMatches: Int {
        filteredMatchStats.count
    }
    
    private var winRate: Double {
        guard !filteredMatchStats.isEmpty else { return 0 }
        let wins = filteredMatchStats.filter { $0.result == .win }.count
        return Double(wins) / Double(filteredMatchStats.count) * 100
    }
    
    private var averageRatingChangeText: String {
        guard !filteredMatchStats.isEmpty else { return "+0" }
        let avg = filteredMatchStats.map { $0.ratingChange }.reduce(0, +) / filteredMatchStats.count
        return avg >= 0 ? "+\(avg)" : "\(avg)"
    }
    
    private var bestStreak: Int {
        var currentStreak = 0
        var maxStreak = 0
        
        for match in filteredMatchStats.reversed() {
            if match.result == .win {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }
        
        return maxStreak
    }
    
    private var currentForm: String {
        let recent = filteredMatchStats.prefix(5)
        let wins = recent.filter { $0.result == .win }.count
        
        if wins >= 4 { return "🔥 Hot" }
        else if wins >= 3 { return "📈 Good" }
        else if wins >= 2 { return "➡️ Average" }
        else { return "📉 Cold" }
    }
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        let currentUserId = SessionManager.shared.currentUser?.id.uuidString ?? ""
        let now = Date()
        
        do {
            // Load current sport profile (real rating, games played)
            let profile = try await APIClient.shared.getSportProfile(sport: sport.rawValue)
            
            // Load real completed match history from backend
            let recentMatches = try await APIClient.shared.getRecentMatches(
                sport: sport.rawValue.lowercased(),
                limit: 20
            )
            
            // Build match stats from real data
            let isoFormatter = ISO8601DateFormatter()
            matchStats = recentMatches.prefix(10).compactMap { challenge in
                let isWinner = challenge.winnerUserId == currentUserId
                let matchDate: Date
                if let completedAt = challenge.completedAt,
                   let parsed = isoFormatter.date(from: completedAt) {
                    matchDate = parsed
                } else {
                    return nil  // Skip matches with no completion date
                }
                return MatchStat(
                    opponent: "Opponent",
                    result: isWinner ? .win : .loss,
                    date: matchDate,
                    ratingChange: isWinner ? 15 : -10
                )
            }
            
            // Build estimated rating progression from real match outcomes.
            // We don't store rating snapshots, so we walk backward from the current
            // rating using standard Elo estimates (+15 win, -10 loss).
            // This is an estimate, not exact history.
            var estimatedRating = profile.rating
            var history: [RatingDataPoint] = [RatingDataPoint(date: now, rating: estimatedRating)]
            
            for match in matchStats {
                let ratingBefore = estimatedRating - (match.result == .win ? 15 : -10)
                history.insert(RatingDataPoint(date: match.date, rating: ratingBefore), at: 0)
                estimatedRating = ratingBefore
            }
            
            ratingHistory = history
            
        } catch {
            print("Failed to load performance data: \(error)")
            ratingHistory = []
            matchStats = []
            loadFailed = true
        }
    }
}

struct RatingDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let rating: Int
}

struct MatchStat: Identifiable {
    let id = UUID()
    let opponent: String
    let result: PerformanceMatchResult
    let date: Date
    let ratingChange: Int
}

enum PerformanceMatchResult {
    case win
    case loss
}

enum TimeRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"
    case year = "Year"
}

struct PieChartData: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let color: Color
    let percentage: Double
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.appSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.appTextPrimary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct RecentMatchRow: View {
    let match: MatchStat
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            Circle()
                .fill(match.result == .win ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(match.result == .win ? "Victory" : "Defeat")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.appTextPrimary)
                
                Text(match.opponent.isEmpty || match.opponent == "Opponent" ? "Ranked Match" : "vs \(match.opponent)")
                    .font(.caption)
                    .foregroundColor(.appSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(match.ratingChange >= 0 ? "+\(match.ratingChange)" : "\(match.ratingChange)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(match.ratingChange >= 0 ? .green : .red)
                
                Text(match.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.appSecondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

#Preview {
    NavigationStack {
        PerformanceGraphsView(sport: .basketball)
    }
}
