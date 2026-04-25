//
//  WorkoutBuilderView.swift
//  SportsHub
//
//  Custom workout builder for training
//

import SwiftUI

struct WorkoutBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workoutName = ""
    @State private var selectedSport: Sport = .basketball
    @State private var drills: [WorkoutDrill] = []
    @State private var showingAddDrill = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Workout Details") {
                    TextField("Workout Name", text: $workoutName)
                    
                    Picker("Sport", selection: $selectedSport) {
                        ForEach(Sport.allCases, id: \.self) { sport in
                            Text(sport.rawValue.capitalized).tag(sport)
                        }
                    }
                }

                Section {
                    Label(StorageStrategy.localOnly.disclosureLabel, systemImage: "iphone")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                Section {
                    ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                        DrillRow(drill: drill, index: index + 1)
                    }
                    .onDelete(perform: deleteDrill)
                    .onMove(perform: moveDrill)
                    
                    Button {
                        showingAddDrill = true
                    } label: {
                        Label("Add Drill", systemImage: "plus.circle.fill")
                            .foregroundColor(.appPrimary)
                    }
                } header: {
                    Text("Drills (\(drills.count))")
                }
                
                if !drills.isEmpty {
                    Section {
                        HStack {
                            Text("Total Duration")
                                .foregroundColor(.appSecondary)
                            Spacer()
                            Text(totalDurationText)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Build Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        saveWorkout()
                    }
                    .disabled(workoutName.isEmpty || drills.isEmpty)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        startWorkout()
                    } label: {
                        Label("Start Workout", systemImage: "play.fill")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(workoutName.isEmpty || drills.isEmpty ? Color.gray : Color.appPrimary)
                            .cornerRadius(CornerRadius.md)
                    }
                    .disabled(workoutName.isEmpty || drills.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddDrill) {
                AddDrillView { drill in
                    drills.append(drill)
                }
            }
            .sheet(isPresented: $showWorkoutSession) {
                if let workout = savedWorkout {
                    WorkoutSessionView(workout: workout)
                }
            }
        }
    }
    
    private var totalDurationText: String {
        let totalMinutes = drills.reduce(0) { $0 + $1.durationMinutes }
        return "\(totalMinutes) min"
    }
    
    private func deleteDrill(at offsets: IndexSet) {
        drills.remove(atOffsets: offsets)
    }
    
    private func moveDrill(from source: IndexSet, to destination: Int) {
        drills.move(fromOffsets: source, toOffset: destination)
    }
    
    @State private var showWorkoutSession = false
    @State private var savedWorkout: SavedWorkout?
    
    private func saveWorkout() {
        // Encode and persist full workout to UserDefaults
        let workout = SavedWorkout(
            name: workoutName,
            sport: selectedSport,
            drills: drills,
            createdAt: Date()
        )
        var existing: [SavedWorkout] = []
        if let data = UserDefaults.standard.data(forKey: "saved_workouts_v2"),
           let decoded = try? JSONDecoder().decode([SavedWorkout].self, from: data) {
            existing = decoded
        }
        existing.append(workout)
        if let encoded = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(encoded, forKey: "saved_workouts_v2")
        }
        dismiss()
    }
    
    private func startWorkout() {
        savedWorkout = SavedWorkout(
            name: workoutName,
            sport: selectedSport,
            drills: drills,
            createdAt: Date()
        )
        showWorkoutSession = true
    }
}

struct WorkoutDrill: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var durationMinutes: Int
    var sets: Int
    var reps: Int?
    var restSeconds: Int
    
    init(name: String, description: String, durationMinutes: Int, sets: Int, reps: Int? = nil, restSeconds: Int) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.durationMinutes = durationMinutes
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
    }
}

struct DrillRow: View {
    let drill: WorkoutDrill
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("\(index).")
                    .font(.caption)
                    .foregroundColor(.appSecondary)
                    .frame(width: 24, alignment: .leading)
                
                Text(drill.name)
                    .font(.headline)
                    .foregroundColor(.appTextPrimary)
            }
            
            if !drill.description.isEmpty {
                Text(drill.description)
                    .font(.caption)
                    .foregroundColor(.appSecondary)
                    .padding(.leading, 30)
            }
            
            HStack(spacing: Spacing.lg) {
                Label("\(drill.durationMinutes) min", systemImage: "clock")
                Label("\(drill.sets) sets", systemImage: "repeat")
                if let reps = drill.reps {
                    Label("\(reps) reps", systemImage: "number")
                }
                Label("\(drill.restSeconds)s rest", systemImage: "pause")
            }
            .font(.caption)
            .foregroundColor(.appSecondary)
            .padding(.leading, 30)
        }
        .padding(.vertical, Spacing.xs)
    }
}

