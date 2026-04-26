//
//  SettingsView.swift
//  SportsHub
//
//  Settings and preferences
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    @State private var showEditUsername = false
    @State private var showEditDisplayName = false
    @State private var showTrainingProfile = false

    var body: some View {
        List {
            Section("Appearance") {
                Toggle(isOn: $isDarkMode) {
                    HStack {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(.appPrimary)
                        Text("Dark Mode")
                    }
                }

                // Theme color is fixed (not configurable in this version)
            }

            Section("Notifications") {
                Toggle(isOn: $notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.appPrimary)
                            Text("In-App Alerts")
                        }
                        Text("Controls in-app alerts · local delivery only, no push")
                            .font(.caption)
                            .foregroundColor(Color.appTextSecondary)
                    }
                }


            }

            Section("Health & Fitness") {
                NavigationLink {
                    SmartwatchSyncView()
                } label: {
                    HStack {
                        Image(systemName: "figure.run.circle.fill")
                            .foregroundColor(.appPrimary)
                        Text("Connect Fitness Tracker")
                    }
                }
            }

            Section("Training Profile") {
                NavigationLink {
                    TrainingProfileSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "figure.run.square.stack.fill")
                            .foregroundColor(.appPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edit Training Profile")
                            Text("Update sport, skill ratings, and goals")
                                .font(.caption)
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                }
            }

            Section("Account") {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.appPrimary)
                    Text("Email")
                    Spacer()
                    Text(sessionManager.currentUser?.email ?? "")
                        .foregroundColor(Color.appSecondary)
                }

                Button(action: { showEditDisplayName = true }) {
                    HStack {
                        Image(systemName: "person.text.rectangle.fill")
                            .foregroundColor(.appPrimary)
                        Text("Display Name")
                        Spacer()
                        Text(sessionManager.currentUser?.displayName ?? "")
                            .foregroundColor(Color.appSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color.appSecondary)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: { showEditUsername = true }) {
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.appPrimary)
                        Text("Username")
                        Spacer()
                        Text("@\(sessionManager.currentUser?.username ?? "")")
                            .foregroundColor(Color.appSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color.appSecondary)
                    }
                }
                .buttonStyle(.plain)
                
                // Phase 4: Dispute History
                NavigationLink {
                    DisputeHistoryView()
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Dispute History")
                    }
                }
            }

            Section("About") {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.appPrimary)
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(Color.appSecondary)
                }

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.appPrimary)
                        Text("Privacy Policy")
                    }
                }

                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.appPrimary)
                        Text("Terms of Service")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    sessionManager.logout()
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.square.fill")
                        Text("Sign Out")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showEditDisplayName) {
            EditDisplayNameSheet(currentDisplayName: sessionManager.currentUser?.displayName ?? "")
        }
        .sheet(isPresented: $showEditUsername) {
            EditUsernameSheet(currentUsername: sessionManager.currentUser?.username ?? "")
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last updated: March 11, 2026")
                    .foregroundColor(.appSecondary)

                Text("SportsHub is committed to protecting your privacy. This policy outlines how we collect, use, and safeguard your information.")
                    .padding(.top, Spacing.md)

                Text("Information We Collect")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• Account information (email, username)\n• Performance data and statistics\n• Match history and rankings\n• User-generated content (posts, clips, messages)")

                Text("How We Use Your Information")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• To provide and improve our services\n• To match you with other players\n• To calculate rankings and statistics\n• To send important notifications")

                Text("Data Security")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("We implement industry-standard security measures to protect your data, including encryption and secure authentication.")
            }
            .padding(Spacing.lg)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Terms of Service")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last updated: March 11, 2026")
                    .foregroundColor(.appSecondary)

                Text("By using SportsHub, you agree to these terms and conditions.")
                    .padding(.top, Spacing.md)

                Text("User Conduct")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• Be respectful to other users\n• No harassment or bullying\n• No cheating or match manipulation\n• Report inappropriate content")

                Text("Account Responsibilities")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• Maintain accurate information\n• Keep your password secure\n• Don't share your account\n• You're responsible for account activity")

                Text("Content Rights")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• You retain rights to content you post\n• You grant SportsHub a license to display your content\n• Don't post copyrighted material without permission")
            }
            .padding(Spacing.lg)
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Edit Username Sheet

