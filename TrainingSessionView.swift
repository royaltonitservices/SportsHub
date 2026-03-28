//
//  TrainingSessionView.swift
//  SportsHub
//
//  Multi-drill training session logging and tracking
//

import SwiftUI
import PhotosUI

struct TrainingSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    
    let sport: Sport
    var prefilledDrillName: String? = nil
    
    // Multi-drill session state
    @State private var drillEntries: [DrillEntry] = []
    @State private var currentDrill = DrillEntry()
    @State private var sessionNotes = ""
    @State private var isEditingDrill = false
    @State private var editingDrillId: UUID?
    
    // UI state
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showDrillSuggestions = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Session Summary Header
                    if !drillEntries.isEmpty {
                        sessionSummaryCard
                    }
                    
                    // Current Drill Entry Form
                    currentDrillCard
                    
                    // Logged Drills List
                    if !drillEntries.isEmpty {
                        loggedDrillsList
                    }
                    
                    // Session Notes
                    sessionNotesSection
                    
                    // Photo Evidence
                    photoEvidenceSection
                }
                .padding()
            }
            .navigationTitle("Log Training Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Session") {
                        Task {
                            await saveSession()
                        }
                    }
                    .disabled(!isSessionValid || isLoading)
                }
            }
            .onAppear {
                if let prefilled = prefilledDrillName {
                    currentDrill.drillName = prefilled
                }
            }
            .sheet(isPresented: $showDrillSuggestions) {
                DrillSuggestionsSheet(sport: sport, selectedDrill: $currentDrill.drillName)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedPhotos.isEmpty ? .constant(nil) : Binding(
                    get: { nil },
                    set: { newImage in
                        if let newImage = newImage {
                            photoImages.append(newImage)
                        }
                    }
                ))
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Training session with \(drillEntries.count) drill(s) logged successfully!")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Session Summary Card
    
    private var sessionSummaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Session Summary")
                    .font(.headline)
                Spacer()
                Text("\(totalDuration) min")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }
            
            HStack(spacing: Spacing.lg) {
                summaryMetric(icon: "figure.run", label: "Drills", value: "\(drillEntries.count)")
                Divider().frame(height: 30)
                summaryMetric(icon: "clock.fill", label: "Total Time", value: "\(totalDuration)m")
                Divider().frame(height: 30)
                summaryMetric(icon: "flame.fill", label: "Avg Effort", value: averageEffort)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func summaryMetric(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Current Drill Card
    
    private var currentDrillCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text(isEditingDrill ? "Edit Drill" : "Add Drill to Session")
                    .font(.headline)
                Spacer()
                if isEditingDrill {
                    Button("Cancel") {
                        cancelEdit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            }
            
            // Drill Name
            HStack {
                TextField("Drill or skill name", text: $currentDrill.drillName)
                    .textInputAutocapitalization(.words)
                
                Button(action: {
                    showDrillSuggestions = true
                }) {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Duration
            HStack {
                Text("Duration")
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("\(currentDrill.duration) min", value: $currentDrill.duration, in: 5...180, step: 5)
            }
            
            // Effort Level
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Effort Level")
                    .foregroundStyle(.secondary)
                
                HStack(spacing: Spacing.sm) {
                    ForEach(EffortLevel.allCases, id: \.self) { level in
                        Button(action: {
                            currentDrill.effort = level
                        }) {
                            VStack(spacing: 4) {
                                Text(level.emoji)
                                    .font(.title2)
                                Text(level.rawValue)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.sm)
                            .background(currentDrill.effort == level ? Color.blue.opacity(0.2) : Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(currentDrill.effort == level ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Metric (Optional)
            HStack {
                Picker("Metric", selection: $currentDrill.metricType) {
                    Text("None").tag(nil as MetricType?)
                    ForEach(MetricType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as MetricType?)
                    }
                }
                
                if currentDrill.metricType != nil {
                    TextField("Value", text: $currentDrill.metricValue)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
            
            // Notes
            TextEditor(text: $currentDrill.notes)
                .frame(height: 60)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    Group {
                        if currentDrill.notes.isEmpty {
                            Text("Notes for this drill (optional)...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                                .padding(.leading, 12)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
            
            // Add/Update Button
            Button(action: {
                if isEditingDrill {
                    updateDrill()
                } else {
                    addDrill()
                }
            }) {
                HStack {
                    Image(systemName: isEditingDrill ? "checkmark.circle.fill" : "plus.circle.fill")
                    Text(isEditingDrill ? "Update Drill" : "Add Drill to Session")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(currentDrill.drillName.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(currentDrill.drillName.isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5)
    }
    
    // MARK: - Logged Drills List
    
    private var loggedDrillsList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Logged Drills (\(drillEntries.count))")
                .font(.headline)
            
            ForEach(drillEntries) { entry in
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.drillName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: Spacing.sm) {
                            Label("\(entry.duration) min", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text(entry.effort.emoji)
                                .font(.caption)
                            
                            if entry.metricType != nil, !entry.metricValue.isEmpty {
                                Text("• \(entry.metricValue) \(entry.metricType?.rawValue ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if !entry.notes.isEmpty {
                            Text(entry.notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    Menu {
                        Button {
                            editDrill(entry)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            removeDrill(entry)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Session Notes Section
    
    private var sessionNotesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Session Notes (Optional)")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            TextEditor(text: $sessionNotes)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    Group {
                        if sessionNotes.isEmpty {
                            Text("Overall session notes, how you felt, etc...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                                .padding(.leading, 12)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }
    
    // MARK: - Photo Evidence Section
    
    private var photoEvidenceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Evidence (Optional)")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if photoImages.isEmpty {
                Button(action: {
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "camera")
                        Text("Add Photos")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(photoImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: photoImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                Button(action: {
                                    photoImages.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(.black.opacity(0.6)))
                                        .padding(4)
                                }
                            }
                        }
                        
                        Button(action: {
                            showImagePicker = true
                        }) {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var totalDuration: Int {
        drillEntries.reduce(0) { $0 + $1.duration }
    }
    
    private var averageEffort: String {
        guard !drillEntries.isEmpty else { return "—" }
        let effortValues: [Int] = drillEntries.map { entry in
            switch entry.effort {
            case .light: return 1
            case .moderate: return 2
            case .hard: return 3
            case .maximal: return 4
            }
        }
        let avg = effortValues.reduce(0, +) / effortValues.count
        let levels = [EffortLevel.light, .moderate, .hard, .maximal]
        return levels[avg - 1].emoji
    }
    
    private var isSessionValid: Bool {
        !drillEntries.isEmpty
    }
    
    // MARK: - Actions
    
    private func addDrill() {
        let newEntry = currentDrill
        drillEntries.append(newEntry)
        currentDrill = DrillEntry()
    }
    
    private func updateDrill() {
        if let id = editingDrillId, let index = drillEntries.firstIndex(where: { $0.id == id }) {
            drillEntries[index] = currentDrill
            cancelEdit()
        }
    }
    
    private func editDrill(_ entry: DrillEntry) {
        currentDrill = entry
        editingDrillId = entry.id
        isEditingDrill = true
    }
    
    private func removeDrill(_ entry: DrillEntry) {
        drillEntries.removeAll { $0.id == entry.id }
    }
    
    private func cancelEdit() {
        currentDrill = DrillEntry()
        editingDrillId = nil
        isEditingDrill = false
    }
    
    private func saveSession() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: API call to save multi-drill training session
        // Will send: sport, drillEntries, sessionNotes, photoImages
        try? await Task.sleep(nanoseconds: 500_000_000)
        showSuccess = true
    }
}

// MARK: - Supporting Types

struct DrillEntry: Identifiable, Codable {
    let id: UUID
    var drillName: String
    var duration: Int
    var metricType: MetricType?
    var metricValue: String
    var effort: EffortLevel
    var notes: String
    
    init(id: UUID = UUID(), drillName: String = "", duration: Int = 15, metricType: MetricType? = nil, metricValue: String = "", effort: EffortLevel = .moderate, notes: String = "") {
        self.id = id
        self.drillName = drillName
        self.duration = duration
        self.metricType = metricType
        self.metricValue = metricValue
        self.effort = effort
        self.notes = notes
    }
}

enum MetricType: String, CaseIterable, Codable {
    case reps = "Reps"
    case makes = "Makes"
    case attempts = "Attempts"
    case distance = "Distance (m)"
    case time = "Time (sec)"
    case weight = "Weight (lbs)"
    case sets = "Sets"
    case accuracy = "Accuracy (%)"
}

enum EffortLevel: String, CaseIterable, Codable {
    case light = "Light"
    case moderate = "Moderate"
    case hard = "Hard"
    case maximal = "Maximal"
    
    var emoji: String {
        switch self {
        case .light: return "😌"
        case .moderate: return "😤"
        case .hard: return "💪"
        case .maximal: return "🔥"
        }
    }
}

// MARK: - Drill Suggestions Sheet

struct DrillSuggestionsSheet: View {
    let sport: Sport
    @Binding var selectedDrill: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(drillSuggestions, id: \.self) { drill in
                    Button(action: {
                        selectedDrill = drill
                        dismiss()
                    }) {
                        HStack {
                            Text(drill)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedDrill == drill {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(sport.rawValue) Drills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var drillSuggestions: [String] {
        switch sport {
        case .basketball:
            return [
                "Ball Handling",
                "Form Shooting",
                "Three-Point Shooting",
                "Finishing at the Rim",
                "Free Throws",
                "Defensive Slides",
                "Rebounding",
                "Passing Drills",
                "Dribble Moves",
                "Footwork",
                "Conditioning",
                "Film Study"
            ]
        case .tennis:
            return [
                "Serve Practice",
                "Forehand Consistency",
                "Backhand Consistency",
                "Volley Drills",
                "Footwork & Movement",
                "Return of Serve",
                "Drop Shots",
                "Overhead Smash",
                "Slice Technique",
                "Topspin Practice",
                "Match Play",
                "Conditioning"
            ]
        case .soccer:
            return [
                "First Touch",
                "Passing Accuracy",
                "Shooting Practice",
                "Weak Foot Work",
                "Dribbling",
                "1v1 Moves",
                "Crossing",
                "Set Pieces",
                "Defensive Positioning",
                "Heading",
                "Speed & Agility",
                "Fitness"
            ]
        case .football:
            return [
                "Route Running",
                "Catching Drills",
                "Throwing Mechanics",
                "Footwork",
                "Blocking Technique",
                "Tackling Form",
                "Speed Training",
                "Strength Work",
                "Film Study",
                "Playbook Review",
                "Conditioning",
                "Position-Specific"
            ]
        }
    }
}

#Preview {
    TrainingSessionView(sport: .basketball)
        .environmentObject(SessionManager.shared)
}
