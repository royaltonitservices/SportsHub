//
//  AICoachChatView.swift
//  SportsHub
//
//  Conversational AI Coach - Premium Feature
//  Chat-style interface with proactive engagement
//

import SwiftUI
import Combine

struct AICoachChatView: View {
    let sport: Sport
    let initialPrompt: String?
    
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var viewModel: AICoachChatViewModel
    @StateObject private var voiceManager = VoiceInputManager()
    @State private var messageText = ""
    @State private var showVoiceTranscription = false
    @State private var hasHandledInitialPrompt = false
    @State private var showTrainSection = false
    @State private var showDrillLibrary = false
    @State private var showSessionLog = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    
    init(sport: Sport, initialPrompt: String? = nil) {
        self.sport = sport
        self.initialPrompt = initialPrompt
        _viewModel = StateObject(wrappedValue: AICoachChatViewModel(sport: sport))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        // Welcome message
                        if viewModel.messages.isEmpty && !viewModel.isLoading {
                            welcomeMessage
                        }
                        
                        // Chat messages
                        ForEach(viewModel.messages) { message in
                            AICoachMessageBubble(message: message) { action in
                                handleActionTap(action)
                            }
                            .id(message.id)
                        }
                        
                        // Loading indicator
                        if viewModel.isLoading {
                            LoadingBubble()
                        }
                        
                        // Proactive check-in
                        if let checkin = viewModel.proactiveCheckin {
                            ProactiveCheckinBubble(message: checkin)
                        }
                    }
                    .padding(Spacing.md)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // Auto-scroll to bottom on new message
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input bar
            inputBar
        }
        .navigationTitle("AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive, action: {
                        viewModel.clearConversation()
                    }) {
                        Label("Clear Conversation", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            await viewModel.loadProactiveCheckin()
        }
        .onAppear {
            // Auto-send initial prompt if provided
            if let prompt = initialPrompt, !hasHandledInitialPrompt {
                hasHandledInitialPrompt = true
                messageText = prompt
                // Small delay to let view fully appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    sendMessage()
                }
            }
        }
        // CONNECTED LOOP: AI Coach -> Train -> Session Logging
        .sheet(isPresented: $showDrillLibrary) {
            DrillLibraryView(sport: sport)
        }
        .sheet(isPresented: $showSessionLog) {
            TrainingSessionView(sport: sport)
        }
    }
    
    // MARK: - Welcome Message
    
    private var welcomeMessage: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.appPrimary, Color.appAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: Spacing.sm) {
                Text("Your AI Coach")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Chat with your personal \(sport.rawValue) coach. I'm here to help you improve, stay motivated, and reach your goals!")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SuggestionChip(text: sportSpecificWeakPointQuestion()) {
                    messageText = sportSpecificWeakPointQuestion()
                    sendMessage()
                }
                
                SuggestionChip(text: "What should I work on today?") {
                    messageText = "What should I work on today?"
                    sendMessage()
                }
                
                SuggestionChip(text: "Give me a 20-minute workout") {
                    messageText = "Give me a 20-minute \(sport.rawValue) workout"
                    sendMessage()
                }
                
                SuggestionChip(text: "How should I prepare for my next match?") {
                    messageText = "How should I prepare for my next \(sport.rawValue) match?"
                    sendMessage()
                }
            }
        }
        .padding(.vertical, Spacing.xl)
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        VStack(spacing: 0) {
            // Voice transcription display
            if showVoiceTranscription {
                voiceTranscriptionView
            }
            
            // Error message display
            if let errorMessage = voiceManager.errorMessage {
                errorMessageView(errorMessage)
            }
            
            // Main input bar
            HStack(spacing: Spacing.sm) {
                // Microphone button
                Button(action: handleMicrophoneTap) {
                    Image(systemName: voiceManager.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 24))
                        .foregroundColor(voiceManager.isRecording ? Color.red : Color.appPrimary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(voiceManager.isRecording ? Color.red.opacity(0.1) : Color.appPrimary.opacity(0.1))
                        )
                }
                .disabled(viewModel.isLoading)
                
                TextField("Message your coach...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .disabled(voiceManager.isRecording)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(messageText.isEmpty ? Color.gray : Color.appPrimary)
                }
                .disabled(messageText.isEmpty || viewModel.isLoading)
            }
            .padding(Spacing.md)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color.appTextSecondary.opacity(0.2)),
                alignment: .top
            )
        }
        .onChange(of: voiceManager.transcribedText) { oldValue, newValue in
            if !newValue.isEmpty && !voiceManager.isRecording {
                // Voice recording finished, use transcription
                messageText = newValue
                showVoiceTranscription = false
            }
        }
    }
    
    private var voiceTranscriptionView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                if voiceManager.isRecording {
                    // Recording indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: voiceManager.isRecording)
                        
                        Text("Listening...")
                            .font(.subheadline)
                            .foregroundColor(.appTextSecondary)
                    }
                } else {
                    Text("Tap the microphone again to finish")
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)
                }
                
                Spacer()
                
                Button(action: {
                    voiceManager.cancelRecording()
                    showVoiceTranscription = false
                }) {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.appPrimary)
                }
            }
            
            // Transcription preview
            if !voiceManager.transcribedText.isEmpty {
                Text(voiceManager.transcribedText)
                    .font(.body)
                    .foregroundColor(.appTextPrimary)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appPrimary.opacity(0.05))
                    .cornerRadius(8)
            } else {
                Text("Start speaking...")
                    .font(.body)
                    .italic()
                    .foregroundColor(.appTextSecondary.opacity(0.6))
            }
        }
        .padding(Spacing.md)
        .background(Color.appAccent.opacity(0.05))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.appTextSecondary.opacity(0.2)),
            alignment: .top
        )
    }
    
    private func errorMessageView(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)
            
            Spacer()
            
            Button(action: {
                voiceManager.errorMessage = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Actions
    
    private func handleMicrophoneTap() {
        if voiceManager.isRecording {
            // Stop recording and use transcription
            voiceManager.stopRecording()
            showVoiceTranscription = false
        } else {
            // Start recording
            showVoiceTranscription = true
            isInputFocused = false
            
            Task {
                await voiceManager.startRecording()
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let message = messageText
        messageText = ""
        isInputFocused = false
        showVoiceTranscription = false
        voiceManager.transcribedText = ""

        Task {
            await viewModel.sendMessage(message)
        }
    }

    // SYSTEM INTEGRATION: Connect AI Coach actions to Train and Session Logging
    private func handleActionTap(_ action: String) {
        let actionLower = action.lowercased()

        // Navigate to Train section / Drill Library
        if actionLower.contains("train") || actionLower.contains("drill") {
            showDrillLibrary = true
        }
        // Navigate to Session Logging
        else if actionLower.contains("log") || actionLower.contains("session") || actionLower.contains("track") {
            showSessionLog = true
        }
        // Open drill library for improvement-focused actions
        else if actionLower.contains("improve") || actionLower.contains("recommended") {
            showDrillLibrary = true
        }
        // Default: open drill library as most common action
        else {
            showDrillLibrary = true
        }
    }

    private func sportSpecificWeakPointQuestion() -> String {
        switch sport {
        case .basketball:
            return "What do you think are your weak points — shooting, ball handling, finishing, defense, or conditioning?"
        case .tennis:
            return "What feels weakest right now — serve, backhand, footwork, consistency, or stamina?"
        case .soccer:
            return "Where do you struggle most — touch, passing, finishing, speed, or endurance?"
        case .football:
            return "What do you want to improve most — speed, route running, footwork, throwing, catching, or conditioning?"
        }
    }
}

// MARK: - Message Bubble

struct AICoachMessageBubble: View {
    let message: AICoachMessage
    let onActionTap: (String) -> Void

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: Spacing.xs) {
                // Message content
                Text(message.content)
                    .padding(Spacing.md)
                    .background(message.isUser ? Color.appPrimary : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.appTextSecondary)
                
                // Suggested actions (for AI messages) - CONNECTED TO TRAIN
                if !message.isUser && !message.suggestedActions.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(message.suggestedActions, id: \.self) { action in
                            ActionChip(text: action) {
                                onActionTap(action)
                            }
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
            }
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
}

// MARK: - Loading Bubble

struct LoadingBubble: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.2 : 1.0)
                        .opacity(animationPhase == index ? 1.0 : 0.5)
                }
            }
            .padding(Spacing.md)
            .background(Color(.systemGray5))
            .cornerRadius(16)
            
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Proactive Checkin Bubble