struct EditDisplayNameSheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    let currentDisplayName: String
    @State private var newDisplayName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                // Header
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.appPrimary)
                    
                    Text("Change Display Name")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Your current display name: \(currentDisplayName)")
                        .font(.subheadline)
                        .foregroundColor(.appSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, Spacing.lg)
                
                // Display name input
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("New Display Name")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.appTextPrimary)
                    
                    TextField("Display Name", text: $newDisplayName)
                        .font(.body)
                        .padding(Spacing.md)
                        .background(Color.appSurface)
                        .cornerRadius(CornerRadius.md)
                    
                    Text("This is the name shown in greetings and your profile. It can contain spaces and special characters.")
                        .font(.caption)
                        .foregroundColor(.appSecondary)
                        .padding(.horizontal, Spacing.sm)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, Spacing.sm)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                
                Spacer()
                
                // Save button
                Button(action: saveDisplayName) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save Changes")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canSave ? Color.appPrimary : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(CornerRadius.md)
                .padding(.horizontal, Spacing.lg)
                .disabled(!canSave || isSaving)
            }
            .padding(.bottom, Spacing.lg)
            .navigationTitle("Display Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your display name has been updated successfully!")
            }
        }
        .onAppear {
            newDisplayName = currentDisplayName
        }
    }
    
    private var canSave: Bool {
        !newDisplayName.isEmpty && newDisplayName.count <= 100 && newDisplayName != currentDisplayName
    }
    
    private func saveDisplayName() {
        guard canSave else { return }
        
        isSaving = true
        errorMessage = nil
        
        Task {
            do {
                try await APIClient.shared.updateDisplayName(newDisplayName: newDisplayName)
                
                await MainActor.run {
                    sessionManager.updateDisplayName(newDisplayName)
                    isSaving = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = (error as? APIError)?.userFriendlyMessage ?? "We couldn't update your display name. Please try again."
                }
            }
        }
    }
}

