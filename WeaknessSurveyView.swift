//
//  WeaknessSurveyView.swift
//  SportsHub
//
//  Sport-specific weakness intake survey.
//  Gives the AI Coach structured, intentional data — not just chat inference.
//

import SwiftUI

// MARK: - Weakness Data Model

/// Manages sport-specific weakness selections with UserDefaults persistence.
struct SportWeaknesses {

    // MARK: Sport Options

    static func options(for sport: Sport) -> [String] {
        switch sport {
        case .basketball:
            return [
                "Ball Handling",
                "Shooting Consistency",
                "Left Hand (Off Hand)",
                "Defense & Closeouts",
                "Finishing at the Rim",
                "Free Throws",
                "Court Vision & Passing",
                "Rebounding",
                "Lateral Quickness",
                "Confidence Under Pressure"
            ]
        case .football:
            return [
                "Route Running & Breaks",
                "Catching & Hands",
                "Throwing Accuracy",
                "QB Drop & Footwork",
                "Release Speed off the Line",
                "Short-Area Agility",
                "Blocking Technique",
                "Coverage Reading",
                "Stamina & Conditioning",
                "First-Step Explosiveness"
            ]
        case .soccer:
            return [
                "Weak Foot Control",
                "First Touch",
                "Passing Accuracy & Weight",
                "1v1 Dribbling",
                "Finishing",
                "Acceleration & Speed",
                "Defending & Positioning",
                "Crossing",
                "Stamina",
                "Decision-Making Under Pressure"
            ]
        case .tennis:
            return [
                "Serve Consistency",
                "Backhand",
                "Forehand Power",
                "Footwork & Recovery",
                "Net Play & Volleys",
                "Return of Serve",
                "Mental Game & Composure",
                "Endurance",
                "Slice & Variation",
                "Second-Serve Reliability"
            ]
        }
    }

    // MARK: Persistence

    static func key(for sport: Sport) -> String {
        "weakness_survey_\(sport.rawValue)"
    }

    static func load(for sport: Sport) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(for: sport)) ?? []
    }

    static func save(_ weaknesses: [String], for sport: Sport) {
        UserDefaults.standard.set(weaknesses, forKey: key(for: sport))
    }

    static func hasCompleted(for sport: Sport) -> Bool {
        UserDefaults.standard.object(forKey: key(for: sport)) != nil
    }
}

// MARK: - Survey View

struct WeaknessSurveyView: View {
    let sport: Sport
    let onSave: (() -> Void)?

    @State private var selected: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    init(sport: Sport, onSave: (() -> Void)? = nil) {
        self.sport = sport
        self.onSave = onSave
    }

    private var options: [String] { SportWeaknesses.options(for: sport) }
    private var sportIcon: String {
        switch sport {
        case .basketball: return "basketball.fill"
        case .football:   return "football.fill"
        case .soccer:     return "soccerball"
        case .tennis:     return "tennisball.fill"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {

                    // Header
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: sportIcon)
                                .font(.title2)
                                .foregroundStyle(Color.appPrimary)
                            Text("\(sport.rawValue.capitalized) Focus Areas")
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Text("Select the areas you want to improve. Your AI Coach uses this to personalize every recommendation.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.md)

                    // Selection grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                        ForEach(options, id: \.self) { weakness in
                            WeaknessOptionButton(
                                label: weakness,
                                isSelected: selected.contains(weakness)
                            ) {
                                if selected.contains(weakness) {
                                    selected.remove(weakness)
                                } else {
                                    selected.insert(weakness)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)

                    // Selection count note
                    if !selected.isEmpty {
                        Text("\(selected.count) area\(selected.count == 1 ? "" : "s") selected — your coach will prioritize these")
                            .font(.caption)
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, Spacing.lg)
                    }

                    Spacer(minLength: Spacing.xl)
                }
            }
            .navigationTitle("Areas to Improve")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SportWeaknesses.save(Array(selected), for: sport)
                        onSave?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selected.isEmpty)
                }
            }
            .onAppear {
                selected = Set(SportWeaknesses.load(for: sport))
            }
        }
    }
}

// MARK: - Option Button

private struct WeaknessOptionButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.secondary)

                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.appPrimary : Color.appTextPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(isSelected ? Color.appPrimary.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isSelected ? Color.appPrimary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