struct AddDrillView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var drillName = ""
    @State private var drillDescription = ""
    @State private var duration = 5
    @State private var sets = 3
    @State private var reps = 10
    @State private var includeReps = true
    @State private var restSeconds = 60
    @State private var selectedCategory: WorkoutDrillCategory = .warmup
    
    let onAdd: (WorkoutDrill) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Drill Info") {
                    TextField("Drill Name", text: $drillName)
                    TextField("Description (optional)", text: $drillDescription)
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(WorkoutDrillCategory.allCases, id: \.self) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }
                
                Section("Duration") {
                    Stepper("\(duration) minutes", value: $duration, in: 1...60)
                }
                
                Section("Sets & Reps") {
                    Stepper("\(sets) sets", value: $sets, in: 1...20)
                    
                    Toggle("Include Reps", isOn: $includeReps)
                    
                    if includeReps {
                        Stepper("\(reps) reps", value: $reps, in: 1...100)
                    }
                }
                
                Section("Rest") {
                    Stepper("\(restSeconds) seconds", value: $restSeconds, in: 0...300, step: 15)
                }
                
                Section("Quick Templates") {
                    Button("Shooting Drill") {
                        applyTemplate(.shooting)
                    }
                    Button("Conditioning") {
                        applyTemplate(.conditioning)
                    }
                    Button("Skill Work") {
                        applyTemplate(.skillWork)
                    }
                }
            }
            .navigationTitle("Add Drill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Add") {
                        let drill = WorkoutDrill(
                            name: drillName,
                            description: drillDescription,
                            durationMinutes: duration,
                            sets: sets,
                            reps: includeReps ? reps : nil,
                            restSeconds: restSeconds
                        )
                        onAdd(drill)
                        dismiss()
                    }
                    .disabled(drillName.isEmpty)
                }
            }
        }
    }
    
    private func applyTemplate(_ template: DrillTemplate) {
        switch template {
        case .shooting:
            drillName = "Shooting Practice"
            drillDescription = "Form shooting from various spots"
            duration = 15
            sets = 5
            reps = 20
            includeReps = true
            restSeconds = 45
            selectedCategory = .skill
            
        case .conditioning:
            drillName = "Conditioning Run"
            drillDescription = "Sprint intervals for endurance"
            duration = 20
            sets = 8
            reps = 1
            includeReps = false
            restSeconds = 90
            selectedCategory = .conditioning
            
        case .skillWork:
            drillName = "Ball Handling"
            drillDescription = "Dribbling and control exercises"
            duration = 10
            sets = 4
            reps = 15
            includeReps = true
            restSeconds = 30
            selectedCategory = .skill
        }
    }
}

enum WorkoutDrillCategory: String, CaseIterable {
    case warmup = "Warm-up"
    case skill = "Skill Development"
    case conditioning = "Conditioning"
    case strength = "Strength"
    case cooldown = "Cool-down"
}

enum DrillTemplate {
    case shooting
    case conditioning
    case skillWork
}

struct WorkoutSessionView: View {
    let workout: SavedWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var currentDrillIndex = 0
    @State private var timeRemaining = 0
    @State private var isActive = false
    @State private var isResting = false
    @State private var currentSet = 1
    @State private var timer: Timer?
    @State private var startTime = Date()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                // Progress
                VStack(spacing: Spacing.sm) {
                    Text("Drill \(currentDrillIndex + 1) of \(workout.drills.count)")
                        .font(.caption)
                        .foregroundColor(.appSecondary)
                    
                    ProgressView(value: Double(currentDrillIndex), total: Double(workout.drills.count))
                        .tint(.appPrimary)
                }
                .padding(.horizontal, Spacing.xl)
                
                Spacer()
                
