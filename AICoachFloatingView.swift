// AI Coach Floating Interface
// Premium Feature - Persistent floating coach in bottom-right corner
// Always visible across all app screens

import SwiftUI
import Combine

// MARK: - AI Coach Manager

@MainActor
class AICoachManager: ObservableObject {
    static let shared = AICoachManager()
    
    @Published var currentInsight: AIInsight?
    @Published var unreadInsights: [AIInsight] = []
    @Published var readinessScore: ReadinessScore?
    @Published var isExpanded = false
    @Published var isVisible = true
    @Published var currentSport: String = "basketball"
    
    private var refreshTimer: Timer?
    
    init() {
        // Refresh insights every 5 minutes
        startAutoRefresh()
    }
    
    func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshInsights()
            }
        }
    }
    
    func refreshInsights() async {
        do {
            // Get daily insights
            _ = try await APIClient.shared.getDailyInsights(sport: currentSport)
            
            // Get unread
            let unread = try await APIClient.shared.getUnreadInsights()
            
            await MainActor.run {
                self.unreadInsights = unread
                
                // Show highest priority unread insight
                if let topInsight = unread.first(where: { $0.priority == "urgent" }) ?? unread.first {
                    self.currentInsight = topInsight
                }
            }
            
            // Get readiness score
            let readiness = try await APIClient.shared.getMatchReadiness(sport: currentSport)
            
            await MainActor.run {
                self.readinessScore = readiness
            }
        } catch {
            print("Failed to refresh AI Coach: \(error)")
        }
    }
    
    func markCurrentInsightRead() async {
        guard let insight = currentInsight else { return }
        
        do {
            _ = try await APIClient.shared.markInsightRead(insightId: insight.id)
            
            await MainActor.run {
                // Remove from unread
                unreadInsights.removeAll { $0.id == insight.id }
                
                // Show next insight
                currentInsight = unreadInsights.first
            }
        } catch {
            print("Failed to mark insight read: \(error)")
        }
    }
    
    func dismissCurrentInsight() async {
        guard let insight = currentInsight else { return }
        
        do {
            _ = try await APIClient.shared.dismissInsight(insightId: insight.id)
            
            await MainActor.run {
                unreadInsights.removeAll { $0.id == insight.id }
                currentInsight = unreadInsights.first
                isExpanded = false
            }
        } catch {
            print("Failed to dismiss insight: \(error)")
        }
    }
}

// MARK: - Floating AI Coach View

struct AICoachFloatingView: View {
    @StateObject private var coachManager = AICoachManager.shared
    @State private var panelPosition: CGPoint?
    