struct ProactiveCheckinBubble: View {
    let message: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.appAccent)
                    Text("Coach")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.appTextSecondary)
                }
                
                Text(message)
                    .foregroundColor(.primary)
            }
            .padding(Spacing.md)
            .background(
                LinearGradient(
                    colors: [Color.appAccent.opacity(0.1), Color.appPrimary.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
            )
            
            Spacer()
        }
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.appPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.appPrimary.opacity(0.1))
                .cornerRadius(20)
        }
    }
}

// MARK: - Action Chip

struct ActionChip: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                Text(text)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                LinearGradient(
                    colors: [Color.appAccent.opacity(0.15), Color.appPrimary.opacity(0.15)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.appAccent)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Message Model

struct AICoachMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    var suggestedActions: [String]
    var tone: String
    
    init(content: String, isUser: Bool, suggestedActions: [String] = [], tone: String = "supportive") {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.suggestedActions = suggestedActions
        self.tone = tone
    }
}

// MARK: - View Model

@MainActor
class AICoachChatViewModel: ObservableObject {
    @Published var messages: [AICoachMessage] = []
    @Published var isLoading = false
    @Published var proactiveCheckin: String?
    
    private let sport: Sport
    private let storageKey: String
    private let contextStorageKey: String
    private let storeManager = StoreManager.shared
    
