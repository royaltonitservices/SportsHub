// Goals Survey View
// Premium Feature - Sport-specific goal setting

import SwiftUI

struct GoalsSurveyView: View {
    let sport: String
    @Environment(\.dismiss) private var dismiss
    @State private var skillFocus: Set<String> = []
    @State private var physicalFocus: Set<String> = []
    @State private var tacticalFocus: Set<String> = []
    @State private var mentalFocus: Set<String> = []
    @State private var customGoals = ""
    @State private var priorities: [String: Int] = [:]
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var skillOptions: SkillOptions?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Header
                    headerSection
                    
                    if let options = skillOptions {
                        // Skill Focus
                        sectionView(
                            title: "Skill Focus",
                            subtitle: "What skills do you want to improve?",
                            icon: "figure.basketball",
                            items: sportSkills(options),
                            selection: $skillFocus
                        )
                        
                        // Physical Focus
                        sectionView(
                            title: "Physical Development",
                            subtitle: "What physical attributes to work on?",
                            icon: "figure.run",
                            items: options.general.filter { ["endurance", "speed", "strength", "agility", "flexibility"].contains($0) },
                            selection: $physicalFocus
                        )
                        
                        // Mental Focus
                        sectionView(
                            title: "Mental Game",
                            subtitle: "Mental aspects to develop",
                            icon: "brain.head.profile",
                            items: options.general.filter { ["mental_toughness", "strategy"].contains($0) },
                            selection: $mentalFocus
                        )
                        
                        // Priority Levels
                        if !skillFocus.isEmpty {
                            prioritySection
                        }
                        
                        // Custom Goals
                        customGoalsSection
                        
                        // Save Button
                        saveButton
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(Spacing.xl)
                    }
                }
                .padding()
            }
            .navigationTitle("\(sport.capitalized) Goals")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSkillOptions()
                await loadExistingGoals()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: sportIcon(sport))
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                VStack(alignment: .leading) {
                    Text(sport.capitalized)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Set your improvement goals")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("AI Coach will use these goals to personalize your training recommendations, drills, and insights.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
        }
    }
    
    // MARK: - Section View
    
    private func sectionView(
        title: String,
        subtitle: String,
        icon: String,
        items: [String],
        selection: Binding<Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            FlowLayout(spacing: Spacing.sm) {
                ForEach(items, id: \.self) { item in
                    SkillChip(
                        title: item.replacingOccurrences(of: "_", with: " ").capitalized,
                        isSelected: selection.wrappedValue.contains(item)
                    ) {
                        if selection.wrappedValue.contains(item) {
                            selection.wrappedValue.remove(item)
                            priorities.removeValue(forKey: item)
                        } else {
                            selection.wrappedValue.insert(item)
                            priorities[item] = 3 // Default medium priority
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Priority Section
    
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                
                Text("Set Priorities")
                    .font(.headline)
            }
            
            Text("Rate importance (1=Low, 5=High)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ForEach(Array(skillFocus), id: \.self) { skill in
                HStack {
                    Text(skill.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    ForEach(1...5, id: \.self) { level in
                        Button(action: {
                            priorities[skill] = level
                        }) {
                            Image(systemName: priorities[skill, default: 3] >= level ? "star.fill" : "star")
                                .foregroundStyle(priorities[skill, default: 3] >= level ? .yellow : .gray)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Custom Goals
    
    private var customGoalsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.blue)
                
                Text("Additional Goals (Optional)")
                    .font(.headline)
            }
            
            TextEditor(text: $customGoals)
                .frame(height: 100)
                .padding(Spacing.sm)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            
            Text("Describe any specific goals or areas you want to focus on")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Save Button
    
    private var saveButton: some View {
        Button(action: {
            Task {
                await saveGoals()
            }
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Save Goals")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
        .disabled(isLoading || skillFocus.isEmpty)
        .opacity((isLoading || skillFocus.isEmpty) ? 0.6 : 1.0)
    }
    
    // MARK: - Data Loading
    
    private func loadSkillOptions() async {
        do {
            skillOptions = try await APIClient.shared.getSkillOptions()
        } catch {
            errorMessage = "We couldn't load skill options. Please try again."
            showError = true
        }
    }
    
    private func loadExistingGoals() async {
        do {
            let goals = try await APIClient.shared.getGoalsSurvey(sport: sport)
            
            await MainActor.run {
                skillFocus = Set(goals.skillFocus)
                physicalFocus = Set(goals.physicalFocus)
                tacticalFocus = Set(goals.tacticalFocus)
                mentalFocus = Set(goals.mentalFocus)
                customGoals = goals.customGoals ?? ""
                priorities = goals.improvementPriority
            }
        } catch {
            // No existing goals - that's okay
        }
    }
    
    private func saveGoals() async {
        isLoading = true
        defer { isLoading = false }
        
        let request = GoalsSurveyRequest(
            sport: sport,
            skillFocus: Array(skillFocus),
            physicalFocus: Array(physicalFocus),
            tacticalFocus: Array(tacticalFocus),
            mentalFocus: Array(mentalFocus),
            customGoals: customGoals.isEmpty ? nil : customGoals,
            improvementPriority: priorities
        )
        
        do {
            _ = try await APIClient.shared.submitGoalsSurvey(request: request)
            
            await MainActor.run {
                dismiss()
            }
        } catch {
            errorMessage = "We couldn't save your goals. Please try again."
            showError = true
        }
    }
    
    // MARK: - Helpers
    
    private func sportSkills(_ options: SkillOptions) -> [String] {
        switch sport.lowercased() {
        case "basketball": return options.basketball
        case "football": return options.football
        case "soccer": return options.soccer
        case "tennis": return options.tennis
        default: return []
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

// MARK: - Skill Chip

struct SkillChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.blue : Color(.systemGray6))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
