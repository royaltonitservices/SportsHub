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
        .navigationTitle("Performance Analytics")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }
    
    private var ratingChart: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Rating Progression")
                .font(.headline)
                .foregroundColor(.appTextPrimary)
                .padding(.horizontal, Spacing.md)
            
            if ratingHistory.isEmpty {
                Text("No rating data available")
                    .foregroundColor(.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
            } else {
                Chart(ratingHistory) { dataPoint in
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
            
            if matchStats.isEmpty {
                Text("No match data available")
                    .foregroundColor(.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 200)
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
            
            if matchStats.isEmpty {
                Text("No performance data available")
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
            
            if matchStats.isEmpty {
                Text("No recent matches")
                    .foregroundColor(.appSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.md)
            } else {
                ForEach(matchStats.prefix(5)) { match in
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
        let minValue = ratingHistory.map(\.rating).min() ?? 1500
        return max(minValue - 100, 0)
    }
    
    private var maxRating: Int {
        let maxValue = ratingHistory.map(\.rating).max() ?? 1500
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
    
    private var winLossPieData: [PieChartData] {
        let wins = matchStats.filter { $0.result == .win }.count
        let losses = matchStats.filter { $0.result == .loss }.count
        let total = wins + losses
        
        guard total > 0 else { return [] }
        
        return [
            PieChartData(label: "Wins", count: wins, color: .green, percentage: Double(wins) / Double(total) * 100),
            PieChartData(label: "Losses", count: losses, color: .red, percentage: Double(losses) / Double(total) * 100)
        ]
    }
    
    private var totalMatches: Int {
        matchStats.count
    }
    
    private var winRate: Double {
        guard !matchStats.isEmpty else { return 0 }
        let wins = matchStats.filter { $0.result == .win }.count
        return Double(wins) / Double(matchStats.count) * 100
    }
    
    private var averageRatingChangeText: String {
        guard !matchStats.isEmpty else { return "+0" }
        let avg = matchStats.map { $0.ratingChange }.reduce(0, +) / matchStats.count
        return avg >= 0 ? "+\(avg)" : "\(avg)"
    }
    
    private var bestStreak: Int {
        var currentStreak = 0
        var maxStreak = 0
        
        for match in matchStats.reversed() {
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
        let recent = matchStats.prefix(5)
        let wins = recent.filter { $0.result == .win }.count
        
        if wins >= 4 { return "🔥 Hot" }
        else if wins >= 3 { return "📈 Good" }
        else if wins >= 2 { return "➡️ Average" }
        else { return "📉 Cold" }
    }
    
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        // Placeholder - implement API call
        // Mock data for demonstration
        ratingHistory = generateMockRatingData()
        matchStats = generateMockMatchStats()
    }
    
    private func generateMockRatingData() -> [RatingDataPoint] {
        let now = Date()
        var data: [RatingDataPoint] = []
        var rating = 1500
        
        for i in (0..<30).reversed() {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: now)!
            rating += Int.random(in: -20...30)
            data.append(RatingDataPoint(date: date, rating: rating))
        }
        
        return data
    }
    
    private func generateMockMatchStats() -> [MatchStat] {
        (0..<10).map { i in
            MatchStat(
                opponent: "Player \(i + 1)",
                result: Bool.random() ? .win : .loss,
                date: Calendar.current.date(byAdding: .day, value: -i, to: Date())!,
                ratingChange: Int.random(in: -25...35)
            )
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
                
                Text("vs \(match.opponent)")
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