    // Conversation context
    private var userWeakPoints: [String] = []
    private var userGoals: [String] = []
    private var availableTime: String?
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 2
    
    init(sport: Sport) {
        self.sport = sport
        self.storageKey = "ai_coach_messages_\(sport.rawValue)"
        self.contextStorageKey = "ai_coach_context_\(sport.rawValue)"
        loadMessages()
        loadContext()
    }
    
    func sendMessage(_ content: String) async {
        // SAFETY CHECK: Prevent API calls from non-Premium users
        // Should never reach here due to UI gates, but guard against direct navigation or deep links
        guard storeManager.isPremium else {
            print("⚠️ AI Coach: Attempted message send without Premium subscription")
            return
        }
        
        // Add user message
        let userMessage = AICoachMessage(content: content, isUser: true)
        messages.append(userMessage)
        saveMessages()
        
        // Extract context from user message
        extractContext(from: content)
        
        // Show loading
        isLoading = true
        
        do {
            // Call AI Coach API
            let apiClient = APIClient.shared
            let response = try await apiClient.sendCoachMessage(sport: sport, message: content)
            
            // Add AI response
            let aiMessage = AICoachMessage(
                content: response.response,
                isUser: false,
                suggestedActions: response.suggestedActions,
                tone: response.tone
            )
            
            messages.append(aiMessage)
            saveMessages()
            
            // Reset failure counter on success
            consecutiveFailures = 0
            
        } catch {
            print("[AI Coach] Error: \(error)")

            // PRIORITY FIX 3: Stop failure loops - provide useful fallback immediately
            consecutiveFailures += 1

            // Don't make user wait through generic failures - provide value now
            if consecutiveFailures >= maxConsecutiveFailures {
                // Multiple failures - clear message and strong fallback
                let fallback = AICoachMessage(
                    content: "I'm offline for the moment, but I've saved your context and can still help! Here's what I recommend based on what we've discussed:",
                    isUser: false
                )
                messages.append(fallback)

                // Immediately follow with useful structured fallback
                let structuredFallback = generateContextualFallback(userMessage: content)
                messages.append(structuredFallback)
                saveMessages()

                // Reset counter - don't get stuck in failure state
                consecutiveFailures = 0
            } else {
                // First failure - still provide immediate value instead of empty promise
                let fallbackResponse = generateContextualFallback(userMessage: content)
                messages.append(fallbackResponse)
                saveMessages()
            }
        }
        
        isLoading = false
    }
    
    func loadProactiveCheckin() async {
        guard messages.isEmpty else { return }  // Only show if no conversation yet
        
        do {
            let apiClient = APIClient.shared
            let response = try await apiClient.getProactiveCheckin(sport: sport)
            
            if response.hasMessage, let message = response.message {
                proactiveCheckin = message
            } else {
                // Fallback to coach-led question if no proactive message
                proactiveCheckin = fallbackCoachQuestion()
            }
        } catch {
            print("[AI Coach] Checkin error: \(error)")
            // Still provide a coach-led question even on error
            proactiveCheckin = fallbackCoachQuestion()
        }
    }
    
    private func fallbackCoachQuestion() -> String {
        let questions = [
            "What sport are you focused on training today?",
            "How's your body feeling after your last session?",
            "What's your biggest training goal right now?",
            "Are you preparing for a match, general improvement, or recovery?",
            "How much time do you have to train today?"
        ]
        return questions.randomElement() ?? questions[0]
    }
    
    func clearConversation() {
        messages = []
        proactiveCheckin = nil
        userWeakPoints = []
        userGoals = []
        availableTime = nil
        consecutiveFailures = 0
        saveMessages()
        saveContext()
        
        Task {
            // Call API to clear backend history
            try? await APIClient.shared.clearCoachConversation(sport: sport)
        }
    }
    
    // MARK: - Context Management
    
    private func extractContext(from message: String) {
        let lowercased = message.lowercased()
        
        // Extract weak points
        if lowercased.contains("weak") || lowercased.contains("struggle") || lowercased.contains("improve") {
            // Store user's mentioned weak areas
            if !userWeakPoints.contains(where: { message.contains($0) }) {
                userWeakPoints.append(message)
                saveContext()
            }
        }
        
        // Extract goals
        if lowercased.contains("goal") || lowercased.contains("want to") || lowercased.contains("trying to") {
            if !userGoals.contains(where: { message.contains($0) }) {
                userGoals.append(message)
                saveContext()
            }
        }
        
        // Extract time availability
        if lowercased.contains("minute") || lowercased.contains("hour") {
            availableTime = message
            saveContext()
        }
    }
    
