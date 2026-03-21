//
//  TrainingSessionView.swift
//  SportsHub
//
//  Training session logging and tracking
//

import SwiftUI
import PhotosUI

struct TrainingSessionView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    
    let sport: Sport
    var prefilledDrillName: String? = nil
    
    @State private var drillName = ""
    @State private var duration = 30
    @State private var metricType: MetricType = .reps
    @State private var metricValue = ""
    @State private var effort: EffortLevel = .moderate
    @State private var notes = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var photoImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Drill Information
                Section("Drill Information") {
                    TextField("Drill Name", text: $drillName)
                        .textInputAutocapitalization(.words)
                    
                    Picker("Sport", selection: .constant(sport)) {
                        Text(sport.rawValue).tag(sport)
                    }
                    .disabled(true)
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        Stepper("\(duration) min", value: $duration, in: 5...180, step: 5)
                    }
                }
                
                // Metrics
                Section("Performance Metrics") {
                    Picker("Metric Type", selection: $metricType) {
                        ForEach(MetricType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    
                    HStack {
                        Text(metricType.rawValue)
                        Spacer()
                        TextField("Value", text: $metricValue)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                }
                
                // Effort & Notes
                Section("Training Details") {
                    Picker("Effort Level", selection: $effort) {
                        ForEach(EffortLevel.allCases, id: \.self) { level in
                            HStack {
                                Text(level.rawValue)
                                Spacer()
                                Text(level.emoji)
                            }
                            .tag(level)
                        }
                    }
                    
                    TextEditor(text: $notes)
                        .frame(height: 100)
                        .overlay(
                            Group {
                                if notes.isEmpty {
                                    Text("Add notes about this session...")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }
                
                // Photo Evidence
                Section("Evidence (Optional)") {
                    if photoImages.isEmpty {
                        Button(action: {
                            showImagePicker = true
                        }) {
                            HStack {
                                Image(systemName: "camera")
                                Text("Add Photos")
                            }
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
            .navigationTitle("Log Training Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveSession()
                        }
                    }
                    .disabled(!isFormValid || isLoading)
                }
            }
            .onAppear {
                if let prefilled = prefilledDrillName {
                    drillName = prefilled
                }
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
                Text("Training session logged successfully!")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isFormValid: Bool {
        !drillName.isEmpty && !metricValue.isEmpty
    }
    
    private func saveSession() async {
        isLoading = true
        defer { isLoading = false }
        
        // TODO: API call to save training session
        // For now, just show success
        try? await Task.sleep(nanoseconds: 500_000_000)
        showSuccess = true
    }
}

// MARK: - Supporting Types

enum MetricType: String, CaseIterable {
    case reps = "Reps"
    case makes = "Makes"
    case attempts = "Attempts"
    case distance = "Distance (m)"
    case time = "Time (sec)"
    case weight = "Weight (lbs)"
    case sets = "Sets"
    case accuracy = "Accuracy (%)"
}

enum EffortLevel: String, CaseIterable {
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

#Preview {
    TrainingSessionView(sport: .basketball)
        .environmentObject(SessionManager.shared)
}
