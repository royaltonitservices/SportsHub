//
//  OnboardingSurveyView.swift
//  SportsHub
//
//  Sport-specific onboarding survey shown after email verification.
//  Steps: sport selection → skill ratings (1-10) → strengths → weaknesses → submit.
//  Data feeds directly into AI Coach context for personalized coaching from day one.
//

import SwiftUI

// MARK: - Sport Skill Definitions

private struct SportSkills {
    static let skills: [Sport: [String]] = [
        .basketball: ["Shooting", "Dribbling", "Defense", "Passing", "Athleticism", "IQ/Court Vision"],
        .football: ["Speed", "Strength", "Route Running", "Catching", "Blocking", "Football IQ"],
        .soccer: ["Dribbling", "Shooting", "Passing", "Defense", "Athleticism", "Vision"],
        .tennis: ["Serve", "Forehand", "Backhand", "Volleys", "Footwork", "Mental Toughness"]
    ]

    static let strengths: [Sport: [String]] = [
        .basketball: ["Scoring", "Rebounding", "Defense", "Playmaking", "Athleticism", "Leadership", "Hustle"],
        .football: ["Speed", "Power", "Route Running", "Ball Skills", "Blocking", "Instincts", "Toughness"],
        .soccer: ["Pace", "Technique", "Vision", "Work Rate", "Defending", "Set Pieces", "Leadership"],
        .tennis: ["Powerful Serve", "Baseline Play", "Net Play", "Consistency", "Mental Toughness", "Speed", "Touch"]
    ]

    static let weaknesses: [Sport: [String]] = [
        .basketball: ["Free Throws", "Left Hand", "Defense", "Three-Pointers", "Finishing", "Stamina", "Dribbling"],
        .football: ["Speed", "Strength", "Hands", "Route Running", "Blocking", "Footwork", "Reading Defense"],
        .soccer: ["Weak Foot", "Heading", "Defending", "Stamina", "Finishing", "Passing Accuracy", "Set Pieces"],
        .tennis: ["Second Serve", "Backhand", "Net Play", "Return of Serve", "Consistency", "Footwork", "Mental Game"]
    ]
}

// MARK: - View