struct EditUsernameSheet: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    
    let currentUsername: String
    @State private var newUsername: String = ""
    @State private var isChecking = false
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var validationState: ValidationState = .none
    @State private var showSuccessAlert = false
    
    enum ValidationState {
        case none
        case checking
        case valid
        case invalid(String)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                // Header
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.appPrimary)
                    
                    Text("Change Username")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Your current username: @\(currentUsername)")
                        .font(.subheadline)
                        .foregroundColor(.appSecondary)
                }
                .padding(.top, Spacing.lg)
                
                // Username input
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("New Username")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.appTextPrimary)
                    
                    HStack {
                        Text("@")
                            .font(.headline)
                            .foregroundColor(.appSecondary)
                        
                        TextField("username", text: $newUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body)
                            .onChange(of: newUsername) { _, newValue in
                                validateUsername(newValue)
                            }
                        
                        if isChecking {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if case .valid = validationState {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if case .invalid = validationState {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color.appSurface)
                    .cornerRadius(CornerRadius.md)
                    
                    // Validation message
                    if let message = validationMessage {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: validationIcon)
                                .font(.caption)
                                .foregroundColor(validationColor)
                            Text(message)
                                .font(.caption)
                                .foregroundColor(validationColor)
                        }
                        .padding(.horizontal, Spacing.sm)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                
                // Guidelines
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Username Guidelines")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.appSecondary)
                    
                    GuidelineRow(text: "3-20 characters long", isValid: newUsername.count >= 3 && newUsername.count <= 20)
                    GuidelineRow(text: "Letters, numbers, and underscores only", isValid: isValidFormat(newUsername))
                    GuidelineRow(text: "Must be unique", isValid: isUsernameUnique)
                }
                .padding(Spacing.md)
                .background(Color.appSurface.opacity(0.5))
                .cornerRadius(CornerRadius.md)
                .padding(.horizontal, Spacing.lg)
                
                Spacer()
                
                // Save button
                Button(action: saveUsername) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Update Username")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.md)
                    .background(canSave ? Color.appPrimary : Color.appSecondary.opacity(0.5))
                    .cornerRadius(CornerRadius.md)
                }
                .disabled(!canSave || isSaving)
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Username Updated", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your username has been successfully changed to @\(newUsername)")
            }
        }
        .onAppear {
            newUsername = currentUsername
        }
    }
    
    private var canSave: Bool {
        guard case .valid = validationState else { return false }
        return newUsername != currentUsername && !isSaving
    }
    
    private var isUsernameUnique: Bool {
        if case .valid = validationState {
            return true
        }
        return false
    }
    
    private var validationIcon: String {
        switch validationState {
        case .valid:
            return "checkmark.circle.fill"
        case .invalid:
            return "xmark.circle.fill"
        default:
            return "info.circle"
        }
    }
    
    private var validationColor: Color {
        switch validationState {
        case .valid:
            return .green
        case .invalid:
            return .red
        default:
            return .appSecondary
        }
    }
    
    private func isValidFormat(_ username: String) -> Bool {
        // Letters, numbers, underscores only
        let regex = "^[a-zA-Z0-9_]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: username)
    }
    
    private func validateUsername(_ username: String) {
        // Reset validation
        validationMessage = nil
        
        // Trim whitespace
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        if trimmed != username {
            newUsername = trimmed
            return
        }
        
        // Check if same as current
        if username == currentUsername {
            validationState = .none
            validationMessage = "This is your current username"
            return
        }
        
        // Check length
        if username.isEmpty {
            validationState = .none
            return
        }
        
        if username.count < 3 {
            validationState = .invalid("Username must be at least 3 characters")
            validationMessage = "Too short (minimum 3 characters)"
            return
        }
        
        if username.count > 20 {
            validationState = .invalid("Username must be 20 characters or less")
            validationMessage = "Too long (maximum 20 characters)"
            return
        }
        
        // Check format
        if !isValidFormat(username) {
            validationState = .invalid("Only letters, numbers, and underscores allowed")
            validationMessage = "Invalid characters (use letters, numbers, _ only)"
            return
        }
        
        // Check for profanity (basic list)
        let profanityList = ["fuck", "shit", "damn", "bitch", "ass", "crap"]
        if profanityList.contains(where: { username.lowercased().contains($0) }) {
            validationState = .invalid("Username contains inappropriate language")
            validationMessage = "Please choose a different username"
            return
        }
        
        // Check availability with backend
        checkAvailability(username)
    }
    
    private func checkAvailability(_ username: String) {
        isChecking = true
        validationState = .checking
        validationMessage = "Checking availability..."
        
        Task {
            do {
                let available = try await APIClient.shared.checkUsernameAvailability(username: username)
                
                await MainActor.run {
                    isChecking = false
                    if available {
                        validationState = .valid
                        validationMessage = "✓ Username available"
                    } else {
                        validationState = .invalid("Username already taken")
                        validationMessage = "Username is already taken"
                    }
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                    let message = (error as? APIError)?.userFriendlyMessage ?? "Unable to check availability. Please try again."
                    validationState = .invalid("Could not verify availability")
                    validationMessage = message
                }
            }
        }
    }
    
    private func saveUsername() {
        isSaving = true
        
        Task {
            do {
                try await APIClient.shared.updateUsername(newUsername: newUsername)
                
                await MainActor.run {
                    isSaving = false
                    // Update session manager
                    sessionManager.updateUsername(newUsername)
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    let message = (error as? APIError)?.userFriendlyMessage ?? "We couldn't update your username. Please try again."
                    validationState = .invalid("Failed to update username")
                    validationMessage = message
                }
            }
        }
    }
}

struct GuidelineRow: View {
    let text: String
    let isValid: Bool
    
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isValid ? .green : .appSecondary)
            Text(text)
                .font(.caption)
                .foregroundColor(isValid ? .appTextPrimary : .appSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(SessionManager.shared)
    }
}

// MARK: - Training Profile Settings View