                // Current drill
                if currentDrillIndex < workout.drills.count {
                    let drill = workout.drills[currentDrillIndex]
                    
                    VStack(spacing: Spacing.lg) {
                        Text(drill.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.appTextPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text(drill.description)
                            .font(.body)
                            .foregroundColor(.appSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.xl)
                        
                        // Timer
                        ZStack {
                            Circle()
                                .stroke(Color.appSecondary.opacity(0.3), lineWidth: 12)
                                .frame(width: 200, height: 200)
                            
                            Circle()
                                .trim(from: 0, to: timerProgress)
                                .stroke(isResting ? Color.orange : Color.appPrimary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .frame(width: 200, height: 200)
                                .rotationEffect(.degrees(-90))
                            
                            VStack(spacing: Spacing.xs) {
                                Text(timeString)
                                    .font(.system(size: 48, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                
                                Text(isResting ? "Rest" : "Work")
                                    .font(.caption)
                                    .foregroundColor(.appSecondary)
                            }
                        }
                        
                        // Sets counter
                        Text("Set \(currentSet) of \(drill.sets)")
                            .font(.headline)
                            .foregroundColor(.appSecondary)
                    }
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: Spacing.xl) {
                    Button {
                        skipDrill()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundColor(.appPrimary)
                            .frame(width: 60, height: 60)
                            .background(Color.appPrimary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    Button {
                        toggleTimer()
                    } label: {
                        Image(systemName: isActive ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(Color.appPrimary)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        finishWorkout()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.red)
                            .frame(width: 60, height: 60)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
            .navigationBarHidden(true)
            .onAppear {
                startTime = Date()
                if currentDrillIndex < workout.drills.count {
                    timeRemaining = workout.drills[currentDrillIndex].durationMinutes * 60
                }
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }
    
    private var timerProgress: CGFloat {
        guard currentDrillIndex < workout.drills.count else { return 0 }
        let drill = workout.drills[currentDrillIndex]
        let totalTime = isResting ? drill.restSeconds : drill.durationMinutes * 60
        return CGFloat(timeRemaining) / CGFloat(totalTime)
    }
    
    private var timeString: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func toggleTimer() {
        isActive.toggle()
        
        if isActive {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if timeRemaining > 0 {
                    timeRemaining -= 1
                } else {
                    handleTimerComplete()
                }
            }
        } else {
            timer?.invalidate()
        }
    }
    
    private func handleTimerComplete() {
        guard currentDrillIndex < workout.drills.count else { return }
        let drill = workout.drills[currentDrillIndex]
        
        if isResting {
            // Rest complete, start next set or drill
            if currentSet < drill.sets {
                currentSet += 1
                timeRemaining = drill.durationMinutes * 60
                isResting = false
            } else {
                nextDrill()
            }
        } else {
            // Work complete, start rest
            if currentSet < drill.sets {
                timeRemaining = drill.restSeconds
                isResting = true
            } else {
                nextDrill()
            }
        }
    }
    
    private func nextDrill() {
        if currentDrillIndex < workout.drills.count - 1 {
            currentDrillIndex += 1
            currentSet = 1
            isResting = false
            timeRemaining = workout.drills[currentDrillIndex].durationMinutes * 60
        } else {
            finishWorkout()
        }
    }
    
    private func skipDrill() {
        timer?.invalidate()
        isActive = false
        nextDrill()
    }
    
    private func finishWorkout() {
        timer?.invalidate()
        logCompletedSession()
        dismiss()
    }
    
    private func logCompletedSession() {
        let durationMinutes = Int(Date().timeIntervalSince(startTime) / 60)
        let drillNames = workout.drills.map { $0.name }
        let sessionData: [String: Any] = [
            "workout_name": workout.name,
            "drills_completed": drillNames,
            "duration_minutes": max(durationMinutes, 1),
            "notes": "Completed \(currentDrillIndex + 1) of \(workout.drills.count) drills"
        ]
        Task {
            do {
                let _ = try await APIClient.shared.analyzeTrainingSession(
                    sport: workout.sport,
                    sessionData: sessionData
                )
            } catch {
                // Best-effort — session still counts locally even if backend is unreachable
                print("Training session log failed: \(error)")
            }
        }
    }
}

struct SavedWorkout: Identifiable, Codable {
    let id: UUID
    let name: String
    let sport: Sport
    let drills: [WorkoutDrill]
    let createdAt: Date
    
    init(name: String, sport: Sport, drills: [WorkoutDrill], createdAt: Date) {
        self.id = UUID()
        self.name = name
        self.sport = sport
        self.drills = drills
        self.createdAt = createdAt
    }
}

#Preview {
    WorkoutBuilderView()
}