    var body: some View {
        if coachManager.isVisible {
            GeometryReader { geometry in
                // Fixed button position above the Profile tab (bottom-right)
                let fixedButtonPosition = CGPoint(
                    x: geometry.size.width - 50,
                    y: geometry.size.height - 120
                )
                
                // Panel position (draggable, defaults to button position)
                let currentPanelPosition = panelPosition ?? fixedButtonPosition
                
                ZStack {
                    if coachManager.isExpanded {
                        // Expanded Panel (draggable)
                        expandedPanel(geometry: geometry)
                            .position(currentPanelPosition)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Collapsed Floating Button (fixed position, not draggable)
                        collapsedButton
                            .position(fixedButtonPosition)
                            .transition(.scale)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: coachManager.isExpanded)
                .onAppear {
                    // Reset panel position when view appears
                    panelPosition = nil
                }
                .onChange(of: coachManager.isExpanded) { expanded in
                    // Reset panel position when expanding
                    if expanded {
                        panelPosition = fixedButtonPosition
                    }
                }
            }
        }
    }
    
    // MARK: - Collapsed Button
    
    private var collapsedButton: some View {
        Button(action: {
            withAnimation {
                coachManager.isExpanded = true
            }
        }) {
            ZStack {
                // Background - Dark circle with blue gradient border
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.1, green: 0.1, blue: 0.2), Color(red: 0.15, green: 0.15, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 4)
                
                // "S" Logo
                Text("S")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(white: 0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Badge for unread insights
                if !coachManager.unreadInsights.isEmpty {
                    Circle()
                        .fill(.red)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Text("\(coachManager.unreadInsights.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .offset(x: 18, y: -18)
                }
            }
        }
    }
    
    // MARK: - Expanded Panel
    
    private func expandedPanel(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("AI Coach")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        coachManager.isExpanded = false
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.gray)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Readiness Score
                    if let readiness = coachManager.readinessScore {
                        readinessCard(readiness)
                    }
                    
                    // Current Insight
                    if let insight = coachManager.currentInsight {
                        insightCard(insight)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .frame(width: 340, height: 500)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 5)
        .gesture(
            DragGesture()
                .onChanged { value in
                    panelPosition = CGPoint(
                        x: (panelPosition?.x ?? 0) + value.translation.width,
                        y: (panelPosition?.y ?? 0) + value.translation.height
                    )
                }
                .onEnded { _ in
                    // Keep panel within bounds
                    if let pos = panelPosition {
                        let minX: CGFloat = 170
                        let maxX = geometry.size.width - 170
                        let minY: CGFloat = 250
                        let maxY = geometry.size.height - 250
                        
                        panelPosition = CGPoint(
                            x: min(max(pos.x, minX), maxX),
                            y: min(max(pos.y, minY), maxY)
                        )
                    }
                }
        )
    }
    
    // MARK: - Readiness Card
    
    private func readinessCard(_ readiness: ReadinessScore) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 20))
                    .foregroundStyle(readinessColor(readiness.status))
                
                Text("Match Readiness")
                    .font(.headline)
                
                Spacer()
                
                Text(readiness.status.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(readinessColor(readiness.status).opacity(0.2))
                    .foregroundStyle(readinessColor(readiness.status))
                    .cornerRadius(8)
            }
            
            // Score Gauge
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(height: 12)
                
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: gradientColors(for: readiness.readinessScore),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 280 * (readiness.readinessScore / 100), height: 12)
            }
            
            Text("\(Int(readiness.readinessScore))/100")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(readinessColor(readiness.status))
            
            Text(readiness.recommendation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Insight Card
    
    private func insightCard(_ insight: AIInsight) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                priorityIcon(insight.priority)
                
                Text(insight.title)
                    .font(.headline)
                    .lineLimit(2)
                
                Spacer()
            }
            
            Text(insight.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if !insight.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Recommendations:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    ForEach(insight.suggestedActions.prefix(3), id: \.self) { action in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                            
                            Text(action)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            HStack {
                Button(action: {
                    Task {
                        await coachManager.markCurrentInsightRead()
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Got It")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await coachManager.dismissCurrentInsight()
                    }
                }) {
                    Text("Dismiss")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)
            
            Text("All Caught Up!")
                .font(.headline)
            
            Text("No new insights at the moment. Check back later for personalized recommendations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    await coachManager.refreshInsights()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.blue)
                .cornerRadius(8)
            }
        }
        .padding(Spacing.xl)
    }
    
    // MARK: - Helper Functions
    
    private func priorityIcon(_ priority: String) -> some View {
        Group {
            switch priority {
            case "urgent":
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case "high":
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case "medium":
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
            default:
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.system(size: 18))
    }
    
    private func readinessColor(_ status: String) -> Color {
        switch status {
        case "excellent": return .green
        case "good": return .blue
        case "fair": return .orange
        case "poor": return .red
        default: return .gray
        }
    }
    
    private func gradientColors(for score: Double) -> [Color] {
        if score >= 85 {
            return [.green, .mint]
        } else if score >= 70 {
            return [.blue, .cyan]
        } else if score >= 50 {
            return [.orange, .yellow]
        } else {
            return [.red, .pink]
        }
    }
}

// MARK: - View Extension for Floating Coach

extension View {
    func withAICoach() -> some View {
        self.overlay(
            AICoachFloatingView()
                .zIndex(999)
        )
    }
}