/// Full editable athlete survey reachable from Settings → Training Profile.
/// Submits the idempotent POST /onboarding/survey endpoint (upsert).
/// Detects material skill improvements (≤3 → ≥5) and clears stale AI Coach
/// weakness cache entries so the next session uses the refreshed baseline.
struct TrainingProfileSettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSport: Sport = .basketball
    @State private var skillRatings: [String: Int] = [:]
    @State private var originalSkillRatings: [String: Int] = [:]
    /// Skills the athlete has explicitly rated (even if set to 5). Skills NOT in this set
    /// are displayed as "Not rated" and excluded from the save payload.
    @State private var ratedSkills: Set<String> = []
    @State private var selectedStrengths: Set<String> = []
    @State private var selectedWeaknesses: Set<String> = []
    @State private var selectedGoals: Set<String> = []

    @State private var isSaving = false
    @State private var saveSuccess = false
    @State private var errorMessage: String?

    private static let surveyLocalKey        = "ai_coach_survey_cache"
    private static let coachContextKeyPrefix = "ai_coach_context_"

    // MARK: - Computed

    private var skillKeys: [String] {
        SurveySkillDefinitions.skills[selectedSport] ?? []
    }
    private var strengthOptions: [String] {
        SurveySkillDefinitions.strengths[selectedSport] ?? []
    }
    private var weaknessOptions: [String] {
        SurveySkillDefinitions.weaknesses[selectedSport] ?? []
    }
    /// Sport-specific training goals the athlete can declare for AI Coach context.
    private var goalOptions: [String] {
        switch selectedSport {
        case .basketball:
            return ["Make varsity team", "Become a starter", "Improve shooting percentage",
                    "Increase athleticism", "Play in college", "Be a better teammate", "Improve defense"]
        case .football:
            return ["Make varsity team", "Master my position", "Get recruited",
                    "Improve physical conditioning", "Be a team leader", "Increase speed and strength",
                    "Improve playbook knowledge"]
        case .soccer:
            return ["Make varsity team", "Score more goals", "Become a starter",
                    "Get recruited", "Improve fitness", "Develop leadership", "Improve game vision"]
        case .tennis:
            return ["Win at local tournaments", "Improve ranking", "Get to varsity",
                    "Develop a consistent serve", "Improve footwork", "Play at college level",
                    "Compete regionally"]
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                Text("Update your training profile so the AI Coach reflects your real skill level. Changes take effect in your next conversation.")
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
            }

            // MARK: Sport picker
            Section("Primary Sport") {
                Picker("Sport", selection: $selectedSport) {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        Text(sport.rawValue.capitalized).tag(sport)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: Skill ratings
            Section {
                ForEach(skillKeys, id: \.self) { skill in
                    let isRated = ratedSkills.contains(skill)
                    HStack {
                        Text(skill)
                            .font(.subheadline)
                        Spacer()
                        if isRated {
                            Stepper(
                                value: Binding(
                                    get: { skillRatings[skill] ?? 5 },
                                    set: { newVal in
                                        skillRatings[skill] = newVal
                                        ratedSkills.insert(skill)
                                    }
                                ),
                                in: 1...10
                            ) {
                                ProfileRatingBadge(rating: skillRatings[skill] ?? 5)
                            }
                        } else {
                            Button("Rate this skill") {
                                skillRatings[skill] = 5
                                ratedSkills.insert(skill)
                            }
                            .font(.caption)
                            .foregroundColor(.appPrimary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Skill Ratings")
            } footer: {
                Text("Tap \"Rate this skill\" to add a rating. Unrated skills are excluded from your AI Coach baseline. 1 = Beginner · 5 = Average · 10 = Elite.")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            // MARK: Strengths
            Section("Strengths") {
                ForEach(strengthOptions, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: { selectedStrengths.contains(option) },
                        set: { on in
                            if on { selectedStrengths.insert(option) }
                            else  { selectedStrengths.remove(option) }
                        }
                    ))
                    .tint(.appSuccess)
                    .font(.subheadline)
                }
            }

            // MARK: Weaknesses / Focus Areas
            Section {
                ForEach(weaknessOptions, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: { selectedWeaknesses.contains(option) },
                        set: { on in
                            if on { selectedWeaknesses.insert(option) }
                            else  { selectedWeaknesses.remove(option) }
                        }
                    ))
                    .tint(.appPrimary)
                    .font(.subheadline)
                }
            } header: {
                Text("Focus Areas")
            } footer: {
                Text("Areas you want to improve. The AI Coach prioritises drills for these areas.")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            // MARK: Goals
            Section {
                ForEach(goalOptions, id: \.self) { option in
                    Toggle(option, isOn: Binding(
                        get: { selectedGoals.contains(option) },
                        set: { on in
                            if on { selectedGoals.insert(option) }
                            else  { selectedGoals.remove(option) }
                        }
                    ))
                    .tint(.appAccent)
                    .font(.subheadline)
                }
            } header: {
                Text("Training Goals")
            } footer: {
                Text("What you are working toward this season. The AI Coach surfaces these in your coaching context.")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            // MARK: Save
            Section {
                if saveSuccess {
                    Label(
                        "Profile updated! AI Coach will reflect your changes next session.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundColor(.appSuccess)
                    .font(.subheadline)
                }
                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.appError)
                        .font(.caption)
                }
                Button { saveProfile() } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Training Profile")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            } footer: {
                Text("Saving immediately updates your AI Coach baseline.")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .navigationTitle("Training Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadFromCache() }
        .onChange(of: selectedSport) { _ in refreshSkillsForCurrentSport() }
    }

    // MARK: - Data

    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.surveyLocalKey),
              let survey = try? JSONDecoder().decode(OnboardingSurveyResponse.self, from: data) else {
            // No cached survey — all skills start as unrated (do NOT default to 5)
            return
        }
        if let sport = Sport(rawValue: survey.mainSport) { selectedSport = sport }
        skillRatings         = survey.skillRatings
        originalSkillRatings = survey.skillRatings
        // Mark every skill with a prior rating as "rated" — the rest remain unrated
        ratedSkills          = Set(survey.skillRatings.keys)
        selectedStrengths    = Set(survey.strengths)
        selectedWeaknesses   = Set(survey.weaknesses)
        selectedGoals        = Set(survey.goals)
    }

    /// Called when sport changes. Does NOT assign default ratings — new skills start unrated.
    private func refreshSkillsForCurrentSport() {
        // Intentionally empty: unknown skills stay unrated until the athlete actively sets them.
        // The UI shows a "Rate this skill" button for any skill not in ratedSkills.
    }

    // MARK: - Save

    private func saveProfile() {
        guard SessionManager.shared.backendAvailable else {
            errorMessage = "Server offline — profile changes can't be saved right now."
            return
        }
        isSaving     = true
        errorMessage = nil
        saveSuccess  = false

        let improved = detectMaterialImprovements()

        // Only send skills the athlete has explicitly rated — exclude unrated (nil) ones.
        let ratedPayload = skillRatings.filter { ratedSkills.contains($0.key) }

        let request = OnboardingSurveyRequest(
            mainSport: selectedSport.rawValue,
            skillRatings: ratedPayload,
            strengths: Array(selectedStrengths),
            weaknesses: Array(selectedWeaknesses),
            goals: Array(selectedGoals),
            onboardingVersion: 1
        )

        Task {
            do {
                try await APIClient.shared.submitOnboardingSurvey(request)

                // Clear stale AI Coach weakness cache for materially improved skills
                if !improved.isEmpty {
                    clearStaleWeaknessCache(for: improved)
                }

                // Refresh local survey cache from server so AI Coach sees updated values
                if let fresh = try? await APIClient.shared.getOnboardingSurvey(),
                   let encoded = try? JSONEncoder().encode(fresh) {
                    UserDefaults.standard.set(encoded, forKey: Self.surveyLocalKey)
                }

                CoachTelemetry.recordSurveyUpdated(sport: selectedSport, changedSkillCount: improved.count)

                await MainActor.run {
                    originalSkillRatings = skillRatings
                    isSaving    = false
                    saveSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSaving     = false
                    errorMessage = "Couldn't save your profile. Please try again."
                }
            }
        }
    }

    /// Skills that moved from ≤3 to ≥5 — qualifies as a material improvement.
    /// Only considers skills that were rated in the original survey (had a value ≤3).
    private func detectMaterialImprovements() -> [String] {
        ratedSkills.compactMap { skill in
            guard let newRating = skillRatings[skill] else { return nil }
            let old = originalSkillRatings[skill] ?? 0
            return (old > 0 && old <= 3 && newRating >= 5) ? skill : nil
        }
    }

    /// Removes improved skill keys from the AI Coach's stale recurring-weakness cache
    /// stored under "ai_coach_context_<sport>" in UserDefaults.
    private func clearStaleWeaknessCache(for skills: [String]) {
        let contextKey = "\(Self.coachContextKeyPrefix)\(selectedSport.rawValue)"
        guard var dict = UserDefaults.standard.dictionary(forKey: contextKey),
              var weaknesses = dict["recurringWeaknesses"] as? [String: Int] else { return }
        let lowered = skills.map { $0.lowercased() }
        for skill in lowered { weaknesses.removeValue(forKey: skill) }
        dict["recurringWeaknesses"] = weaknesses
        UserDefaults.standard.set(dict, forKey: contextKey)
    }
}

/// Small colored badge showing a skill self-rating (1-10).
private struct ProfileRatingBadge: View {
    let rating: Int

    var color: Color {
        switch rating {
        case 1...3: return .appError
        case 4...6: return .orange
        default:    return .appSuccess
        }
    }

    var label: String {
        switch rating {
        case 1...3: return "Needs work"
        case 4...6: return "Developing"
        default:    return "Strong"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(rating)/10")
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(6)
    }
}
