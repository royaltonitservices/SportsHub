//
//  DrillDetailView.swift
//  SportsHub
//
//  Detailed drill instructions and tracking
//

import SwiftUI

struct DrillDetailView: View {
    @Environment(\.dismiss) var dismiss
    
    let drill: TrainingDrill
    
    @State private var showStartSession = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text(drill.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Spacer()
                        
                        // Difficulty badge
                        HStack(spacing: 4) {
                            Image(systemName: drill.difficulty.icon)
                                .font(.caption)
                            Text(drill.difficulty.rawValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(drill.difficulty.color)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(drill.difficulty.color.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Text(drill.description)
                        .font(.body)
                        .foregroundStyle(Color.appTextSecondary)
                    
                    // Metadata
                    HStack(spacing: Spacing.lg) {
                        Label("\(drill.duration) min", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Label(drill.category.rawValue, systemImage: "tag")
                            .font(.subheadline)
                            .foregroundStyle(Color.appPrimary)
                        
                        Label(drill.sport.rawValue, systemImage: drill.sport.icon)
                            .font(.subheadline)
                            .foregroundStyle(Color.appPrimary)
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Equipment
                if !drill.equipment.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "gym.bag.fill")
                                .foregroundStyle(Color.appPrimary)
                            Text("Equipment Needed")
                                .font(.headline)
                                .foregroundStyle(Color.appTextPrimary)
                        }
                        
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(drill.equipment, id: \.self) { item in
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.appSecondary)
                                    Text(item)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.appTextPrimary)
                                }
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .cardBackground()
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: "list.number")
                            .foregroundStyle(Color.appPrimary)
                        Text("Instructions")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(Array(drill.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Color.appPrimary)
                                    .clipShape(Circle())
                                
                                Text(instruction)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appTextPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Metrics to Track
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(Color.appPrimary)
                        Text("Metrics to Track")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(drill.metrics, id: \.self) { metric in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.caption)
                                    .foregroundStyle(Color.appSecondary)
                                Text(metric)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appTextPrimary)
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Pro Tips
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("Pro Tips")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                    
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(drill.tips, id: \.self) { tip in
                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .padding(.top, 2)
                                
                                Text(tip)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(Spacing.md)
                .cardBackground()
                
                // Start Session Button
                Button(action: {
                    showStartSession = true
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                        Text("Start This Drill")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appPrimary)
                    .cornerRadius(12)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .padding(.vertical, Spacing.md)
        }
        .background(Color.appBackground)
        .navigationTitle("Drill Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStartSession) {
            // Pass name, duration, effort level, and top coaching notes so the
            // training session form starts pre-populated with real drill context.
            let instructionSummary: String = {
                var parts: [String] = []
                if !drill.tips.isEmpty {
                    parts.append(contentsOf: drill.tips.prefix(2))
                }
                if !drill.instructions.isEmpty && parts.count < 3 {
                    parts.append(drill.instructions[0])
                }
                return parts.joined(separator: " | ")
            }()
            TrainingSessionView(
                sport: drill.sport,
                prefilledDrillName: drill.name,
                prefilledDuration: drill.duration,
                prefilledDrillNotes: instructionSummary.isEmpty ? nil : instructionSummary,
                prefilledEffort: drill.difficulty.effortLevel,
                prefilledMetricType: drill.primaryMetricType
            )
        }
    }
}

#Preview {
    NavigationStack {
        DrillDetailView(drill: TrainingDrill.basketballDrills[0])
    }
}