    private func generateContextualFallback(userMessage: String) -> AICoachMessage {
        // Determine what the user is asking for
        let lowercased = userMessage.lowercased()
        
        var fallbackContent = ""
        var suggestedActions: [String] = []
        
        if lowercased.contains("workout") || lowercased.contains("drill") || lowercased.contains("train") {
            // User wants training recommendations
            fallbackContent = generateTrainingFallback()
            suggestedActions = ["View Train Section", "Start Quick Workout"]
        } else if lowercased.contains("weak") || lowercased.contains("improve") {
            // User wants improvement advice
            fallbackContent = generateImprovementFallback()
            suggestedActions = ["See Recommended Drills", "Track Progress"]
        } else if lowercased.contains("recovery") || lowercased.contains("rest") || lowercased.contains("tired") {
            // User asking about recovery
            fallbackContent = "While I reconnect, here's what I can suggest: Based on typical recovery patterns, consider taking a light training day or active recovery session. Check your wearable data if synced for personalized insights."
            suggestedActions = ["View Recovery Data", "Light Workout Options"]
        } else {
            // General fallback
            fallbackContent = "While I work on reconnecting, let me point you to some resources. Check out the Train section for sport-specific drills, or browse the drill library for skill development."
            suggestedActions = ["Browse Drills", "View Training Plans"]
        }
        
        return AICoachMessage(
            content: fallbackContent,
            isUser: false,
            suggestedActions: suggestedActions,
            tone: "supportive"
        )
    }
    
    private func generateTrainingFallback() -> String {
        // Generate sport-specific workout recommendation
        let drillSuggestions = getSportSpecificDrills()
        
        if let time = availableTime {
            return "While I reconnect, here's a quick \(sport.rawValue) workout based on your \(time):\n\n\(drillSuggestions.prefix(3).joined(separator: "\n"))\n\nYou can find more drills in the Train section with detailed instructions."
        } else {
            return "While I reconnect, here are some effective \(sport.rawValue) drills to work on:\n\n\(drillSuggestions.prefix(3).joined(separator: "\n"))\n\nCheck the Train section for full workout programs and more drills."
        }
    }
    
    private func generateImprovementFallback() -> String {
        if !userWeakPoints.isEmpty {
            return "Based on what you've mentioned, focus on drills that target your specific areas. The Train section has skill-specific drills you can filter by category. Start with fundamentals and gradually increase difficulty."
        } else {
            return "To improve in \(sport.rawValue), I recommend working on fundamental skills first. Visit the Train section to find drills organized by skill level and focus area. Track your progress over time to see improvement."
        }
    }
    
    private func getSportSpecificDrills() -> [String] {
        switch sport {
        case .basketball:
            return [
                "• Ball Handling: 15 min (stationary dribbling, crossovers, between legs)",
                "• Shooting: 20 min (form shooting, spot-up threes, free throws)",
                "• Conditioning: 10 min (suicide runs, defensive slides)"
            ]
        case .tennis:
            return [
                "• Groundstrokes: 20 min (forehand/backhand rallies, cross-court)",
                "• Serve Practice: 15 min (toss consistency, power serves)",
                "• Footwork: 10 min (split-step drills, lateral movement)"
            ]
        case .soccer:
            return [
                "• Ball Control: 15 min (juggling, first touch, close control)",
                "• Passing: 20 min (short passes, through balls, crossing)",
                "• Conditioning: 15 min (interval sprints, agility ladder)"
            ]
        case .football:
            return [
                "• Route Running: 20 min (crisp cuts, timing patterns)",
                "• Catching: 15 min (hands drills, one-handed grabs)",
                "• Conditioning: 15 min (40-yard sprints, cone drills)"
            ]
        }
    }
    
    // MARK: - Persistence
    
    private func saveMessages() {
        if let encoded = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
    
    private func loadMessages() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AICoachMessage].self, from: data) {
            messages = decoded
        }
    }
    
    private func saveContext() {
        let context: [String: Any] = [
            "weakPoints": userWeakPoints,
            "goals": userGoals,
            "availableTime": availableTime as Any
        ]
        if let encoded = try? JSONSerialization.data(withJSONObject: context) {
            UserDefaults.standard.set(encoded, forKey: contextStorageKey)
        }
    }
    
    private func loadContext() {
        guard let data = UserDefaults.standard.data(forKey: contextStorageKey),
              let context = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        
        if let weakPoints = context["weakPoints"] as? [String] {
            userWeakPoints = weakPoints
        }
        if let goals = context["goals"] as? [String] {
            userGoals = goals
        }
        if let time = context["availableTime"] as? String {
            availableTime = time
        }
    }
}

#Preview {
    NavigationStack {
        AICoachChatView(sport: .basketball)
    }
}