struct OnboardingSurveyView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var currentStep = 0
    @State private var selectedSport: Sport = .basketball
    @State private var skillRatings: [String: Int] = [:]
    @State private var selectedStrengths: Set<String> = []
    @State private var selectedWeaknesses: Set<String> = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)

                TabView(selection: $currentStep) {
                    sportSelectionStep.tag(0)
                    skillRatingsStep.tag(1)
                    strengthsStep.tag(2)
                    weaknessesStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                navigationButtons
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text(stepTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.appSurface)
                    Capsule()
                        .fill(Color.appPrimary)
                        .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps))
                        .animation(.spring(response: 0.4), value: currentStep)
                }
            }
            .frame(height: 4)
        }
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return "Your Sport"
        case 1: return "Skill Ratings"
        case 2: return "Strengths"
        case 3: return "Weaknesses"
        default: return ""
        }
    }

    // MARK: - Step 0: Sport Selection

    private var sportSelectionStep: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                stepHeader(
                    icon: "sportscourt.fill",
                    title: "What's your main sport?",
                    subtitle: "Your AI Coach specializes around your sport from day one."
                )

                VStack(spacing: Spacing.md) {
                    ForEach([Sport.basketball, .football, .soccer, .tennis], id: \.self) { sport in
                        sportCard(sport: sport)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xl)
        }
    }

    private func sportCard(sport: Sport) -> some View {
        Button {
            selectedSport = sport
            skillRatings = [:]
            selectedStrengths = []
            selectedWeaknesses = []
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: sportIcon(sport))
                    .font(.title2)
                    .foregroundStyle(selectedSport == sport ? .white : Color.appPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(selectedSport == sport ? Color.appPrimary : Color.appPrimary.opacity(0.15))
                    )

                Text(sport.displayName)
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)

                Spacer()

                if selectedSport == sport {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.appPrimary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(Color.appSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .strokeBorder(selectedSport == sport ? Color.appPrimary : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 1: Skill Ratings

    private var skillRatingsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                stepHeader(
                    icon: "star.fill",
                    title: "\(selectedSport.rawValue.capitalized) skills",
                    subtitle: "Rate yourself honestly — 1 = just starting out, 5 = average player, 10 = elite. Your coach uses this to skip the guesswork."
                )

                // Scale legend
                HStack {
                    Text("1 · Beginner")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                    Spacer()
                    Text("5 · Average")
                        .font(.caption2)
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer()
                    Text("10 · Elite")
                        .font(.caption2)
                        .foregroundStyle(.green.opacity(0.8))
                }
                .padding(.horizontal, 2)

                VStack(spacing: Spacing.lg) {
                    let skills = SportSkills.skills[selectedSport] ?? []
                    ForEach(skills, id: \.self) { skill in
                        skillRatingRow(skill: skill)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xl)
        }
    }

    private func skillRatingRow(skill: String) -> some View {
        let rating = skillRatings[skill] ?? 5
        let (label, labelColor) = skillRatingLabel(rating)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(skill)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(labelColor)
                    Text("\(rating)/10")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.appPrimary)
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Slider(
                value: Binding(
                    get: { Double(skillRatings[skill] ?? 5) },
                    set: { skillRatings[skill] = Int($0.rounded()) }
                ),
                in: 1...10,
                step: 1
            )
            .accentColor(Color.appPrimary)
        }
    }

    private func skillRatingLabel(_ rating: Int) -> (String, Color) {
        switch rating {
        case 1...2: return ("Beginner",    .red.opacity(0.8))
        case 3...4: return ("Learning",    .orange.opacity(0.9))
        case 5...6: return ("Average",     Color.appTextSecondary)
        case 7...8: return ("Good",        .blue.opacity(0.8))
        default:    return ("Elite",       .green.opacity(0.85))
        }
    }

    // MARK: - Step 2: Strengths

    private var strengthsStep: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                stepHeader(
                    icon: "bolt.fill",
                    title: "What are your strengths?",
                    subtitle: "Pick up to 3. Your coach will build on what you already do well."
                )

                tagsGrid(
                    options: SportSkills.strengths[selectedSport] ?? [],
                    selected: $selectedStrengths,
                    max: 3,
                    color: Color.appSuccess
                )
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xl)
        }
    }

    // MARK: - Step 3: Weaknesses

    private var weaknessesStep: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                stepHeader(
                    icon: "target",
                    title: "What do you want to improve?",
                    subtitle: "Pick up to 3. Your coach focuses sessions around your biggest gaps."
                )

                tagsGrid(
                    options: SportSkills.weaknesses[selectedSport] ?? [],
                    selected: $selectedWeaknesses,
                    max: 3,
                    color: Color.appPrimary
                )

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.appError)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.xl)
        }
    }

    // MARK: - Tags Grid

    private func tagsGrid(options: [String], selected: Binding<Set<String>>, max: Int, color: Color) -> some View {
        FlexibleTagGrid(options: options, selected: selected, max: max, color: color)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: Spacing.md) {
            if currentStep > 0 {
                Button(action: previousStep) {
                    Text("Back")
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.large)
                                .fill(Color.appSurface)
                        )
                }
            }

            Button(action: nextStep) {
                ZStack {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(currentStep == totalSteps - 1 ? "Start Coaching" : "Next")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.large)
                        .fill(isCurrentStepValid ? Color.appPrimary : Color.appSurface)
                )
            }
            .disabled(!isCurrentStepValid || isSubmitting)
        }
    }

    // MARK: - Step Validation

    private var isCurrentStepValid: Bool {
        switch currentStep {
        case 0: return true // Sport always selected
        case 1:
            let skills = SportSkills.skills[selectedSport] ?? []
            return skills.allSatisfy { skillRatings[$0] != nil }
        case 2: return !selectedStrengths.isEmpty
        case 3: return !selectedWeaknesses.isEmpty
        default: return true
        }
    }

    // MARK: - Navigation

    private func nextStep() {
        if currentStep < totalSteps - 1 {
            withAnimation { currentStep += 1 }
        } else {
            submitSurvey()
        }
    }

    private func previousStep() {
        if currentStep > 0 {
            withAnimation { currentStep -= 1 }
        }
    }

    // MARK: - Submit

    private func submitSurvey() {
        isSubmitting = true
        errorMessage = nil

        // goals not collected during initial onboarding — user sets them later in Settings
        let surveyRequest = OnboardingSurveyRequest(
            mainSport: selectedSport.rawValue,
            skillRatings: skillRatings,
            strengths: Array(selectedStrengths),
            weaknesses: Array(selectedWeaknesses),
            goals: [],
            onboardingVersion: 1
        )

        Task {
            do {
                try await APIClient.shared.submitOnboardingSurvey(surveyRequest)
                sessionManager.handleSurveyCompletion()
            } catch {
                await MainActor.run {
                    errorMessage = "Couldn't save your survey. Please try again."
                    isSubmitting = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(Color.appPrimary)

            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.appTextPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func sportIcon(_ sport: Sport) -> String {
        switch sport {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .soccer: return "soccerball"
        case .tennis: return "tennis.racket"
        }
    }
}

// MARK: - Flexible Tag Grid

private struct FlexibleTagGrid: View {
    let options: [String]
    @Binding var selected: Set<String>
    let max: Int
    let color: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: Spacing.sm) {
            ForEach(options, id: \.self) { option in
                tagChip(option)
            }
        }
    }

    private func tagChip(_ option: String) -> some View {
        let isSelected = selected.contains(option)
        let canSelect = selected.count < max || isSelected

        return Button {
            if isSelected {
                selected.remove(option)
            } else if canSelect {
                selected.insert(option)
            }
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                Text(option)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(isSelected ? color : Color.appSurface)
            )
            .foregroundStyle(isSelected ? .white : (canSelect ? Color.appTextPrimary : Color.appTextSecondary))
        }
        .buttonStyle(.plain)
        .disabled(!canSelect && !isSelected)
    }
}

// MARK: - Sport Extension

private extension Sport {
    var displayName: String {
        switch self {
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        }
    }
}

#Preview {
    OnboardingSurveyView()
        .environmentObject(SessionManager.shared)
        .preferredColorScheme(.dark)
}
