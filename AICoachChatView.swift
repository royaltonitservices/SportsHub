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
                            AICoachMessageBubble(
                                message: message,
                                onActionTap: { action in handleActionTap(action) },
                                onFeedback: message.isUser ? nil : { helpful in
                                    let focus = viewModel.sessionInsight?.primaryFocus
                                    CoachFeedbackStore.record(CoachFeedbackEntry(
                                        messageId: message.id.uuidString,
                                        helpful: helpful,
                                        sport: sport,
                                        focusArea: focus
                                    ))
                                    CoachTelemetry.recordFeedback(sport: sport, helpful: helpful, focusArea: focus)
                                }
                            )
                            .id(message.id)
                        }
                        
                        // Loading indicator
                        if viewModel.isLoading {
                            LoadingBubble()
                        }
                        
                        // Error state with retry
                        if let errorState = viewModel.errorState {
                            ErrorRetryBubble(errorState: errorState) {
                                Task {
                                    await viewModel.retryLastMessage()
                                }
                            }
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
            
            // Session insight banner — shows current focus, progression stage, and why today
            if let insight = viewModel.sessionInsight {
                sessionInsightBanner(insight)
            }

            // Input bar
            inputBar
        }
        .navigationTitle("AI Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("AI Coach")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    Text(StorageStrategy.hybrid.disclosureLabel)
                        .font(.caption2)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
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
            // Load both in parallel — survey and proactive check-in are independent
            async let survey: () = viewModel.loadSurvey()
            async let checkin: () = viewModel.loadProactiveCheckin()
            _ = await (survey, checkin)
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
    
    // MARK: - Session Insight Banner

    /// Slim banner above the input bar surfacing the AI's current reasoning:
    /// what to focus on, which progression stage the athlete is in, and why.
    private func sessionInsightBanner(_ insight: CoachSessionInsight) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "brain.head.profile")
                .font(.caption)
                .foregroundStyle(Color.appPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Today: \(insight.primaryFocus.prefix(1).uppercased() + insight.primaryFocus.dropFirst())")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)
                Text(insight.whyToday)
                    .font(.caption2)
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(insight.stageLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Color.appPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.appPrimary.opacity(0.12), in: Capsule())

            Button(action: { viewModel.dismissSessionInsight() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 8)
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.appTextSecondary.opacity(0.2)),
            alignment: .top
        )
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
    /// Called with true (helpful) or false (not helpful) when the athlete rates a response.
    /// Nil for user messages — feedback buttons are only shown on AI responses.
    var onFeedback: ((Bool) -> Void)? = nil

    @State private var feedbackGiven: Bool? = nil

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

                // Feedback row — thumbs up / down for AI messages only
                if !message.isUser, let onFeedback = onFeedback {
                    HStack(spacing: Spacing.sm) {
                        Button {
                            guard feedbackGiven == nil else { return }
                            feedbackGiven = true
                            onFeedback(true)
                        } label: {
                            Image(systemName: feedbackGiven == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.caption)
                                .foregroundColor(feedbackGiven == true ? .appPrimary : .appTextSecondary)
                        }
                        Button {
                            guard feedbackGiven == nil else { return }
                            feedbackGiven = false
                            onFeedback(false)
                        } label: {
                            Image(systemName: feedbackGiven == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                .font(.caption)
                                .foregroundColor(feedbackGiven == false ? .appError : .appTextSecondary)
                        }
                        if let given = feedbackGiven {
                            Text(given ? "Thanks!" : "Got it")
                                .font(.caption2)
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                    .padding(.top, 2)
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

// MARK: - Error Retry Bubble

struct ErrorRetryBubble: View {
    let errorState: AICoachErrorState
    let onRetry: () -> Void
    
    private var canRetry: Bool {
        switch errorState {
        case .noConnection, .backendDown, .timeout, .serverError:
            return true
        case .authRequired, .premiumRequired:
            return false
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if canRetry {
                    Button(action: onRetry) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                            Text("Retry")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.appPrimary)
                        .cornerRadius(8)
                    }
                }
            }
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

// MARK: - AI Coach Error Types

enum AICoachErrorState {
    case noConnection
    case backendDown
    case authRequired
    case premiumRequired
    case timeout
    case serverError
}

enum AICoachErrorKind {
    case noConnection
    case backendDown
    case endpointNotFound
    case authFailure
    case premiumRequired
    case timeout
    case serverError(String)
    case unknown(String)
    
    var isRetryable: Bool {
        switch self {
        case .timeout, .backendDown, .serverError:
            return true
        case .noConnection, .endpointNotFound, .authFailure, .premiumRequired, .unknown:
            return false
        }
    }
    
    /// Errors where the infrastructure is the problem, not the user's request.
    /// These should fall back to local coaching rather than showing a dead-end error.
    var isInfrastructureError: Bool {
        switch self {
        case .backendDown, .endpointNotFound, .noConnection:
            return true
        case .timeout, .serverError, .authFailure, .premiumRequired, .unknown:
            return false
        }
    }
    
    var logDescription: String {
        switch self {
        case .noConnection: return "No internet connection"
        case .backendDown: return "Backend unreachable"
        case .endpointNotFound: return "Endpoint not found (404)"
        case .authFailure: return "Auth failure (401)"
        case .premiumRequired: return "Premium required (403)"
        case .timeout: return "Request timeout"
        case .serverError(let msg): return "Server error: \(msg)"
        case .unknown(let msg): return "Unknown: \(msg)"
        }
    }
}

// MARK: - Readiness Engine Types

/// Three-tier coaching readiness derived from biometrics, sleep, and self-report.
/// Used to adapt session intensity/volume AFTER the coaching plan is built.
enum CoachReadinessLevel {
    case high     // Score ≥ 70 — full intensity, progressive overload, include power/speed work
    case medium   // Score 40–69 — productive session, reduce volume ~20%, maintain technique
    case low      // Score < 40 — recovery mode: technique-only, protect the body

    var label: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Moderate"
        case .low:    return "Low"
        }
    }
}

/// Composite readiness snapshot computed from wearable + self-reported signals.
/// `hasWearableData` is true when at least one biometric is present.
struct CoachReadinessProfile {
    let level: CoachReadinessLevel
    let score: Int            // 0–100 composite
    let hrv: Double?          // ms — higher = better (nil = no data)
    let restingHR: Double?    // bpm — lower = better
    let sleepHours: Double?   // hours
    let steps: Int?           // proxy for accumulated daily strain
    let selfReported: String? // e.g. "good" / "moderate" / "poor" / "exhausted"
    let hasWearableData: Bool
    let recoveryNote: String  // human-readable explanation of the classification
}

// MARK: - Pre-Pipeline Intent Gate (Phase 1)

// MARK: - Phase 3: Refinement & Follow-Up Continuity

/// A constraint change the user wants applied to the most recent AI response.
/// Used by `RefinementClassifier` and the Phase 3 gate in `sendMessage()`.
enum RefinementModifier {
    case shorterDuration(minutes: Int?)  // "20 minutes" / "shorter" — nil = reduce by 15 min
    case longerDuration                   // "longer" / "more time" — adds 15 min
    case harder                           // "harder" / "more intense"
    case easier                           // "easier" / "scale it down"
    case noEquipment                      // "no equipment" / "bodyweight" / "at home"
    case recoveryMode                     // "recovery" / "low intensity" / "adjust for recovery"
}

/// Classified intent for a follow-up message evaluated against the prior AI response.
/// Returned by `RefinementClassifier.classify()` and consumed by the Phase 3 gate.
enum RefinementIntent {
    case refine([RefinementModifier])    // Apply modifiers to prior output — no re-derivation
    case convertGuidanceToSession        // Prior .guidance topic → concrete .workoutPlan
    case conversationalCompletion        // User answered a .coachingConversational gathering question
    case freshRequest                    // New topic — exit refinement state, run full pipeline
}

/// Lightweight, deterministic classifier for follow-up / refinement messages.
///
/// Only runs when a prior AI response exists in the message thread.
/// Internal (not private) so it is unit-testable via @testable import.
///
/// Priority order (first match wins):
///   1. Fresh topic override  — "what about footwork?"
///   2. Guidance conversion   — "make that into a session" (only after .guidance)
///   3. Conversational answer — short specific reply (only after .coachingConversational)
///   4. Constraint modifiers  — time / intensity / equipment / recovery
///   5. Default               — .freshRequest (safe fallback)
struct RefinementClassifier {

    static func classify(
        message: String,
        hasPriorAIResponse: Bool,
        priorMode: AICoachChatViewModel.OutputMode?
    ) -> RefinementIntent {
        guard hasPriorAIResponse else { return .freshRequest }

        let low = message.lowercased().trimmingCharacters(in: .whitespaces)

        // ── STEP 1: Fresh topic override ──────────────────────────────────────────────
        // "what about X" / "how about X" explicitly redirects to a new topic.
        if low.hasPrefix("what about") || low.hasPrefix("how about") {
            return .freshRequest
        }

        // ── STEP 2: Guidance → session conversion ─────────────────────────────────────
        // Only valid immediately after a .guidance response.
        if priorMode == .guidance {
            let conversionPhrases = [
                "make that into a session", "turn that into", "build a session",
                "build me a session", "create a session", "make that a plan",
                "make it a session", "make it into a session", "turn it into",
                "yes — build", "yes, build", "ok, create", "okay, create",
                "okay, make", "ok, make", "make it a workout"
            ]
            if conversionPhrases.contains(where: { low.contains($0) }) {
                return .convertGuidanceToSession
            }
        }

        // ── STEP 3: CoachingConversational completion ──────────────────────────────────
        // After a gathering question, user answers with a short, specific reply.
        // Heuristic: ≤ 6 words, no modifier vocabulary, no explicit duration, not a question.
        // Explicit durations ("about 30 minutes") are modifier intent, not a topic answer.
        if priorMode == .coachingConversational {
            let wordCount = low.split(separator: " ").count
            let hasModVocab = hasAnyModifierVocabulary(low)
            let hasExplicitDuration = extractExplicitMinutes(from: low) != nil
            let isQuestion = low.hasPrefix("what") || low.hasPrefix("how") || low.hasSuffix("?")
            if wordCount <= 6 && !hasModVocab && !hasExplicitDuration && !isQuestion {
                return .conversationalCompletion
            }
        }

        // ── STEP 4: Constraint modifiers ──────────────────────────────────────────────
        var modifiers: [RefinementModifier] = []

        // Time — explicit duration beats relative shortening
        if let mins = extractExplicitMinutes(from: low) {
            modifiers.append(.shorterDuration(minutes: mins))
        } else if containsAny(low, ["make it shorter", "shorter version", "shorten",
                                     "less time", "cut it down", "too long",
                                     "brief version", "quicker version"]) {
            modifiers.append(.shorterDuration(minutes: nil))
        } else if containsAny(low, ["make it longer", "longer version", "more time",
                                     "extend it", "add more time"]) {
            modifiers.append(.longerDuration)
        }

        // Intensity — harder and easier are mutually exclusive; first match wins
        if containsAny(low, ["harder", "more intense", "more challenging",
                              "push me harder", "increase intensity",
                              "harder version", "make it harder", "step it up"]) {
            modifiers.append(.harder)
        } else if containsAny(low, ["easier", "scale it down", "less intense", "lighter",
                                     "tone it down", "make it easier", "too hard",
                                     "dial it back", "scaled down"]) {
            modifiers.append(.easier)
        }

        // Equipment — no-equipment request
        if containsAny(low, ["no equipment", "no gear", "at home", "bodyweight",
                              "equipment-free", "equipment free", "no weights",
                              "without equipment"]) {
            modifiers.append(.noEquipment)
        }

        // Recovery — low-intensity recovery request
        if containsAny(low, ["recovery", "active recovery", "recovery mode",
                              "adjust for recovery", "low intensity", "easy day",
                              "recovery session", "light session"]) {
            modifiers.append(.recoveryMode)
        }

        if !modifiers.isEmpty { return .refine(modifiers) }

        // ── STEP 5: Default — treat as fresh request ──────────────────────────────────
        return .freshRequest
    }

    // MARK: - Helpers (internal for testability)

    /// Extracts an explicit session duration (5–180 min) from the message, if present.
    static func extractExplicitMinutes(from low: String) -> Int? {
        let pattern = #"(\d{1,3})\s*(?:min(?:utes?)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(low.startIndex..., in: low)
        guard let match = regex.firstMatch(in: low, range: range),
              let r = Range(match.range(at: 1), in: low),
              let mins = Int(low[r]),
              (5...180).contains(mins) else { return nil }
        return mins
    }

    private static func hasAnyModifierVocabulary(_ low: String) -> Bool {
        let vocab = ["shorter", "longer", "harder", "easier", "no equipment", "bodyweight",
                     "recovery", "more intense", "less intense", "make it", "scale", "adjust",
                     "lighter", "at home", "low intensity", "shorten", "extend"]
        return vocab.contains(where: { low.contains($0) })
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: { text.contains($0) })
    }
}

// MARK: - Phase 5A: Direct Skill Detector

/// Detects whether the user's message contains an explicit, named sport-skill signal.
///
/// A "direct skill signal" is a concrete, sport-specific technical phrase that the user
/// is asking to work on right now — e.g. "I want to work on my crossover" or
/// "help me with my serve." When detected, survey-derived weak points must NOT steer
/// the coaching plan away from the stated focus (hard override, not a score boost).
///
/// This struct is the single source of truth for direct-skill phrase lists across the
/// codebase. `buildPromptContext()` calls it to decide whether to suppress survey data,
/// and `extractAllFocusAreas()` relies on the same phrase vocabulary for FocusArea tagging.
struct DirectSkillDetector {

    /// Returns true if `message` contains a direct skill phrase for the given sport.
    static func detect(from message: String, sport: Sport) -> Bool {
        let low = message.lowercased()
        return skillPhrases(for: sport).contains(where: { low.contains($0) })
    }

    /// The canonical sport-specific skill phrases.  Keep in sync with
    /// `extractAllFocusAreas()` in AICoachChatViewModel.
    static func skillPhrases(for sport: Sport) -> [String] {
        switch sport {
        case .basketball:
            return ["left hand", "weak hand", "off hand", "shooting", "free throw", "layup",
                    "crossover", "dribbling", "ball handling", "ball control",
                    "post move", "finishing", "passing", "footwork", "pivot"]
        case .football:
            return ["route running", "catching", "blocking", "footwork", "pass rush",
                    "release", "off the line", "coverage", "acceleration", "agility"]
        case .soccer:
            return ["first touch", "heading", "crossing", "finishing", "passing",
                    "dribbling", "shooting", "footwork", "defending"]
        case .tennis:
            return ["serve", "forehand", "backhand", "volley", "topspin", "drop shot",
                    "footwork", "return", "overhead", "net play"]
        }
    }
}

// MARK: - Phase 5C: Safety Interrupt Classifier

/// Detects mixed injury-plus-coaching-request messages where safety must win over
/// coaching content.
///
/// A "safety interrupt" fires when the user's message contains BOTH:
///   1. Injury/pain language (via `SafetyDetector.detectsInjury()`)
///   2. An explicit coaching-request signal (drill/workout/plan/build/give me/etc.)
///
/// Pure injury messages with no coaching request ("my knee hurts") are intentionally
/// NOT interrupted here — the downstream `SafetyConstraintClassifier` already handles
/// those gracefully.  The interrupt is for the specific pattern where the user tries
/// to bypass safety by bundling the injury with a coaching ask in a single message.
struct SafetyInterruptClassifier {

    /// Returns true when the message contains BOTH injury language AND a coaching request.
    static func isMixedInjuryCoachingRequest(_ message: String) -> Bool {
        guard SafetyDetector.detectsInjury(in: message) else { return false }
        let low = message.lowercased()
        let coachingSignals = [
            "build me", "give me a", "make me a", "create a", "design a",
            "give me drills", "give me a drill",
            "i want to train", "i need to train", "let's train",
            "workout", "drill session", "practice session",
            "can i still", "should i still", "is it ok to train",
            "can i train", "can i work out", "can i workout",
        ]
        return coachingSignals.contains(where: { low.contains($0) })
    }

    /// Safety-first response when injury + coaching request are mixed.
    static func safetyResponse(for keyword: String, sport: Sport) -> (text: String, actions: [String]) {
        let sportName = sport.rawValue.capitalized
        return (
            """
            I noticed you mentioned \"\(keyword)\" — before I build anything, that's the priority. \
            Training through pain can make things worse and extend your time away from \(sportName).

            What I'd recommend:
            • **Rest the affected area** for at least 24–48 hours
            • **If pain is sharp, persistent, or worsening** — see a healthcare professional before returning to training
            • If it's mild soreness, light active recovery (walking, gentle stretching, mobility work) is usually fine

            When you're feeling better, come back and I'll build you something smart that works around it. Your long-term development matters more than one session.
            """,
            ["I'll rest up", "What's active recovery?", "When can I train again?"]
        )
    }
}

// MARK: - Phase 5B: Coaching Ambiguity Classifier

/// Detects messages that are underspecified coaching intents — the user wants coaching
/// but has not provided any focus, duration, constraint, or context signal.
///
/// When detected (and no prior AI response exists in the session), the AI returns a
/// sport-specific clarifying question instead of fabricating a plan from thin air.
///
/// GATE CONDITIONS (all must be true):
///   • This classifier returns true
///   • No prior AI response in the session (hasPriorAI == false)
///   • No active refinement context (activeRefinementContext == nil)
///
/// Non-goals: This classifier must NOT fire for messages that contain any specific skill,
/// duration hint, intensity signal, or equipment constraint — those are handled by the
/// normal pipeline.
struct CoachingAmbiguityClassifier {

    /// Returns true if the message is a vague coaching intent with no specifying detail.
    static func isAmbiguous(_ message: String) -> Bool {
        let low = message.lowercased().trimmingCharacters(in: .whitespaces)

        // Hard-exclude: specific skill signals → let pipeline handle it
        let specificSignals = [
            "minute", "min", "hour",               // time hint
            "drill", "workout", "session", "plan",  // explicit plan request
            "harder", "easier", "recover",          // intensity/recovery hint
            "no equipment", "home",                 // equipment hint
        ]
        if specificSignals.contains(where: { low.contains($0) }) { return false }

        // Ambiguous coaching triggers — only these exact underspecified phrases
        let ambiguousPatterns = [
            "something for today",
            "what now",
            "what should i do",
            "not sure what to do",
            "not sure where to start",
            "just give me something",
            "give me anything",
            "surprise me",
            "whatever you think",
            "what do you recommend",
            "what do you suggest",
            "i don't know where to start",
            "i don't know what to do",
            "i need help",
            "any ideas",
            "what can i do",
        ]
        return ambiguousPatterns.contains(where: { low.contains($0) })
    }

    /// Returns a sport-specific clarifying question when ambiguity is detected.
    static func clarifyingQuestion(for sport: Sport) -> (text: String, actions: [String]) {
        switch sport {
        case .basketball:
            return (
                "To make this count — are you looking to work on a specific skill (shooting, ball handling, footwork), build athleticism, or get a solid all-around session?",
                ["Skill-specific", "Athleticism", "All-around session"]
            )
        case .football:
            return (
                "Are you working on a position skill (route running, blocking, coverage), improving athleticism, or need a general conditioning session?",
                ["Position skill", "Athleticism", "Conditioning"]
            )
        case .soccer:
            return (
                "Are you focusing on a technical skill (first touch, dribbling, finishing), fitness, or want a complete well-rounded session?",
                ["Technical skill", "Fitness", "Complete session"]
            )
        case .tennis:
            return (
                "Are you working on a specific shot (serve, forehand, backhand), movement and footwork, or looking for a solid general session?",
                ["Specific shot", "Movement & footwork", "General session"]
            )
        }
    }
}

// MARK: - Phase 4: App Help

/// Detects whether the user is asking how to USE the SportsHub app (navigation, features, settings).
///
/// CRITICAL DISTINCTION:
///   - "how do I log a session?" → app-help  (navigating the app)
///   - "how do I do a euro step?" → coaching  (sport skill instruction)
///
/// Internal (not private) so it is unit-testable via @testable import.
struct AppHelpClassifier {

    /// Returns true if the message is asking about app navigation, features, or settings.
    static func isAppHelp(_ message: String) -> Bool {
        let low = message.lowercased().trimmingCharacters(in: .whitespaces)

        // Hard-exclude sport-skill vocabulary — these are coaching questions, not app-help.
        // Checked first so sport vocab always wins over app-help vocab.
        let sportSkillVocab = [
            "euro step", "crossover", "step back", "pull up", "lay up", "dunk",
            "free throw", "three point", "3 point", "free kick", "penalty kick",
            "serve", "volley", "backhand", "forehand", "spiral", "route",
            "dribbling", "shooting", "passing", "defending", "blocking",
            "jump shot", "hook shot", "post up", "screen", "pick and roll",
            "offside trap", "formation", "press break", "zone defense",
            "how do i improve", "how do i get better", "how do i train",
            "help me with", "work on my", "improve my", "practice my",
            "teach me", "show me how to", "explain how to"
        ]
        if sportSkillVocab.contains(where: { low.contains($0) }) { return false }

        // App-help keyword patterns
        let appHelpPatterns = [
            // Session logging
            "log a session", "log my session", "log a workout", "log my workout",
            "how do i log", "where do i log",
            "save a session", "save my session", "save a workout", "save my workout",
            "record a session", "track a session",
            // Navigation
            "where is the train", "where is train", "where is the play",
            "where is the home", "where is the profile", "where is the clips",
            "where is the post", "which tab", "find the tab", "find the train",
            "navigate to", "go to train", "go to play", "where do i go",
            // AI Coach
            "how does ai coach work", "what is ai coach", "how do i use ai coach",
            "how does the ai coach", "what can the ai coach", "what does ai coach",
            "where is the ai coach", "find the ai coach", "access the ai coach",
            // Readiness
            "how do i check my readiness", "what is readiness", "daily readiness",
            "how does readiness work", "what is the readiness",
            // Profile / settings / training profile
            "how do i edit my profile", "how do i change my name",
            "how do i change my username", "how do i update my profile",
            "how do i see my stats", "where are my stats",
            "where is my profile", "find my profile",
            "where do i edit", "where can i edit",
            "edit my training", "training profile",
            "training goals", "set my goals", "my training goals",
            // Matchmaking / opponents
            "how do i find opponents", "how do i find a match",
            "how do i find someone to play", "how does matchmaking work",
            "how do i challenge someone", "how do i create a challenge",
            "how do i accept a challenge", "where do i accept",
            // Friends
            "how do i add friends", "how do i send a friend", "how does friends work",
            "where are my friends", "how do i find friends",
            // Disputes
            "how do i file a dispute", "how do i report a dispute",
            "how does dispute work", "what is a dispute",
            // Premium / subscription
            "what is premium", "how does premium work", "what do i get with premium",
            "how do i upgrade", "how do i subscribe", "premium features",
            "what are premium features",
            // Smartwatch
            "how do i connect my watch", "how does smartwatch work",
            "how do i sync my watch", "how do i connect my apple watch",
            "where is the smartwatch", "smartwatch sync",
            // Drill library
            "what is the drill library", "where is the drill library",
            "how do i find drills", "how do i access drills",
            // Tournaments
            "how do i join a tournament", "how do i create a tournament",
            "where are tournaments", "how does tournament work",
            // Posts / clips
            "how do i post a clip", "how do i upload a clip", "how do i post",
            "how do i share", "where are clips",
            // General app help
            "how does the app work", "how do i use the app",
            "how do i get started", "where do i start",
            "what features", "what can i do in the app", "what does the app"
        ]

        return appHelpPatterns.contains(where: { low.contains($0) })
    }

    /// Returns a factual, concise answer for the app-help query.
    /// Answers are grouped by feature area for easy future maintenance.
    static func answer(for message: String, sport: Sport) -> String {
        let low = message.lowercased()

        // ── Session logging ──────────────────────────────────────────────────────────
        if containsAny(low, ["log", "save", "record", "track"]) &&
           containsAny(low, ["session", "workout"]) {
            return "To log a training session: go to the **Train** tab, choose your drills, then tap **Finish Session** at the bottom. Your session is saved locally and analyzed by the AI Coach."
        }

        // ── Navigation ───────────────────────────────────────────────────────────────
        if containsAny(low, ["train tab", "where is train", "find train", "go to train"]) {
            return "The **Train** tab is the second tab from the left in the bottom navigation bar. Tap it to access drills, the AI Coach, and session logging."
        }
        if containsAny(low, ["play tab", "where is play", "find play", "go to play"]) {
            return "The **Play** tab is the first tab. Tap it to find opponents, create challenges, and view the leaderboard."
        }
        if containsAny(low, ["which tab", "where do i go", "navigate to", "find the tab",
                               "how does the app work", "how do i use the app", "where do i start"]) {
            return "SportsHub has 6 tabs at the bottom: **Play** (matchmaking), **Train** (drills & AI Coach), **Posts** (feed), **Clips** (videos), **Profile** (stats & settings), and **Home** (dashboard)."
        }

        // ── AI Coach ─────────────────────────────────────────────────────────────────
        if containsAny(low, ["ai coach", "coach"]) {
            return "The **AI Coach** is in the **Train** tab. Tap the AI Coach card to start a conversation. You can ask for workout plans, drill recommendations, explanations of techniques, or a weekly schedule. It's a Premium feature — free users can see it but need to upgrade to use it."
        }

        // ── Readiness ────────────────────────────────────────────────────────────────
        if containsAny(low, ["readiness", "daily readiness"]) {
            return "**Daily Readiness** is in the **Train** tab under the smartwatch section. It shows your recovery status based on wearable data (heart rate, sleep, HRV) and recommends whether to train hard, light, or rest. Requires a connected wearable."
        }

        // ── Profile / stats / training profile ───────────────────────────────────────
        if containsAny(low, ["edit my profile", "change my name",
                               "change my username", "update my profile"]) {
            return "To edit your profile: go to the **Profile** tab, tap the **Edit** button in the top right. You can update your display name, username, and bio there."
        }
        if containsAny(low, ["training profile", "edit my training",
                               "training goals", "set my goals", "my training goals"]) {
            return "To edit your training profile (goals, skill levels, weak areas): go to the **Profile** tab → **Settings** → **Training Profile**. This updates the AI Coach's recommendations for you."
        }
        if containsAny(low, ["stats", "my stats"]) {
            return "Your stats (wins, games played, rating) are on the **Profile** tab. Tap your sport selector to switch between sport stats."
        }

        // ── Matchmaking ──────────────────────────────────────────────────────────────
        if containsAny(low, ["find opponent", "find a match",
                               "find someone to play", "matchmaking"]) {
            return "To find opponents: go to the **Play** tab and tap **Find Opponents**. You can filter by sport, skill level, and distance. The system matches you with nearby players at a similar rating."
        }
        if containsAny(low, ["challenge", "create a challenge", "accept a challenge"]) {
            return "Challenges are in the **Play** tab. Tap **Create Challenge** to send one to an opponent, or check **Pending Challenges** to accept/decline incoming challenges."
        }

        // ── Friends ──────────────────────────────────────────────────────────────────
        if containsAny(low, ["friend", "add friend"]) {
            return "To add friends: go to the **Profile** tab and tap **Friends**, or search by username in the top search bar on the **Home** tab. You can send a friend request and chat once they accept."
        }

        // ── Disputes ─────────────────────────────────────────────────────────────────
        if containsAny(low, ["dispute"]) {
            return "To file a dispute: go to the **Play** tab, find the completed challenge, and tap **Dispute Result**. You can upload evidence (photos/videos). Disputes are reviewed by admins within 48 hours."
        }

        // ── Premium ───────────────────────────────────────────────────────────────────
        if containsAny(low, ["premium", "upgrade", "subscribe"]) {
            return "**Premium** unlocks: AI Coach conversations, smartwatch sync, weekly personalized drills, and tournament creation. Plans: $8.99/month or $100/year. Tap the **Premium** banner in the **Train** tab to upgrade."
        }

        // ── Smartwatch ────────────────────────────────────────────────────────────────
        if containsAny(low, ["watch", "smartwatch", "apple watch", "sync"]) {
            return "To connect your smartwatch: go to **Train** tab → **Smartwatch Sync**. SportsHub currently supports Apple Watch (HealthKit). Tap **Connect Device** and grant HealthKit permissions. This is a Premium feature."
        }

        // ── Drills ────────────────────────────────────────────────────────────────────
        if containsAny(low, ["drill library", "find drills", "access drills"]) {
            return "The **Drill Library** is in the **Train** tab. It contains sport-specific drills organized by skill area. Tap any drill to see instructions, sets, reps, and coaching cues."
        }

        // ── Tournaments ───────────────────────────────────────────────────────────────
        if containsAny(low, ["tournament"]) {
            return "Tournaments are in the **Play** tab → **Tournaments** section. You can browse and join tournaments for free. Creating a tournament requires a Premium subscription."
        }

        // ── Clips / posts ─────────────────────────────────────────────────────────────
        if containsAny(low, ["clip", "upload a clip", "post a clip"]) {
            return "To upload a clip: go to the **Clips** tab and tap the **+** button. You can select a video from your library. Clips are visible to all users in the feed."
        }
        if containsAny(low, ["post", "share"]) {
            return "To create a post: go to the **Posts** tab and tap **+**. Posts are sport-filtered and visible to all users."
        }

        // ── General fallback ─────────────────────────────────────────────────────────
        return "SportsHub has 6 main sections: **Play** (matchmaking & challenges), **Train** (drills & AI Coach), **Posts** (feed), **Clips** (videos), **Profile** (stats & settings), and **Home** (dashboard). What specific feature would you like help with?"
    }

    static func suggestedActions(for message: String, sport: Sport) -> [String] {
        let low = message.lowercased()
        if containsAny(low, ["log", "session", "workout"]) {
            return ["Go to Train tab", "Ask for a workout plan", "See my recent sessions"]
        }
        if containsAny(low, ["ai coach", "coach"]) {
            return ["Ask me for a workout plan", "Upgrade to Premium", "See what I can help with"]
        }
        if containsAny(low, ["premium", "upgrade"]) {
            return ["Tell me about premium features", "Get a workout plan", "Upgrade now"]
        }
        if containsAny(low, ["opponent", "match", "challenge", "play"]) {
            return ["Go to Play tab", "Tell me about matchmaking", "Create a workout instead"]
        }
        return ["Ask me for a workout plan", "What can you help me with?", "Go to Train tab"]
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: { text.contains($0) })
    }
}

// MARK: - Phase 4: Analytics & Reporting

/// Detects whether the user is asking about their own training statistics, patterns, or progress.
///
/// CRITICAL DISTINCTION:
///   - "how am I doing?" → analytics  (wants a data summary)
///   - "how am I doing with my shooting?" → coaching  (has skill vocab → falls through to pipeline)
///   - "am I improving?" → analytics
///   - "how do I improve?" → coaching  (action request, not a data request)
///
/// Conservative by design — only fires when the message is clearly a data/progress query.
/// Internal (not private) so it is unit-testable via @testable import.
struct AnalyticsClassifier {

    static func isAnalytics(_ message: String) -> Bool {
        let low = message.lowercased().trimmingCharacters(in: .whitespaces)

        // Hard-exclude coaching-action intent phrases — those are training requests, not queries.
        let coachingIntentPhrases = [
            "how do i improve", "how do i get better", "help me improve",
            "help me with", "how should i train", "what should i work on",
            "how do i work on", "what drills", "give me a workout",
            "how do i do", "how do i practice", "how do i develop"
        ]
        if coachingIntentPhrases.contains(where: { low.contains($0) }) { return false }

        // If the message has sport-skill vocabulary, only route to analytics for the narrow set
        // of strong progress-tracking phrases — everything else falls through to coaching.
        // e.g. "how am I doing with my shooting?" → coaching, not analytics
        let sportSkillVocab = [
            "shooting", "dribbling", "passing", "defending", "footwork",
            "conditioning", "speed", "agility", "strength", "endurance",
            "crossover", "euro step", "jump shot", "serve", "volley",
            "free throw", "three point", "post up", "pick and roll",
            "formation", "penalty kick", "free kick"
        ]
        let hasSkillVocab = sportSkillVocab.contains(where: { low.contains($0) })
        if hasSkillVocab {
            let strongProgressPhrases = ["my progress in", "progress with", "how much have i improved"]
            if !strongProgressPhrases.contains(where: { low.contains($0) }) { return false }
        }

        // Analytics detection patterns
        let analyticsPatterns = [
            // General progress queries
            "how am i doing", "how have i been doing",
            "am i improving", "am i getting better", "am i making progress",
            "have i improved", "have i been improving", "have i gotten better",
            "show me my progress", "what's my progress", "check my progress",
            // Streaks / consistency
            "what's my streak", "do i have a streak", "how consistent am i",
            "how often have i", "how many times have i",
            // Session counts
            "how many sessions", "how many workouts", "how much have i trained",
            "how many times have i trained", "sessions this week", "workouts this week",
            // Weakness patterns
            "what are my weak areas", "what do i keep struggling with",
            "what have i been struggling with", "what are my patterns",
            "what keeps coming up", "what am i bad at", "what are my weaknesses",
            // Recent training
            "recent training", "what have i been working on",
            "what did i train", "what have i trained",
            "training summary", "my training summary",
            "my recent sessions", "show my sessions",
            // Effort / intensity
            "how hard have i been training", "what's my effort",
            "my training intensity", "how intense have i been"
        ]

        return analyticsPatterns.contains(where: { low.contains($0) })
    }
}

// MARK: - PrePipeline Intent

/// Top-level classification of an incoming message before any coaching pipeline logic runs.
/// Determines whether the message should be handled by the coaching pipeline
/// or intercepted by the pre-pipeline gate and returned immediately.
///
/// Only `.coachingLikely` falls through to `extractContext()` and the pipeline.
/// All other buckets are handled directly in `sendMessage()` with a lightweight response.
enum PrePipelineIntent {
    case greetingSocial
    case arithmeticFactual(answer: String)
    case offTopicRedirect
    case unclear
    case coachingLikely

    /// Used by `CoachTelemetry.recordPrePipelineIntent()` to track real-world input distribution.
    var telemetryLabel: String {
        switch self {
        case .greetingSocial:    return "greeting_social"
        case .arithmeticFactual: return "arithmetic_factual"
        case .offTopicRedirect:  return "off_topic_redirect"
        case .unclear:           return "unclear"
        case .coachingLikely:    return "coaching_likely"
        }
    }
}

/// Synchronous, keyword/pattern-based pre-pipeline classifier.
///
/// Priority order (first match wins):
///   1. Greeting / Social   — positive social signal, no coaching action verbs
///   2. Arithmetic          — narrow: deterministic numeric expression, no sport vocabulary
///   3. Coaching-Likely     — sport/skill/training vocabulary or coaching intent present
///   4. Off-Topic Factual   — clearly non-sport question (narrow detection to avoid false positives)
///   5. Unclear             — default when no signal is strong enough
///
/// Internal (not private) so the classifier is unit-testable via @testable import SportsHub.
/// Zero async, zero GPT, zero backend — this must complete in sub-millisecond time.
struct PrePipelineClassifier {

    static func classify(_ message: String, sport: Sport) -> PrePipelineIntent {
        let low = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !low.isEmpty else { return .unclear }

        if isGreetingOrSocial(low)              { return .greetingSocial }
        if let answer = evaluateArithmetic(low) { return .arithmeticFactual(answer: answer) }
        if isCoachingLikely(low)                { return .coachingLikely }
        if isOffTopicFactual(low)               { return .offTopicRedirect }
        return .unclear
    }

    // MARK: — Bucket 1: Greeting / Social

    /// Returns true when the message is clearly a social or greeting expression
    /// with no coaching action verbs that would override the classification.
    ///
    /// Rule: coaching action verbs always win over social signal.
    /// If a message starts with "ok" but contains "build me a session", it is coaching-likely,
    /// not social. Overall message intent matters more than any single word.
    static func isGreetingOrSocial(_ low: String) -> Bool {
        // Hard override: coaching action verbs cancel any social signal present
        let coachingActionOverrides = [
            "build me", "build a", "give me a", "give me the",
            "make me a", "make me the", "create a", "create me",
            "show me a", "show me the",
            "help me with my", "help me improve", "help me train",
            "improve my", "work on my", "train my",
            "i want to improve", "i want to get better", "i want to work on",
            "i want to train", "i need to train", "i need a session",
            "let's work on", "let's train", "let's do a",
            "what should i work", "what should i focus", "what do i need to work"
        ]
        if coachingActionOverrides.contains(where: { low.contains($0) }) { return false }

        let words = low.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Standalone greeting words (message is 1–3 words, starts with greeting)
        let greetingPrefixes = [
            "hi", "hey", "hello", "howdy", "yo ", "sup",
            "good morning", "good afternoon", "good evening", "good night",
            "morning", "evening"
        ]
        for prefix in greetingPrefixes {
            if low.hasPrefix(prefix) && words.count <= 3 { return true }
        }

        // Greeting prefix + pure social question — catches "Hi, how are you", "Hey, how's it going?"
        // Deliberately narrow: only unambiguous social questions that cannot be coaching queries.
        let pureGreetingSocialQuestions = ["how are you", "how's it going", "how are things", "what's up", "whats up"]
        if greetingPrefixes.contains(where: { low.hasPrefix($0) }),
           pureGreetingSocialQuestions.contains(where: { low.contains($0) }) { return true }

        // Unconditional laughter / emoji (≤8 words, any position)
        let laughterTokens = ["lol", "haha", "hehe", "lmao", "😂", "😄", "🤣"]
        if words.count <= 8, laughterTokens.contains(where: { low.contains($0) }) { return true }

        // Single-word social acknowledgments
        let singleWordSocial = [
            "ok", "okay", "sure", "yep", "yup", "k",
            "cool", "nice", "great", "awesome", "perfect",
            "noted", "alright", "alrighty", "👍"
        ]
        if words.count == 1,
           let first = words.first,
           singleWordSocial.contains(first.trimmingCharacters(in: .punctuationCharacters)) {
            return true
        }

        // Multi-word acknowledgment phrases (≤5 words, social vocabulary present)
        let socialPhrases = [
            "thanks", "thank you", "thx", "sounds good", "got it",
            "that helped", "that was helpful", "that's helpful",
            "that was great", "that was amazing", "that was awesome",
            "that was useful", "that was perfect", "nice work"
        ]
        if words.count <= 5, socialPhrases.contains(where: { low.contains($0) }) { return true }

        // Past-tense positive sentiment about an event (no future action markers present)
        // Catches: "that game last night was amazing" even with sport vocabulary present
        let positivePatterns = [
            "was amazing", "was awesome", "was great", "was helpful",
            "was perfect", "was excellent", "was useful", "was good"
        ]
        let futureActionMarkers = [
            "will you", "can you", "could you", "should i",
            "going to", "want to", "plan to", "need to", "would you",
            "build", "create", "give me", "make me", "show me"
        ]
        if positivePatterns.contains(where: { low.contains($0) }),
           !futureActionMarkers.contains(where: { low.contains($0) }) {
            return true
        }

        return false
    }

    // MARK: — Bucket 2a: Simple Arithmetic

    /// Returns the computed result as a string if the message contains a simple
    /// two-operand arithmetic expression with no coaching or sport vocabulary.
    ///
    /// Scope is deliberately narrow:
    ///   - Only handles NUMBER OP NUMBER (two-operand, no chain expressions)
    ///   - Returns nil for anything that looks like a word problem or sport calculation
    ///   - Returns nil for division by zero
    ///
    /// Examples that return a result: "40 times 5", "12 + 9", "18*3", "100/4"
    /// Examples that return nil: "how many reps should I do", "40 minutes of training"
    static func evaluateArithmetic(_ low: String) -> String? {
        // Must not contain any coaching or sport vocabulary — guards against "how many reps"
        let coachingGuard = [
            "rep", "set", "drill", "workout", "session", "train",
            "basketball", "football", "soccer", "tennis",
            "shoot", "dribbl", "serve", "pass", "catch", "run",
            "exercise", "practice", "conditioning", "sport", "game",
            "calories", "miles", "minutes of", "seconds of", "hours of"
        ]
        if coachingGuard.contains(where: { low.contains($0) }) { return nil }

        // Must contain at least one digit
        guard low.contains(where: { $0.isNumber }) else { return nil }

        // Normalize word operators → symbols
        var expr = low
        let wordOperators: [(String, String)] = [
            (" divided by ", "/"), (" multiplied by ", "*"),
            (" times ", "*"), (" plus ", "+"), (" minus ", "-"),
            ("×", "*"), ("÷", "/")
        ]
        for (word, sym) in wordOperators {
            expr = expr.replacingOccurrences(of: word, with: sym)
        }

        // Strip common question preambles
        for preamble in ["what is ", "what's ", "whats ", "calculate ", "compute ", "evaluate ", "solve "] {
            expr = expr.replacingOccurrences(of: preamble, with: "")
        }
        expr = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing sentence punctuation (?, !, ., ,) that would break the regex end anchor.
        // Only trailing characters — never strip punctuation from inside the expression.
        expr = expr.trimmingCharacters(in: .init(charactersIn: "?!.,;:"))

        // Match exactly: NUMBER OP NUMBER (anchored — no chained expressions)
        let pattern = #"^(-?\d+(?:\.\d+)?)\s*([+\-*/])\s*(-?\d+(?:\.\d+)?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: expr, range: NSRange(expr.startIndex..., in: expr)),
              let r1 = Range(match.range(at: 1), in: expr),
              let r2 = Range(match.range(at: 2), in: expr),
              let r3 = Range(match.range(at: 3), in: expr)
        else { return nil }

        guard let left  = Double(String(expr[r1])),
              let right = Double(String(expr[r3]))
        else { return nil }

        let op = String(expr[r2])
        let result: Double
        switch op {
        case "+": result = left + right
        case "-": result = left - right
        case "*": result = left * right
        case "/":
            guard right != 0 else { return nil }    // Division by zero: unanswerable
            result = left / right
        default: return nil
        }

        // Format: integer when the result is a whole number, up to 4 sig figs otherwise
        if result == result.rounded(.towardZero), abs(result) < 1_000_000_000 {
            return String(Int(result.rounded()))
        }
        return String(format: "%.4g", result)
    }

    // MARK: — Bucket 3: Coaching-Likely

    /// Returns true when the message contains sport, skill, training, or coaching intent vocabulary.
    ///
    /// Errs toward inclusion — it is safer to send a vague coaching message through the pipeline
    /// (where Phase 2 will route it to .coachingConversational) than to incorrectly classify it
    /// as unclear and show a generic clarifying fallback.
    static func isCoachingLikely(_ low: String) -> Bool {
        // Sport names are unambiguous coaching signals
        let sportNames = ["basketball", "football", "soccer", "tennis"]
        if sportNames.contains(where: { low.contains($0) }) { return true }

        // Training and session vocabulary
        let trainingTerms = [
            "drill", "workout", "session", "warm up", "warmup", "cool down",
            "reps", "sets", "routine", "conditioning", "exercise",
            "practice", "technique", "form", "fundamentals", "skill work",
            "training plan", "training schedule", "weekly plan", "weekly schedule"
        ]
        if trainingTerms.contains(where: { low.contains($0) }) { return true }

        // Sport skill vocabulary (unique to sports training — not generic English words)
        let skillTerms = [
            "shooting", "dribbling", "ball handling", "layup", "euro step", "floater",
            "footwork", "pivot", "post move", "crossover", "free throw",
            "serve", "forehand", "backhand", "volley", "topspin", "drop shot", "overhead",
            "route running", "catching", "blocking", "pass rush", "release technique",
            "first touch", "finishing", "crossing", "heading",
            "left hand dribble", "weak hand", "off hand", "non-dominant",
            // Limb / side constraint signals — athletes naturally say "left hand", "right foot" etc.
            "left hand", "right hand", "left foot", "right foot",
            "weak side", "weaker hand", "weaker foot",
            "agility training", "explosiveness", "plyometric", "acceleration training",
            "strength training", "endurance training", "cardio training",
            "vertical jump", "athleticism", "court vision", "coverage read"
        ]
        if skillTerms.contains(where: { low.contains($0) }) { return true }

        // Coaching intent patterns (request paired with coaching object)
        let intentPatterns = [
            "help me", "how do i get better", "how do i improve",
            "want to get better", "want to improve", "want to train",
            "want to work", "want to practice", "need to improve",
            "how to improve", "how to train", "how to get better",
            "what drills", "what exercises", "what should i do",
            "what should i train", "how should i train",
            "what should i work", "what should i focus",
            "plan a session", "plan my training", "plan for training",
            // Constraint / requirement phrasing — athletes often state focus as a need:
            // "I require left hand work", "I need to work on my serve", "I struggle with crossing"
            "i require", "need to work on", "i need help with", "need help with",
            "focus on my", "i struggle with", "struggle with my",
            "working on my", "i want to focus"
        ]
        if intentPatterns.contains(where: { low.contains($0) }) { return true }

        // Coaching-adjacent emotional/progress expressions.
        // Athletes expressing stagnation or frustration are implicitly asking for coaching
        // help in this app context — route them through the pipeline, not to .unclear.
        let coachingAdjacentExpressions = [
            "feel stuck", "feeling stuck", "not improving", "not getting better",
            "not progressing", "losing progress", "fell behind", "don't know what to do next"
        ]
        if coachingAdjacentExpressions.contains(where: { low.contains($0) }) { return true }

        return false
    }

    // MARK: — Bucket 4: Off-Topic Factual

    /// Returns true for messages that are clearly about non-sport, non-training topics.
    ///
    /// Deliberately narrow: only catches unambiguous off-topic signals.
    /// When uncertain, let the message fall through to .unclear (safe default).
    static func isOffTopicFactual(_ low: String) -> Bool {
        let offTopicPatterns = [
            "what's the weather", "what is the weather", "weather today", "weather forecast",
            "who won last night", "who won the game", "what was the score",
            "homework", "school assignment", "help with my essay",
            "what's the news", "news today",
            "tell me a joke", "tell me a story",
            "recipe for", "how do i cook", "how to cook",
            "stock market", "stock price", "crypto price", "bitcoin price",
            "movie recommendation", "what show should", "music recommendation"
        ]
        return offTopicPatterns.contains(where: { low.contains($0) })
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

// MARK: - Phase 5F: Refinement Depth Guard
//
// File-scope helper for testing the modifier depth cap logic without needing access to
// the private ActiveRefinementContext struct.  The production logic mirrors this exactly.
enum RefinementDepthGuard {

    /// The maximum number of modifier steps before a reset is forced.
    /// Matches the `refCtx.modifierDepth >= maxDepth` check in the Phase 3 .refine case.
    static let maxDepth: Int = 3   // 5F tunable — 4th modifier resets

    /// Returns true if the given depth has reached the cap (next modifier would reset).
    static func isAtCap(depth: Int) -> Bool { depth >= maxDepth }

    /// Returns the depth after accepting one modifier (before any cap check).
    static func incrementedDepth(from current: Int) -> Int { current + 1 }
}

// MARK: - Phase 5E: Mention-Count Decay Config
//
// File-scope so the pure decay function is accessible from tests without any actor context.
// Tune decayFactor here — 0.80 means each concept loses 20% of its mention count when
// the session opens on a new calendar day.
enum MentionCountDecayConfig {
    static let decayFactor: Double = 0.80  // 5E tunable — fraction of count retained per day
    static let countFloor: Int     = 1     // 5E tunable — concepts never go below this count

    /// Applies decay to a mention-count dictionary.
    /// Returns a new dictionary; does not mutate in place.
    /// Each count is multiplied by `decayFactor`, floored at `countFloor`.
    static func apply(to counts: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (key, count) in counts {
            let decayed = max(countFloor, Int((Double(count) * decayFactor).rounded(.down)))
            result[key] = decayed
        }
        return result
    }
}

// MARK: - Phase 5D: Survey Recency Config
//
// File-scope enum (not inside any @MainActor type) so the computation function is freely
// accessible from both @MainActor code and unit tests without actor isolation issues.
// Tune the two constants below to adjust how quickly stale survey data loses influence.
enum SurveyRecencyConfig {
    static let decayPerWeek: Double  = 0.10   // 5D tunable — fraction lost per week
    static let minMultiplier: Double = 0.10   // 5D tunable — floor (never below 10%)

    /// Computes the recency weight multiplier for survey-derived focus areas.
    /// Returns 1.0 for fresh surveys (age ≤ 0 weeks) and decays by `decayPerWeek` per
    /// week, floored at `minMultiplier` so survey data never loses all influence.
    static func multiplier(ageInWeeks: Double) -> Double {
        guard ageInWeeks > 0 else { return 1.0 }
        let raw = 1.0 - (ageInWeeks * decayPerWeek)
        return max(minMultiplier, min(1.0, raw))
    }
}

// MARK: - View Model

@MainActor
class AICoachChatViewModel: ObservableObject {
    @Published var messages: [AICoachMessage] = []
    @Published var isLoading = false
    @Published var errorState: AICoachErrorState?
    @Published var proactiveCheckin: String?
    /// Current session coaching focus — shown as a slim insight banner above the input bar.
    @Published var sessionInsight: CoachSessionInsight?
    
    private let sport: Sport
    private let storageKey: String
    private let contextStorageKey: String
    private let storeManager = StoreManager.shared
    
    // Conversation context
    private var userWeakPoints: [String] = []
    private var userGoals: [String] = []
    private var availableTimeMinutes: Int?
    private var latestWeakness: String?            // Most recently mentioned weak skill or attribute
    private var athleticAttributes: [String] = []  // Speed, strength, conditioning, etc.
    private var recurringWeaknesses: [String: Int] = [:]  // concept → total mention count (memory evolution)

    // Phase 3: Most recent AI response context for refinement continuity.
    // Set after every successful response; cleared when a fresh topic is detected.
    private var activeRefinementContext: ActiveRefinementContext?

    /// Key parameters preserved from the most recent AI response.
    /// Enables Phase 3 to rebuild under modified constraints (time/intensity/equipment/recovery)
    /// without re-deriving from survey data or session history.
    private struct ActiveRefinementContext {
        var outputMode: OutputMode
        let primaryFocus: String
        let sportName: String
        var durationMinutes: Int      // Updated when time modifiers are applied
        var intensityHarder: Bool     // true when user asked for higher intensity
        var intensityEasier: Bool     // true when user asked for lower intensity
        var equipmentFree: Bool       // true when user asked for no-equipment version
        var recoveryMode: Bool        // true when user asked for recovery-mode version
        // 5F: Tracks accumulated modifier steps so we can cap at 3 and reset on the 4th.
        var modifierDepth: Int = 0
    }

    // Onboarding survey — loaded once on first chat open, persisted locally for offline use
    private var surveyResponse: OnboardingSurveyResponse?
    private static let surveyLocalKey = "ai_coach_survey_cache"

    // 5D: Survey staleness gate — named tunable constant keys.
    // Reduce survey influence by SurveyRecencyConfig.decayPerWeek for each week since the
    // survey was last fetched.  minMultiplier prevents complete suppression (never goes to 0).
    private static let surveyDateKey = "ai_coach_survey_date"

    // 5E: Mention-count decay — track the last date decay was applied to prevent
    // double-decaying within a single day (computed per-sport, per-instance).
    private var mentionDecayDateKey: String { "ai_coach_mention_decay_date_\(sport.rawValue)" }

    init(sport: Sport) {
        self.sport = sport
        self.storageKey = "ai_coach_messages_\(sport.rawValue)"
        self.contextStorageKey = "ai_coach_context_\(sport.rawValue)"
        loadMessages()
        loadContext()
    }
    
    func sendMessage(_ content: String) async {
        // Step 1: Validate prerequisites
        guard SessionManager.shared.isAuthenticated else {
            errorState = .authRequired
            return
        }
        
        guard storeManager.isPremium || storeManager.isLoading else {
            errorState = .premiumRequired
            return
        }
        
        // Clear any previous error
        errorState = nil
        
        // Add user message
        let userMessage = AICoachMessage(content: content, isUser: true)
        messages.append(userMessage)
        saveMessages()
        
        // ── PRE-PIPELINE INTENT GATE (Phase 1) ─────────────────────────────────────────
        // Classifies the message before any coaching pipeline logic runs.
        // .greetingSocial / .arithmeticFactual / .offTopicRedirect / .unclear are handled
        // directly here and return immediately — pipeline never runs for these.
        // Only .coachingLikely falls through to extractContext() below.
        let preIntent = PrePipelineClassifier.classify(content, sport: sport)
        CoachTelemetry.recordPrePipelineIntent(bucket: preIntent.telemetryLabel, sport: sport)

        switch preIntent {
        case .greetingSocial:
            let (text, actions) = prePipelineGreetingResponse(for: content)
            handlePrePipelineResponse(text, suggestedActions: actions)
            return
        case .arithmeticFactual(let answer):
            handlePrePipelineResponse("That's \(answer).")
            return
        case .offTopicRedirect:
            handlePrePipelineResponse(
                "I'm best at helping with your \(sport.rawValue) training — for that you'd want to check elsewhere. What would you like to work on today?",
                suggestedActions: ["Let's get to work"]
            )
            return
        case .unclear:
            let (text, actions) = prePipelineUnclearResponse()
            handlePrePipelineResponse(text, suggestedActions: actions)
            return
        case .coachingLikely:
            break   // Fall through to existing pipeline — zero changes below this line
        }
        // ── END PRE-PIPELINE GATE ────────────────────────────────────────────────────

        // ── PHASE 5C: SAFETY INTERRUPT ────────────────────────────────────────────────
        // Fires when the user mixes injury language with a coaching request in the same
        // message (e.g. "my knee hurts but build me a workout").
        // Safety categorically wins — we do NOT generate drills or plans when injury is
        // present alongside a request.  Pure injury-only messages are handled downstream
        // by SafetyConstraintClassifier; this gate is for the mixed-signal case only.
        if SafetyInterruptClassifier.isMixedInjuryCoachingRequest(content) {
            CoachTelemetry.recordPrePipelineIntent(bucket: "safety_interrupt", sport: sport)
            let keyword = SafetyDetector.firstMatchedKeyword(in: content) ?? "pain or discomfort"
            let (safetyText, safetyActions) = SafetyInterruptClassifier.safetyResponse(for: keyword, sport: sport)
            handlePrePipelineResponse(safetyText, suggestedActions: safetyActions)
            return
        }
        // ── END PHASE 5C ──────────────────────────────────────────────────────────────

        // ── PHASE 4a: APP-HELP CHECK ──────────────────────────────────────────────────
        // Runs BEFORE Phase 3 so "how do I log that?" after a coaching plan is caught here,
        // not treated as a refinement modifier.
        if AppHelpClassifier.isAppHelp(content) {
            CoachTelemetry.recordPrePipelineIntent(bucket: "app_help", sport: sport)
            let helpAnswer = AppHelpClassifier.answer(for: content, sport: sport)
            let helpActions = AppHelpClassifier.suggestedActions(for: content, sport: sport)
            handlePrePipelineResponse(helpAnswer, suggestedActions: helpActions)
            return
        }

        // ── PHASE 4b: ANALYTICS CHECK ─────────────────────────────────────────────────
        // Runs BEFORE Phase 3 so "how am I doing?" after a coaching plan is caught here,
        // not treated as a refinement modifier.
        if AnalyticsClassifier.isAnalytics(content) {
            CoachTelemetry.recordPrePipelineIntent(bucket: "analytics_summary", sport: sport)
            let (analyticsSummary, analyticsActions) = buildAnalyticsSummary(for: content)
            handlePrePipelineResponse(analyticsSummary, suggestedActions: analyticsActions)
            return
        }
        // ── END PHASE 4 ───────────────────────────────────────────────────────────────

        // ── PHASE 3: REFINEMENT GATE ──────────────────────────────────────────────────
        // For .coachingLikely messages only: checks if this modifies the most recent AI
        // response (refinement) vs. starting a fresh request from scratch.
        // Bound to the MOST RECENT AI response — not the full thread.
        let hasPriorAI = messages.contains(where: { !$0.isUser })
        if let refCtx = activeRefinementContext, hasPriorAI {
            let refinementIntent = RefinementClassifier.classify(
                message: content,
                hasPriorAIResponse: true,
                priorMode: refCtx.outputMode
            )
            switch refinementIntent {
            case .refine(let modifiers):
                // 5F: Cap modifier depth at 3. When the 4th modifier arrives (depth already 3),
                // reset the refinement context and let the message fall through to the pipeline
                // as a fresh request — prevents runaway constraint accumulation.
                if refCtx.modifierDepth >= 3 {
                    CoachTelemetry.recordPrePipelineIntent(bucket: "refinement_depth_reset", sport: sport)
                    print("🔄 [5F] Modifier depth cap reached (\(refCtx.modifierDepth)) — resetting to fresh request")
                    activeRefinementContext = nil
                    // No return: falls out of switch → out of if-let → to pipeline
                } else {
                    CoachTelemetry.recordPrePipelineIntent(bucket: "refinement_modify", sport: sport)
                    var updated = refCtx
                    for modifier in modifiers {
                        switch modifier {
                        case .shorterDuration(let mins):
                            updated.durationMinutes = mins ?? max(10, refCtx.durationMinutes - 15)
                        case .longerDuration:
                            updated.durationMinutes = min(120, refCtx.durationMinutes + 15)
                        case .harder:
                            updated.intensityHarder = true
                            updated.intensityEasier = false
                        case .easier:
                            updated.intensityEasier = true
                            updated.intensityHarder = false
                        case .noEquipment:
                            updated.equipmentFree = true
                        case .recoveryMode:
                            updated.recoveryMode = true
                            updated.intensityEasier = true
                        }
                    }
                    updated.modifierDepth += 1   // 5F: track accumulated depth
                    activeRefinementContext = updated
                    let refined = buildRefinedSessionResponse(context: updated, modifiers: modifiers)
                    handleSuccessResponse(refined, source: .localCoaching)
                    isLoading = false
                    return
                }

            case .convertGuidanceToSession:
                CoachTelemetry.recordPrePipelineIntent(bucket: "refinement_guidance_convert", sport: sport)
                let converted = buildGuidanceConversionResponse(context: refCtx)
                activeRefinementContext = ActiveRefinementContext(
                    outputMode: .workoutPlan,
                    primaryFocus: refCtx.primaryFocus,
                    sportName: refCtx.sportName,
                    durationMinutes: refCtx.durationMinutes,
                    intensityHarder: false,
                    intensityEasier: false,
                    equipmentFree: false,
                    recoveryMode: false,
                    modifierDepth: 0   // fresh context — reset depth
                )
                handleSuccessResponse(converted, source: .localCoaching)
                isLoading = false
                return

            case .conversationalCompletion:
                // User answered our gathering question with the missing specificity.
                // Clear refinement state and fall through — extractContext() will pick up the topic.
                CoachTelemetry.recordPrePipelineIntent(bucket: "refinement_conv_completion", sport: sport)
                activeRefinementContext = nil

            case .freshRequest:
                // New topic — clear refinement state, run full pipeline.
                activeRefinementContext = nil
            }
        }
        // ── END PHASE 3 ───────────────────────────────────────────────────────────────

        // ── PHASE 5B: AMBIGUITY GATE ───────────────────────────────────────────────────
        // Fires when: underspecified coaching intent + no prior AI in session + no active
        // refinement context.  Returns a sport-specific clarifying question rather than
        // fabricating a plan from an empty signal.
        // Must NOT fire when the user IS in an ongoing coaching thread (hasPriorAI == true)
        // because that would break conversational continuity.
        if !hasPriorAI,
           activeRefinementContext == nil,
           CoachingAmbiguityClassifier.isAmbiguous(content) {
            CoachTelemetry.recordPrePipelineIntent(bucket: "ambiguity_clarify", sport: sport)
            let (clarifyText, clarifyActions) = CoachingAmbiguityClassifier.clarifyingQuestion(for: sport)
            handlePrePipelineResponse(clarifyText, suggestedActions: clarifyActions)
            return
        }
        // ── END PHASE 5B ──────────────────────────────────────────────────────────────

        // ── PIPELINE STAGE 1: PROMPT BUILDER ──────────────────────────────────────────
        // assembleContext() then buildPromptContext() produces the single typed pipeline object
        extractContext(from: content)
        let promptCtx = buildPromptContext(for: content)

        // ── PIPELINE STAGE 2: TOOL DECISION ───────────────────────────────────────────
        // Currently always .none — reserved for future drill library + calculator integration
        _ = ToolPlan.decide(for: promptCtx)
        if promptCtx.specificityMode == .high {
            print("🎯 [AI Coach] HIGH specificity → GPT path — directive injected in brief, expecting 7-component output")
        }

        // ── PIPELINE STAGE 3: MODEL REASONING ─────────────────────────────────────────
        isLoading = true
        let apiClient = APIClient.shared

        let result = await attemptSendMessage(
            apiClient:  apiClient,
            content:    content,
            context:    promptCtx.apiContext,
            history:    promptCtx.conversationHistory
        )

        // ── PIPELINE STAGES 4 + 5: RESPONSE FORMATTER → FINAL OUTPUT ─────────────────
        switch result {
        case .success(var response):
            // Record GPT success for telemetry (always, not just in DEBUG)
            CoachTelemetry.recordGPTSuccess(sport: sport)

            // Post-response contract validation — runs in both DEBUG and RELEASE.
            // Critical violations (wrong sport, football 1v1, safety) fall back to local path.
            // Minor violations are logged via telemetry but the response is still shown.
            let violations = GPTResponseValidator.validate(response: response, sport: sport, message: content)
            if !violations.isEmpty {
                let criticals = violations.filter { $0.severity == .critical }
                let minors    = violations.filter { $0.severity == .minor }

                if GPTResponseValidator.isFallbackRequired(violations) {
                    for v in criticals {
                        print("❌ [GPT Validator] Critical violation: \(v.rule) — \(v.description)")
                        CoachTelemetry.recordGPTViolation(sport: sport, rule: v.rule, severity: "critical")
                    }
                    CoachTelemetry.recordGPTValidationFail(sport: sport, violationCount: criticals.count)

                    // ── CONSTRAINED RETRY ──────────────────────────────────────────────────────
                    // One final GPT attempt with strict contract rules injected into the backend
                    // system prompt (constrainedMode = true). If this also fails → local fallback.
                    // Guaranteed no loop: constrainedMode retry never triggers another retry.
                    print("🔄 [GPT Validator] Attempting constrained retry with strict contract injection...")
                    CoachTelemetry.recordConstrainedRetryStarted(sport: sport)

                    var constrainedCtx = promptCtx.apiContext
                    constrainedCtx.constrainedMode = true

                    let constrainedResult = await attemptSendMessage(
                        apiClient:  apiClient,
                        content:    content,
                        context:    constrainedCtx,
                        history:    promptCtx.conversationHistory
                    )

                    switch constrainedResult {
                    case .success(let constrainedResponse):
                        let constrainedViolations = GPTResponseValidator.validate(
                            response: constrainedResponse, sport: sport, message: content
                        )
                        if GPTResponseValidator.isFallbackRequired(constrainedViolations) {
                            // Second failure — now fall back to local (guaranteed stop, no loop)
                            print("❌ [GPT Validator] Constrained retry also failed — falling back to local path")
                            CoachTelemetry.recordConstrainedRetryFailed(sport: sport)
                            CoachTelemetry.recordGPTFallbackToLocal(sport: sport, reason: "constrained_retry_failed")
                            handleWithLocalCoaching(promptContext: promptCtx,
                                failureReason: .serverError("GPT constrained retry violated contract"))
                            isLoading = false
                            return
                        }
                        // Constrained retry succeeded
                        print("✅ [GPT Validator] Constrained retry succeeded")
                        CoachTelemetry.recordConstrainedRetrySucceeded(sport: sport)
                        let constrainedFormatted = ResponseFormatter.format(
                            constrainedResponse, context: promptCtx,
                            drillProvider: localDetailedDrillsForFocusArea
                        )
                        handleSuccessResponse(constrainedFormatted, source: .backend)
                        storeRefinementContext(from: promptCtx)
                        isLoading = false
                        return
                    case .failure:
                        // Network failure on constrained retry → local fallback
                        CoachTelemetry.recordConstrainedRetryFailed(sport: sport)
                        CoachTelemetry.recordGPTFallbackToLocal(sport: sport, reason: "constrained_retry_network_failure")
                        handleWithLocalCoaching(promptContext: promptCtx,
                            failureReason: .serverError("Constrained retry network failure"))
                        isLoading = false
                        return
                    }
                }

                // Attempt inline repair for football 1v1 violations before showing the response
                if sport == .football && FootballConstraintValidator.detectsViolation(in: response.response) {
                    if let repairedText = FootballConstraintValidator.repairResponse(response.response) {
                        response = CoachMessageResponse(
                            response: repairedText,
                            suggestedActions: response.suggestedActions,
                            tone: response.tone,
                            followUpQuestions: response.followUpQuestions,
                            timestamp: response.timestamp
                        )
                        CoachTelemetry.recordGPTRepairApplied(sport: sport, rule: "football_team_context")
                    } else {
                        // Repair failed — cannot safely show this response
                        CoachTelemetry.recordFootballConstraintRepairFailed(sport: sport)
                        CoachTelemetry.recordGPTFallbackToLocal(sport: sport, reason: "football_repair_failed")
                        handleWithLocalCoaching(promptContext: promptCtx, failureReason: .serverError("Football constraint repair failed"))
                        isLoading = false
                        return
                    }
                } else {
                    response = GPTResponseValidator.attemptRepair(response, sport: sport)
                }

                for v in minors {
                    CoachTelemetry.recordGPTViolation(sport: sport, rule: v.rule, severity: "minor")
                }
            }

            // Drill realism post-check (advisory — minor violations logged, not blocking)
            let realismViolations = DrillRealismValidator.validate(
                response: response.response,
                sport: sport,
                sessionMinutes: availableTimeMinutes
            )
            for rv in realismViolations {
                print("⚠️ [Drill Realism] \(rv.rule): \(rv.description)")
                CoachTelemetry.recordGPTViolation(sport: sport, rule: rv.rule, severity: "minor")
            }

            let formatted = ResponseFormatter.format(response, context: promptCtx, drillProvider: localDetailedDrillsForFocusArea)
            handleSuccessResponse(formatted, source: .backend)
            storeRefinementContext(from: promptCtx)

        case .failure(let firstError):
            let errorKind = classifyError(firstError)
            print("⚠️ [AI Coach] First attempt failed: \(errorKind.logDescription)")

            if errorKind.isRetryable {
                // One controlled retry for transient failures
                print("🔄 [AI Coach] Retrying after transient error...")
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s backoff

                let retryResult = await attemptSendMessage(
                    apiClient:  apiClient,
                    content:    content,
                    context:    promptCtx.apiContext,
                    history:    promptCtx.conversationHistory
                )

                switch retryResult {
                case .success(let response):
                    CoachTelemetry.recordGPTSuccess(sport: sport)
                    let formatted = ResponseFormatter.format(response, context: promptCtx, drillProvider: localDetailedDrillsForFocusArea)
                    handleSuccessResponse(formatted, source: .backend)
                    storeRefinementContext(from: promptCtx)
                case .failure(let retryError):
                    let retryErrorKind = classifyError(retryError)
                    print("❌ [AI Coach] Retry also failed: \(retryErrorKind.logDescription)")
                    CoachTelemetry.recordLocalFallback(sport: sport, reason: "retry_failed")
                    handleWithLocalCoaching(promptContext: promptCtx, failureReason: retryErrorKind)
                }
            } else if errorKind.isInfrastructureError {
                CoachTelemetry.recordLocalFallback(sport: sport, reason: errorKind.logDescription)
                handleWithLocalCoaching(promptContext: promptCtx, failureReason: errorKind)
            } else {
                // Auth/premium/unknown — show honest error, no fallback
                handleFailure(errorKind, userMessage: content)
            }
        }

        isLoading = false
    }

    /// Single API call attempt — returns Result, never throws
    private func attemptSendMessage(apiClient: APIClient, content: String, context: CoachContext, history: [ConversationMessage] = []) async -> Result<CoachMessageResponse, Error> {
        do {
            let response = try await apiClient.sendCoachMessage(sport: sport, message: content, context: context, conversationHistory: history)
            return .success(response)
        } catch {
            return .failure(error)
        }
    }

    /// Build conversation history for the backend — last 20 messages mapped to role/content pairs
    private func buildConversationHistory() -> [ConversationMessage] {
        messages.suffix(20).map { msg in
            ConversationMessage(role: msg.isUser ? "user" : "assistant", content: msg.content)
        }
    }
    
    /// Where the coaching response came from
    private enum ResponseSource {
        case backend
        case localCoaching
    }
    
    /// Handle successful AI response
    private func handleSuccessResponse(_ response: CoachMessageResponse, source: ResponseSource) {
        let aiMessage = AICoachMessage(
            content: response.response,
            isUser: false,
            suggestedActions: response.suggestedActions,
            tone: response.tone
        )
        messages.append(aiMessage)
        saveMessages()
        errorState = nil
        
        if source == .backend {
            print("✅ [AI Coach] Response from backend AI")
        } else {
            print("📱 [AI Coach] Response from local coaching engine")
        }
    }
    
    // MARK: - Pre-Pipeline Response Helpers

    /// Appends a lightweight AI message and returns — no pipeline, no GPT, no backend.
    private func handlePrePipelineResponse(_ content: String, suggestedActions: [String] = []) {
        let aiMessage = AICoachMessage(
            content: content,
            isUser: false,
            suggestedActions: suggestedActions,
            tone: "supportive"
        )
        messages.append(aiMessage)
        saveMessages()
        errorState = nil
        print("💬 [AI Coach] Pre-pipeline response returned — pipeline skipped")
    }

    /// Returns a warm reply for greeting/social messages plus sport-aware follow-up actions.
    private func prePipelineGreetingResponse(for message: String) -> (String, [String]) {
        let low = message.lowercased()
        let sportName = sport.rawValue.capitalized

        // Acknowledgement of a past session or positive feedback
        let positivePhrases = ["was amazing", "was great", "was awesome", "was helpful",
                               "was perfect", "was excellent", "that helped", "thanks", "thank you", "thx"]
        if positivePhrases.contains(where: { low.contains($0) }) {
            return (
                "Glad it helped. What do you want to work on next?",
                ["Plan my next session", "What should I focus on?", "Show me a drill"]
            )
        }

        // Greeting with context about what sport we're in
        let greetings = ["hi", "hey", "hello", "good morning", "good afternoon", "good evening"]
        if greetings.contains(where: { low.hasPrefix($0) }) {
            return (
                "Hey — what are we working on today for \(sportName)?",
                ["Build me a session", "What should I work on?", "Check my readiness"]
            )
        }

        // Single-word acknowledgement ("ok", "cool", "noted", etc.)
        return (
            "Got it. What do you want to work on for \(sportName)?",
            ["Build me a session", "Show me drills", "What's my weakness?"]
        )
    }

    /// Returns a sport-specific clarifying prompt for ambiguous/unclear messages.
    private func prePipelineUnclearResponse() -> (String, [String]) {
        let sportName = sport.rawValue.capitalized
        return (
            "I'm not sure what you're looking for — I can help with your \(sportName) training, drills, game planning, or injury recovery. What do you want to work on?",
            ["Build me a session", "Show me drills", "Help me improve a skill", "Check my readiness"]
        )
    }

    /// ALL inputs go through the unified pipeline — no keyword bypass, no exceptions.
    ///
    /// Pipeline:
    ///   1. CoachPromptContext     — typed context assembled by buildPromptContext()
    ///   2. buildPipelineLocalResponse() — routes to the correct renderer using context
    ///   3. applyReadinessToLocalResponse() — WHOOP-like intensity adaptation
    ///   4. ResponseFormatter.format()    — sport correctness / specificity / actions
    ///
    /// ZERO alternate paths. Every message — vague, short, explanation, follow-up — uses
    /// the same reasoning chain.
    private func handleWithLocalCoaching(promptContext: CoachPromptContext, failureReason: AICoachErrorKind) {
        print("📱 [AI Coach] LOCAL PATH — reason:\(failureReason.logDescription) specificity:\(promptContext.specificityMode == .high ? "HIGH 🎯" : "standard") sport:\(promptContext.sport.rawValue) focusAreas:\(promptContext.focusAreas.count)")
        if promptContext.specificityMode == .high {
            print("🎯 [AI Coach] LOCAL HIGH mode — using localDetailedDrillsForFocusArea() for all blocks")
        }
        let pipelineResp = buildPipelineLocalResponse(
            outputMode:      promptContext.outputMode,
            focusAreas:      promptContext.focusAreas,
            totalMins:       promptContext.availableTimeMinutes,
            specificityMode: promptContext.specificityMode
        )
        // Readiness layer sits AFTER plan is built — annotates and modifies but never replaces.
        let adapted   = applyReadinessToLocalResponse(pipelineResp)
        // ResponseFormatter enforces sport correctness, specificity, and action alignment.
        let formatted = ResponseFormatter.format(adapted, context: promptContext)
        handleSuccessResponse(formatted, source: .localCoaching)
        storeRefinementContext(from: promptContext)
    }

    /// Preserve the most recent successful response's key parameters for Phase 3 refinement.
    /// Called after every successful response — GPT or local — so follow-up modifier messages
    /// ("make it shorter", "harder", "no equipment") rebuild from the same base.
    private func storeRefinementContext(from context: CoachPromptContext) {
        let focus = context.focusAreas.first?.name ?? sport.rawValue
        activeRefinementContext = ActiveRefinementContext(
            outputMode:      context.outputMode,
            primaryFocus:    focus,
            sportName:       sport.rawValue,
            durationMinutes: context.availableTimeMinutes,
            intensityHarder: false,
            intensityEasier: false,
            equipmentFree:   false,
            recoveryMode:    false,
            modifierDepth:   0   // fresh context — reset depth
        )
    }

    /// Derive focus areas from session/survey context when the current message is vague.
    ///
    /// GUARANTEED output:
    ///   - ≥2 focus areas returned (never 0 or 1)
    ///   - ≥1 sport-specific skill area
    ///   - ≥1 athletic or fundamental component
    ///
    /// Skill priority: survey critical gaps (1–3) → survey weaknesses → recurring session
    /// concepts (≥2 mentions) → sport-default primary skill.
    /// Athletic component: added automatically if no existing area covers it.
    private func deriveFocusAreasFromContext() -> [FocusArea] {
        var result: [FocusArea] = []

        // 5D: Compute survey recency multiplier — reduces survey influence for stale data.
        let surveyDate = UserDefaults.standard.object(forKey: Self.surveyDateKey) as? Date
        let surveyAgeInWeeks: Double = {
            guard let date = surveyDate else { return 0 }
            return max(0, Date().timeIntervalSince(date)) / (7 * 24 * 3600)
        }()
        let recencyMult = SurveyRecencyConfig.multiplier(ageInWeeks: surveyAgeInWeeks)

        // ── Step 1: Collect sport-specific skill areas ─────────────────────
        if let survey = surveyResponse {
            let critical = survey.skillRatings.filter { $0.value <= 3 }.sorted { $0.value < $1.value }
            for pair in critical.prefix(2) {
                // Apply staleness multiplier to survey-derived weights (5D)
                let baseWeight: Double = result.isEmpty ? 1.0 : 0.70
                result.append(FocusArea(
                    name: pair.key,
                    concepts: ["direct_skill", "technique"],
                    userWeight: baseWeight * recencyMult
                ))
            }
            if result.isEmpty, let weak = survey.weaknesses.first {
                result.append(FocusArea(name: weak, concepts: ["technique"],
                                        userWeight: 1.0 * recencyMult))
            }
        }

        if result.isEmpty {
            for (i, pair) in recurringWeaknesses
                .filter({ $0.value >= 2 })
                .sorted(by: { $0.value > $1.value })
                .prefix(2)
                .enumerated() {
                result.append(FocusArea(
                    name: pair.key,
                    concepts: ["technique"],
                    userWeight: i == 0 ? 1.0 : 0.70
                ))
            }
        }

        // Sport-default skill guarantees ≥1 skill area is always present
        if result.isEmpty {
            result.append(FocusArea(
                name: defaultSportSkill(),
                concepts: ["direct_skill", "technique"],
                userWeight: 1.0
            ))
        }

        // ── Step 2: Ensure ≥1 athletic or fundamental component ────────────
        let athleticKeywords = ["conditioning", "footwork", "athleticism", "endurance",
                                 "speed", "agility", "strength", "stamina", "explosiveness",
                                 "fundamentals", "fitness", "cardio"]
        let hasAthletic = result.contains { area in
            let low = area.name.lowercased()
            return athleticKeywords.contains { low.contains($0) }
        }
        if !hasAthletic {
            result.append(FocusArea(
                name: defaultAthleticComponent(),
                concepts: ["conditioning", "athleticism"],
                userWeight: 0.50
            ))
        }

        // ── Step 3: Guarantee total ≥2 ─────────────────────────────────────
        // Edge case: step 2 skipped because existing area was already athletic →
        // add sport-default skill so there is always a concrete skill to drill.
        if result.count < 2 {
            let fallback = defaultSportSkill()
            if !result.contains(where: { $0.name.lowercased() == fallback.lowercased() }) {
                result.append(FocusArea(name: fallback, concepts: ["direct_skill", "technique"], userWeight: 0.70))
            } else {
                result.append(FocusArea(name: "\(sport.rawValue) fundamentals", concepts: ["fundamentals", "technique"], userWeight: 0.35))
            }
        }

        return result
    }

    /// Primary skill baseline for each sport — used when no survey or session signals exist.
    private func defaultSportSkill() -> String {
        switch sport {
        case .basketball: return "shooting"
        case .football:   return "route running"
        case .soccer:     return "first touch"
        case .tennis:     return "forehand"
        }
    }

    /// Default athletic/conditioning component — added when no physical area is present.
    private func defaultAthleticComponent() -> String {
        switch sport {
        case .basketball: return "conditioning"
        case .football:   return "acceleration training"
        case .soccer:     return "conditioning"
        case .tennis:     return "footwork"
        }
    }

    // MARK: - Readiness Engine

    /// Compute today's coaching readiness from all available biometric + self-reported signals.
    ///
    /// Scoring (max 100):
    ///   HRV (0–25):         >55ms → 25 | 40–55 → 18 | 28–40 → 10 | <28 → 0
    ///   Resting HR (0–25):  <58bpm → 25 | <65 → 18 | <72 → 10 | <80 → 5 | ≥80 → 0
    ///   Sleep (0–30):       ≥8h → 30 | ≥7h → 23 | ≥6h → 14 | ≥5h → 6 | <5h → 0
    ///   Self-report (0–20): "good/great/ready" → 20 | "ok/moderate" → 12 | "tired/poor" → 4 | "exhausted" → 0
    ///   Steps penalty:      >15k steps → −8 | >10k → −4 (accumulated daily strain)
    ///
    /// Falls back to a neutral medium profile (score 45) when no data exists.
    private func computeReadiness() -> CoachReadinessProfile {
        let defaults = UserDefaults.standard
        let selfReport = defaults.string(forKey: "daily_readiness_\(sport.rawValue)")

        // ── Wearable data gates (staleness + validity) ────────────────────────────────
        // Gate 1 — Staleness: reject data older than 24 hours
        let lastSync = defaults.double(forKey: "smartwatch_last_sync")
        let syncAge  = lastSync > 0 ? Date().timeIntervalSince1970 - lastSync : Double.infinity
        let wearableIsStale = syncAge > 86_400  // 24 hours

        // Gate 2 — Validity: reject data that failed physiological range checks
        // `wearable_data_valid` is written by WearableProviderManager.persistForAICoach()
        // Nil (key absent) = no sync has ever run → treat as not valid
        let wearableIsValid = !wearableIsStale && (defaults.object(forKey: "wearable_data_valid") as? Bool == true)

        // Gate 3 — Recovery data presence: HRV/resting HR/sleep only available for full syncs
        let hasRecoveryData = wearableIsValid && (defaults.object(forKey: "wearable_has_recovery_data") as? Bool == true)

        if wearableIsStale && lastSync > 0 {
            let ageHours = Int(syncAge / 3600)
            print("[AI Coach] Wearable data is \(ageHours)h old — exceeds 24h staleness gate, using neutral values")
        } else if !wearableIsValid && lastSync > 0 {
            print("[AI Coach] Wearable data failed validation gate — using neutral values for recovery metrics")
        }

        // Read raw values — then gate each field by data quality
        let rawHRV       = defaults.object(forKey: "smartwatch_hrv") as? Double
        let rawRestingHR = defaults.object(forKey: "smartwatch_resting_hr") as? Double
        let rawSleep     = defaults.object(forKey: "smartwatch_sleep_hours") as? Double
        let rawSteps     = defaults.object(forKey: "smartwatch_steps") as? Int

        // Recovery metrics: only trusted when wearable data passed BOTH validity + recovery gates
        let hrv       = hasRecoveryData ? rawHRV       : nil
        let restingHR = hasRecoveryData ? rawRestingHR : nil
        let sleep     = hasRecoveryData ? rawSleep     : nil
        // Activity: available for activity-only syncs too (steps affect strain penalty)
        let steps     = wearableIsValid ? rawSteps     : nil

        let hasWearable = hrv != nil || restingHR != nil || sleep != nil || steps != nil

        // No data at all — return neutral medium so the pipeline doesn't fail
        guard hasWearable || selfReport != nil else {
            return CoachReadinessProfile(
                level: .medium, score: 50,
                hrv: nil, restingHR: nil, sleepHours: nil, steps: nil,
                selfReported: nil, hasWearableData: false,
                recoveryNote: "No biometric data — using default moderate readiness."
            )
        }

        var score = 0

        // HRV: higher = better nervous system recovery
        if let h = hrv {
            if h > 55      { score += 25 }
            else if h > 40 { score += 18 }
            else if h > 28 { score += 10 }
            // < 28ms: +0 — significant fatigue indicator
        } else {
            score += 15 // neutral when no HRV sensor
        }

        // Resting HR: lower = better cardiovascular recovery
        if let rhr = restingHR {
            if rhr < 58      { score += 25 }
            else if rhr < 65 { score += 18 }
            else if rhr < 72 { score += 10 }
            else if rhr < 80 { score += 5 }
            // ≥ 80bpm: +0 — significantly elevated
        } else {
            score += 15 // neutral
        }

        // Sleep: foundation of recovery — weighted highest
        if let s = sleep {
            if s >= 8.0      { score += 30 }
            else if s >= 7.0 { score += 23 }
            else if s >= 6.0 { score += 14 }
            else if s >= 5.0 { score += 6  }
            // < 5h: +0 — severe sleep debt
        } else {
            score += 18 // neutral
        }

        // Self-reported readiness: direct subjective signal
        if let report = selfReport?.lowercased() {
            if report.contains("great") || report.contains("good") || report.contains("ready") {
                score += 20
            } else if report.contains("ok") || report.contains("moderate") || report.contains("alright") {
                score += 12
            } else if report.contains("tired") || report.contains("sore") || report.contains("poor") {
                score += 4
            } else if report.contains("exhaust") || report.contains("terrible") {
                score += 0
            } else {
                score += 12 // unrecognized term — neutral
            }
        } else {
            score += 12 // neutral when not self-reported
        }

        // Steps penalty — accumulated daily strain reduces available capacity
        if let s = steps {
            if s > 15000 { score = max(0, score - 8) }
            else if s > 10000 { score = max(0, score - 4) }
        }

        // Classify
        let level: CoachReadinessLevel
        if score >= 70      { level = .high }
        else if score >= 40 { level = .medium }
        else                { level = .low }

        // Build a specific, non-generic recovery note
        let note: String
        switch level {
        case .high:
            note = "Recovery is strong — full intensity, progressive overload, include power/speed work."
        case .medium:
            var reasons: [String] = []
            if let s = sleep, s < 7.0      { reasons.append("sleep \(String(format: "%.1f", s))h below 7h target") }
            if let rhr = restingHR, rhr > 65 { reasons.append("resting HR \(Int(rhr))bpm elevated") }
            if let h = hrv, h < 45         { reasons.append("HRV \(Int(h))ms below baseline") }
            if reasons.isEmpty             { reasons.append("moderate recovery signals") }
            note = "Moderate readiness (\(reasons.joined(separator: "; "))) — reduce volume ~20%, preserve technique quality."
        case .low:
            var reasons: [String] = []
            if let h = hrv, h < 35         { reasons.append("HRV \(Int(h))ms — suppressed nervous system") }
            if let s = sleep, s < 6.0      { reasons.append("sleep only \(String(format: "%.1f", s))h") }
            if let rhr = restingHR, rhr > 72 { reasons.append("resting HR \(Int(rhr))bpm — high fatigue marker") }
            if reasons.isEmpty             { reasons.append("multiple recovery indicators below baseline") }
            note = "Low readiness (\(reasons.joined(separator: "; "))) — technique-only mode, reduce intensity ~40%, extend rest."
        }

        return CoachReadinessProfile(
            level: level, score: score,
            hrv: hrv, restingHR: restingHR, sleepHours: sleep, steps: steps,
            selfReported: selfReport, hasWearableData: hasWearable,
            recoveryNote: note
        )
    }

    /// Build the READINESS DIRECTIVE block for the GPT coaching brief.
    ///
    /// Rules:
    ///   • Never collapses to "just rest today"
    ///   • Always prescribes sport-specific drill modifications
    ///   • Never replaces focus areas — only changes HOW they are trained
    ///   • Readiness modifies intensity and volume; sport lock is never overridden
    private func adaptPlanForReadiness(profile: CoachReadinessProfile) -> String {
        var lines: [String] = []
        lines.append("READINESS STATE: \(profile.level.label) (score \(profile.score)/100)")
        lines.append("RECOVERY NOTE: \(profile.recoveryNote)")

        switch profile.level {
        case .high:
            lines.append("READINESS DIRECTIVE (HIGH): Athlete is fully recovered — push intensity today.")
            switch sport {
            case .basketball:
                lines.append("  • Include 1–2 max-effort explosive drills (full-court speed dribble, pull-up jumper under fatigue, live 1v1 speed reps).")
                lines.append("  • Conditioning block appropriate at >80% effort — include sprint or tempo run component.")
                lines.append("  • Apply progressive overload: if this skill has appeared before, increase reps/sets or add a defender.")
            case .football:
                lines.append("  • Full-speed route running with game-pace cuts — no half-speed reps today.")
                lines.append("  • Max-effort release work off the line — include explosion and first-step reps.")
                lines.append("  • Add 2–3 sprint/acceleration reps at the end of the primary block.")
            case .soccer:
                lines.append("  • Game-intensity 1v1 finishing and dribbling — include pressure or simulated opponent.")
                lines.append("  • Include 2 tempo runs in warmup or transfer block — full conditioning is appropriate.")
                lines.append("  • High-pace combination play drill (rondo or pressing pattern) at end of session.")
            case .tennis:
                lines.append("  • Match-intensity groundstroke rallying — push rally length to 8–10 shots with pace.")
                lines.append("  • Power serve practice: target full-effort first serves at 90%+ pace.")
                lines.append("  • Include a full footwork sprint circuit (split-step reaction → baseline recovery, ×5).")
            }

        case .medium:
            lines.append("READINESS DIRECTIVE (MODERATE): Reduce total volume ~20% — maintain technique quality, avoid max-effort spikes.")
            switch sport {
            case .basketball:
                lines.append("  • Replace 1 sprint/high-effort drill with a form/control variant (e.g., spot shooting instead of full-court speed dribble).")
                lines.append("  • Cap conditioning block at 60–70% effort — no all-out runs or max reps.")
                lines.append("  • Add 15–20s extra rest between dribbling/ball-handling sets compared to a peak session.")
            case .football:
                lines.append("  • Reduce full-speed route reps by 30% — sharp cuts still expected but total volume drops.")
                lines.append("  • Skip max-effort acceleration sprints — replace with controlled 70–75% speed technique reps.")
                lines.append("  • Focus on release mechanics and hand placement, not raw explosiveness today.")
            case .soccer:
                lines.append("  • Remove high-intensity conditioning runs — keep all technical work without sustained sprinting.")
                lines.append("  • Reduce total drill distance by 25% — shorter transitions between cones.")
                lines.append("  • Use rondo or possession circle instead of 1v1 for the transfer block today.")
            case .tennis:
                lines.append("  • Use controlled cross-court rallying instead of match intensity — consistent groundstrokes over power.")
                lines.append("  • Second-serve practice over first-serve today — control and spin focus, not pace.")
                lines.append("  • Shorten footwork bursts: 3 reps × 10m instead of a full ladder sprint circuit.")
            }

        case .low:
            lines.append("READINESS DIRECTIVE (LOW): Recovery mode — technique/skill refinement, protect the body from overload.")
            lines.append("  ⚠ Do NOT prescribe conditioning runs, max-effort sprints, plyometrics, or full-speed game reps.")
            lines.append("  ⚠ Do NOT collapse the session to 'just rest today' — prescribe focused skill work at low intensity.")
            switch sport {
            case .basketball:
                lines.append("  • Stationary skill focus: form shooting, stationary ball handling, walk-through footwork patterns only.")
                lines.append("  • All drills at 50–60% effort — emphasize touch, feel, and mechanics, not speed.")
                lines.append("  • Double rest periods: 60s between sets minimum instead of the usual 30s.")
                lines.append("  • Replace any sprint or agility drill with a slow walk-through or visualization rep.")
            case .football:
                lines.append("  • Walk-through route running at 40% effort — technique and route shape only, zero explosion.")
                lines.append("  • Mental reps: describe route break angles, release timing, and coverage reads verbally.")
                lines.append("  • Resistance band stationary hip-activation and release mechanics — no full-speed patterns.")
                lines.append("  • Extend all rest periods to 90s minimum between sets.")
            case .soccer:
                lines.append("  • Rondos and possession circles only — low-intensity passing with no sprinting.")
                lines.append("  • Stationary technical work: first-touch against a wall (slow), cone patterns at walking pace.")
                lines.append("  • Light recovery jog warmup (no tempo runs), extended static-stretch cooldown (10+ min).")
                lines.append("  • No shooting under pressure or competitive 1v1 today.")
            case .tennis:
                lines.append("  • Mini-tennis only (inside service boxes) — short, controlled rallying, no power.")
                lines.append("  • Serve from the baseline: focus only on toss height and arm path, not pace or spin.")
                lines.append("  • Stationary volley pairs at the net: no footwork sprint component.")
                lines.append("  • Cap session length at 30–35 min maximum, regardless of stated available time.")
            }
        }

        // Universal rule: readiness never overrides sport context
        lines.append("READINESS + SPORT LOCK: All readiness-adapted drills must remain \(sport.rawValue)-specific. Readiness modifies intensity and volume — never the sport context or focus area.")

        return lines.joined(separator: "\n")
    }

    /// Apply readiness-based annotations to local (offline) coaching responses.
    ///
    /// Prepends a readiness context header and adjusts suggested actions + follow-up questions.
    /// Only injects content when biometric or self-reported data is available.
    /// Never replaces the session plan — only annotates it.
    private func applyReadinessToLocalResponse(_ response: CoachMessageResponse) -> CoachMessageResponse {
        let profile = computeReadiness()

        // Don't inject readiness context if there is truly no data
        guard profile.hasWearableData || profile.selfReported != nil else {
            return response
        }

        let prefix: String
        let actions: [String]
        let followUps: [String]

        switch profile.level {
        case .high:
            prefix = "**Readiness: High (\(profile.score)/100)** — \(profile.recoveryNote)\n\n"
            // Preserve existing actions, add intensity nudge
            actions = (response.suggestedActions + ["Push intensity today"]).prefix(4).map { $0 }
            followUps = response.followUpQuestions

        case .medium:
            prefix = "**Readiness: Moderate (\(profile.score)/100)** — \(profile.recoveryNote)\n*Volume is reduced ~20% from a peak session. Prioritize technique quality over rep count.*\n\n"
            actions = response.suggestedActions
            followUps = (["How is your energy mid-session?"] + response.followUpQuestions).prefix(3).map { $0 }

        case .low:
            prefix = "**Readiness: Low (\(profile.score)/100)** — \(profile.recoveryNote)\n*Session calibrated for recovery: skill refinement at reduced intensity. Technique work at low load still drives real improvement — don't skip it.*\n\n"
            actions = ["Log this session", "Check recovery tomorrow"]
            followUps = ["How does your body feel during this?", "Want tomorrow's adjusted plan?"]
        }

        return CoachMessageResponse(
            response: prefix + response.response,
            suggestedActions: actions,
            tone: response.tone,
            followUpQuestions: followUps,
            timestamp: response.timestamp
        )
    }

    /// Route to the correct local renderer based on detected output mode.
    /// Every case uses the same focus areas and sport context — no shortcuts.
    private func buildPipelineLocalResponse(outputMode: OutputMode, focusAreas: [FocusArea], totalMins: Int, specificityMode: SpecificityMode = .standard) -> CoachMessageResponse {
        switch outputMode {
        case .schedulePlan:
            return buildLocalScheduleResponse(focusAreas: focusAreas, sessionMins: totalMins, specificityMode: specificityMode)
        case .explanation:
            return buildLocalExplanationResponse(focusAreas: focusAreas, specificityMode: specificityMode)
        case .workoutPlan, .hybrid:
            var blocks = buildTimeBlocks(totalMinutes: totalMins, focusAreas: focusAreas)
            validateTimeBudget(blocks: &blocks, requestedMinutes: totalMins)
            return buildLocalSessionResponse(focusAreas: focusAreas, blocks: blocks, totalMins: totalMins, specificityMode: specificityMode)
        case .guidance:
            return buildLocalGuidanceResponse(focusAreas: focusAreas)
        case .coachingConversational:
            return buildLocalConversationalResponse(focusAreas: focusAreas)
        }
    }

    /// Render a coaching explanation using the full reasoning pipeline.
    ///
    /// Explanation ≠ simplified path. It uses AICoachReasoning.analyze() to produce
    /// sport-specific coaching insight: WHY it matters, WHAT the limitation looks like,
    /// HOW to train it, and an applied drill example. Equal depth to a workout response.
    private func buildLocalExplanationResponse(focusAreas: [FocusArea], specificityMode: SpecificityMode = .standard) -> CoachMessageResponse {
        guard let primary = focusAreas.first else {
            return CoachMessageResponse(
                response: "What aspect of your \(sport.rawValue) game would you like to understand better? Tell me the skill or situation and I'll give you a coaching breakdown.",
                suggestedActions: ["Tell me what to work on"],
                tone: "supportive",
                followUpQuestions: ["Which skill or situation feels most unclear?"],
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }

        // Full pipeline analysis — same path as buildCoachingBrief()
        let analysis = AICoachReasoning.analyze(
            concepts: primary.concepts,
            message: primary.name,
            intent: "explanation",
            sport: sport
        )

        var lines: [String] = []
        lines.append("Here's your \(sport.rawValue) coaching breakdown on **\(primary.name)**:\n")

        if let a = analysis {
            lines.append("**Why it matters in \(sport.rawValue):**")
            lines.append(a.sportImpact)
            lines.append("")

            lines.append("**What it looks like when it's limiting you:**")
            lines.append(a.manifestation)
            lines.append("")

            lines.append("**How to train it:**")
            lines.append(a.trainingFocus)
            lines.append("")

            // Progression stage context
            let mentionCount  = recurringWeaknesses[primary.name.lowercased()] ?? 1
            let sessionCount  = SafetyDetector.weeklySessionCount(for: sport)
            let feedback      = CoachFeedbackStore.feedbackCounts(for: sport)
            let derivedStage  = OutcomeAwareProgressionStage.derive(
                mentionCount: mentionCount, sessionCount: sessionCount, feedbackRatio: feedback
            )
            let stage = ProgressionStage(mentionCount: derivedStage)
            lines.append("**Where you are right now:** Stage \(stage.stageNumber)/3 — \(stage.displayName)")
            lines.append(stage.sessionDesignPrinciple)
            lines.append("")
        }

        // In HIGH mode: show full 7-component drill example; STANDARD: compact one-liner
        lines.append("**Applied \(sport.rawValue) example — try this now:**")
        if specificityMode == .high {
            let detailedDrills = localDetailedDrillsForFocusArea(name: primary.name)
            if let firstDrill = detailedDrills.first {
                lines.append(firstDrill)
            }
            // In HIGH mode also show suggested actions reflecting depth
            let suggestedActions = ["Build a full detailed session", "More drills like this", "Log this session"]
            let secondaryConnection: String? = focusAreas.count > 1
                ? "\nYour secondary area **\(focusAreas[1].name)** connects here: the same movement patterns that improve \(primary.name) transfer directly into \(focusAreas[1].name)."
                : nil
            if let conn = secondaryConnection { lines.append(conn) }
            lines.append("\nWant a full session built around these drills at this level of detail?")
            return CoachMessageResponse(
                response: lines.joined(separator: "\n"),
                suggestedActions: suggestedActions,
                tone: "educational",
                followUpQuestions: [
                    "Want all drills in this session at this depth?",
                    "Which component of this drill is hardest?"
                ],
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        } else {
            let drills = localDrillsForFocusArea(name: primary.name)
            if let firstDrill = drills.first {
                lines.append(firstDrill)
            }
            if focusAreas.count > 1 {
                let secondary = focusAreas[1]
                lines.append("\nYour secondary area **\(secondary.name)** connects to this: improving \(primary.name) unlocks \(secondary.name) because the same movement patterns carry over.")
            }
            lines.append("\nWant me to build a complete session around this?")
            return CoachMessageResponse(
                response: lines.joined(separator: "\n"),
                suggestedActions: ["Build a full session", "Show me more drills"],
                tone: "educational",
                followUpQuestions: [
                    "Want a complete \(primary.name) session?",
                    "Which part of this still feels unclear?"
                ],
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        }
    }

    // MARK: - Phase 2 Local Handlers

    /// Guidance mode — directional advisory coaching, not a full plan.
    /// Returns brief, direct coaching advice + a confirming question so the athlete can
    /// confirm before committing to a session.
    private func buildLocalGuidanceResponse(focusAreas: [FocusArea]) -> CoachMessageResponse {
        let sportName = sport.rawValue.capitalized
        let primaryFocus = focusAreas.first?.name ?? "the fundamentals of your \(sportName) game"
        let response = """
        Based on what you've been working on, I'd prioritize **\(primaryFocus)** today.

        It's where consistent reps compound fastest right now — drilling it repeatedly across short focused sessions will move the needle more than spreading your time across multiple skills.

        Does that match what you're feeling, or is there something pulling your attention elsewhere?
        """
        return CoachMessageResponse(
            response: response,
            suggestedActions: [
                "Yes — build me a session around \(primaryFocus)",
                "Actually I want to work on something else",
                "Tell me why that's the priority"
            ],
            tone: "directive",
            followUpQuestions: ["How much time do you have today?"],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Coaching conversational mode — vague coaching intent, needs a gathering question.
    /// Returns a sport-specific question to pull out what the athlete actually needs
    /// before any plan or drill prescription happens.
    private func buildLocalConversationalResponse(focusAreas: [FocusArea]) -> CoachMessageResponse {
        let sportName = sport.rawValue.capitalized
        let intro: String
        let suggestedActions: [String]

        if let primary = focusAreas.first {
            intro = "Got it. To give you the most useful \(primary.name) work, let me ask — how much time do you have to train today?"
            suggestedActions = [
                "About 20–30 minutes",
                "Around 45 minutes",
                "An hour or more",
                "Tell me what to work on regardless"
            ]
        } else {
            intro = "I want to make sure I give you the most useful \(sportName) training possible. What part of your game do you want to improve right now?"
            suggestedActions = [
                "My \(sportName) fundamentals",
                "A specific skill I'm struggling with",
                "My athleticism and conditioning",
                "Help me figure out what to focus on"
            ]
        }

        return CoachMessageResponse(
            response: intro,
            suggestedActions: suggestedActions,
            tone: "supportive",
            followUpQuestions: [],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Phase 3: Refinement Response Builders

    /// Rebuilds the prior session under modified constraints.
    ///
    /// Preserves sport, focus, and output mode from `ActiveRefinementContext`.
    /// Applies only the new modifier(s) — time / intensity / equipment / recovery.
    /// Replaces the opening header line so the user sees what changed.
    private func buildRefinedSessionResponse(
        context: ActiveRefinementContext,
        modifiers: [RefinementModifier]
    ) -> CoachMessageResponse {
        let focus = context.primaryFocus
        let mins  = context.durationMinutes

        // Describe the adjustment(s) for the response header
        var changeNotes: [String] = []
        for mod in modifiers {
            switch mod {
            case .shorterDuration(let m): changeNotes.append("\(m ?? mins) minutes")
            case .longerDuration:         changeNotes.append("extended to \(mins) minutes")
            case .harder:                 changeNotes.append("higher intensity")
            case .easier:                 changeNotes.append("scaled-down intensity")
            case .noEquipment:            changeNotes.append("no equipment")
            case .recoveryMode:           changeNotes.append("recovery mode")
            }
        }
        let changeLabel = changeNotes.isEmpty ? "" : " — \(changeNotes.joined(separator: ", "))"

        // Build the underlying session via the existing local pipeline
        let focusArea = FocusArea(name: focus, concepts: ["direct_skill"], userWeight: 1.0)
        var baseResp: CoachMessageResponse

        switch context.outputMode {
        case .schedulePlan:
            baseResp = buildLocalScheduleResponse(focusAreas: [focusArea], sessionMins: mins)
        default:
            // workoutPlan, hybrid, guidance → rebuild as a concrete workout session
            let blocks = buildTimeBlocks(totalMinutes: mins, focusAreas: [focusArea])
            baseResp = buildLocalSessionResponse(focusAreas: [focusArea], blocks: blocks, totalMins: mins)
        }

        // Replace the first line ("Here's your X-min …") with a concise adjustment label.
        // Splitting on "\n" preserves all block content after the header.
        var lines = baseResp.response.components(separatedBy: "\n")
        if !lines.isEmpty {
            lines[0] = "Got it\(changeLabel) — your adjusted \(focus) session:"
        }

        var adjusted = CoachMessageResponse(
            response: lines.joined(separator: "\n"),
            suggestedActions: baseResp.suggestedActions,
            tone: baseResp.tone,
            followUpQuestions: baseResp.followUpQuestions,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )

        // Recovery mode: apply the readiness layer to de-intensify and annotate
        if context.recoveryMode {
            adjusted = applyReadinessToLocalResponse(adjusted)
        }

        return adjusted
    }

    /// Converts a prior .guidance topic into a concrete .workoutPlan session.
    ///
    /// Called when the user says "make that into a session" / "build me a session"
    /// after a guidance response. Preserves the guidance topic as the workout focus.
    private func buildGuidanceConversionResponse(context: ActiveRefinementContext) -> CoachMessageResponse {
        let focus = context.primaryFocus
        let mins  = context.durationMinutes
        let focusArea = FocusArea(name: focus, concepts: ["direct_skill"], userWeight: 1.0)
        let blocks = buildTimeBlocks(totalMinutes: mins, focusAreas: [focusArea])
        let baseResp = buildLocalSessionResponse(focusAreas: [focusArea], blocks: blocks, totalMins: mins)

        // Replace header to signal this came from a guidance conversion, not a fresh request
        var lines = baseResp.response.components(separatedBy: "\n")
        if !lines.isEmpty {
            lines[0] = "Perfect — here's your \(focus) session:"
        }

        return CoachMessageResponse(
            response: lines.joined(separator: "\n"),
            suggestedActions: ["Log this session", "Make it harder", "I only have 20 minutes"],
            tone: "directive",
            followUpQuestions: ["How did it go?"],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Phase 4: Analytics & Time-Budget Methods

    /// Builds a training analytics summary from real local data only.
    ///
    /// Sources used:
    ///   - `recent_sessions_{sport}` UserDefaults key (SavedSessionData array)
    ///   - `SafetyDetector.weeklySessionCount(for:)`
    ///   - `CoachFeedbackStore.feedbackCounts(for:)`
    ///   - `recurringWeaknesses` (in-memory coaching patterns)
    ///   - `TrainingOutcomeAnalyzer.analyze(sessions:)`
    ///
    /// Sparse data guard: < 3 total sessions → honest "not enough data" response. No fabrication.
    private func buildAnalyticsSummary(for message: String) -> (String, [String]) {
        let sessionsKey = "recent_sessions_\(sport.rawValue)"
        let allSessions: [SavedSessionData]
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([SavedSessionData].self, from: data) {
            allSessions = decoded
        } else {
            allSessions = []
        }

        // Sparse data threshold: < 3 total sessions → honest response, no fabrication
        guard allSessions.count >= 3 else {
            let count = allSessions.count
            let countStr = count == 0 ? "no sessions" : count == 1 ? "1 session" : "\(count) sessions"
            let text = """
            I've found \(countStr) logged for \(sport.rawValue) on this device. \
            Log at least 3 sessions so I can give you a meaningful progress summary.

            Your stats will grow the more you train — each saved session adds data for \
            effort trends, weakness patterns, and drill variety tracking.
            """
            let actions = ["Log a session now", "Ask for a workout plan", "What should I work on?"]
            return (text, actions)
        }

        let summary    = TrainingOutcomeAnalyzer.analyze(sessions: allSessions)
        let weeklyCount = SafetyDetector.weeklySessionCount(for: sport)
        let feedback   = CoachFeedbackStore.feedbackCounts(for: sport)

        var lines: [String] = []
        lines.append("Here's your \(sport.rawValue) training summary:\n")

        // Session frequency
        switch weeklyCount {
        case 0:  lines.append("**This week:** No sessions logged — rest week.")
        case 1:  lines.append("**This week:** 1 session logged.")
        default: lines.append("**This week:** \(weeklyCount) sessions logged.")
        }
        lines.append("**Total logged (all time):** \(allSessions.count) sessions.\n")

        // Effort trend (only meaningful with ≥ 3 recent sessions)
        if summary.sessionCountLast7Days >= 3 {
            let trendLabel: String
            switch summary.effortTrend {
            case "improving":
                trendLabel = "trending upward — effort has been increasing. Keep the momentum."
            case "declining":
                trendLabel = "trending downward — intensity has dropped. Check if you're resting intentionally or losing motivation."
            default:
                trendLabel = "consistent — training intensity has been stable."
            }
            lines.append("**Effort trend:** \(trendLabel)\n")
        }

        // Drill variety
        if !summary.recentDrillNames.isEmpty {
            lines.append("**Recent focus:** \(summary.recentDrillNames.joined(separator: ", "))")
            if let repeated = summary.mostRepeatedDrill, summary.repetitionCount >= 2 {
                lines.append("You've done **\(repeated)** \(summary.repetitionCount)× this week — consider a variation or escalation.")
            }
            lines.append("")
        }

        // Recurring coaching patterns from conversation
        let topWeaknesses = recurringWeaknesses
            .sorted { $0.value > $1.value }
            .prefix(3)
            .filter { $0.value >= 2 }
        if !topWeaknesses.isEmpty {
            let areas = topWeaknesses.map { $0.key }.joined(separator: ", ")
            lines.append("**Coaching patterns:** You've been focused on **\(areas)** across multiple sessions.\n")
        }

        // Feedback quality (only show if there's enough signal)
        let totalFeedback = feedback.helpful + feedback.notHelpful
        if totalFeedback >= 3 {
            let ratio = feedback.helpful > 0
                ? Int(Double(feedback.helpful) / Double(totalFeedback) * 100)
                : 0
            if ratio >= 70 {
                lines.append("**Coaching feedback:** \(ratio)% of recent responses rated helpful — plans are landing well.\n")
            } else if ratio < 50 {
                lines.append("**Coaching feedback:** Under 50% of recent responses rated helpful — let me know what's missing and I'll adjust.\n")
            }
        }

        lines.append("Want me to build a session based on this? Tell me how much time you have.")

        let suggested: [String]
        if weeklyCount == 0 {
            suggested = ["Build me a session", "What should I work on?", "Start fresh this week"]
        } else if summary.effortTrend == "declining" {
            suggested = ["Build me an intense session", "What should I focus on?", "Help me get back on track"]
        } else {
            suggested = ["Build me a session", "What are my weaknesses?", "Give me a harder workout"]
        }

        return (lines.joined(separator: "\n"), suggested)
    }

    /// Validates that time block minutes sum to within tolerance of the requested duration.
    ///
    /// If the discrepancy exceeds 5 minutes, the largest non-warmup/cooldown block is
    /// corrected conservatively (minimum 5 min per block). Telemetry is logged for each correction.
    ///
    /// - Parameters:
    ///   - blocks: The time blocks to validate and potentially correct (mutated in-place).
    ///   - requestedMinutes: The user's requested session duration.
    private func validateTimeBudget(blocks: inout [TimeBlock], requestedMinutes: Int) {
        let actual = blocks.reduce(0) { $0 + $1.minutes }
        let discrepancy = actual - requestedMinutes

        // Tighter tolerance for short sessions: 3 min for ≤25 min, 5 min for longer.
        let tolerance = requestedMinutes <= 25 ? 3 : 5
        guard abs(discrepancy) > tolerance else { return }  // Within tolerance — no action

        // Log the discrepancy for telemetry (silent in production, visible in debug)
        CoachTelemetry.recordPrePipelineIntent(
            bucket: "time_budget_corrected",
            sport: sport
        )
        #if DEBUG
        print("⏱ [TimeBudget] Requested \(requestedMinutes) min, got \(actual) min (Δ\(discrepancy)). Correcting largest work block.")
        #endif

        // Find the largest non-structural block (not warmup or cooldown) to adjust
        let adjustableTypes: Set<String> = ["primary", "secondary", "transfer"]
        guard let idx = blocks.indices.max(by: { i, j in
            let iAdjustable = adjustableTypes.contains(blocks[i].blockType)
            let jAdjustable = adjustableTypes.contains(blocks[j].blockType)
            if iAdjustable != jAdjustable { return !iAdjustable }  // adjustable wins
            return blocks[i].minutes < blocks[j].minutes
        }), adjustableTypes.contains(blocks[idx].blockType) else { return }

        let corrected = max(5, blocks[idx].minutes - discrepancy)
        blocks[idx] = TimeBlock(
            name: blocks[idx].name,
            minutes: corrected,
            blockType: blocks[idx].blockType
        )
    }

    /// Generate a 4-day sport-specific schedule using the local pipeline.
    private func buildLocalScheduleResponse(focusAreas: [FocusArea], sessionMins: Int, specificityMode: SpecificityMode = .standard) -> CoachMessageResponse {
        let warmup   = max(5, sessionMins / 10)
        let cooldown = 5
        let workMins = max(0, sessionMins - warmup - cooldown)
        let days = ["Day 1", "Day 2", "Day 3", "Day 4"]
        var lines: [String] = ["Here's your \(sport.rawValue) training schedule:\n"]
        for (i, day) in days.enumerated() {
            let focusIndex = i % max(1, focusAreas.count)
            let dayFocus   = focusAreas.count > focusIndex ? focusAreas[focusIndex].name : "\(sport.rawValue) fundamentals"
            lines.append("**\(day) — \(dayFocus.capitalized)** (\(sessionMins) min)")
            lines.append("  Warmup (\(warmup) min): Dynamic \(sport.rawValue) movement + activation")
            if specificityMode == .high {
                let drills = localDetailedDrillsForFocusArea(name: dayFocus)
                for drill in drills.prefix(2) {
                    lines.append(drill)
                }
            } else {
                let drills    = localDrillsForFocusArea(name: dayFocus)
                let drillMins = max(3, workMins / max(1, min(3, drills.count)))
                for drill in drills.prefix(3) {
                    lines.append("  • \(drill)  [\(drillMins) min]")
                }
            }
            lines.append("  Cooldown (\(cooldown) min): Static stretch + breathing\n")
        }
        lines.append("Log each session in the Train tab to track your progress!")
        return CoachMessageResponse(
            response: lines.joined(separator: "\n"),
            suggestedActions: ["Open Train section", "Log session when done"],
            tone: "motivating",
            followUpQuestions: ["Which day do you want to start with?"],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Generate a single structured session using the local pipeline.
    private func buildLocalSessionResponse(focusAreas: [FocusArea], blocks: [TimeBlock], totalMins: Int, specificityMode: SpecificityMode = .standard) -> CoachMessageResponse {
        var lines: [String] = ["Here's your \(totalMins)-min \(sport.rawValue) session:\n"]
        for block in blocks {
            switch block.blockType {
            case "warmup":
                lines.append("**Warmup (\(block.minutes) min)**")
                lines.append("  • Dynamic \(sport.rawValue) movement + muscle activation")
            case "cooldown":
                lines.append("**Cooldown (\(block.minutes) min)**")
                lines.append("  • Static stretch targeting today's muscle groups")
            case "transfer":
                lines.append("**Game Transfer (\(block.minutes) min)**")
                lines.append("  • Apply today's skills at game speed — full intensity, no pauses")
            default:
                lines.append("**\(block.name.capitalized) (\(block.minutes) min)**")
                if specificityMode == .high {
                    let drills = localDetailedDrillsForFocusArea(name: block.name)
                    for drill in drills.prefix(2) {
                        lines.append(drill)
                    }
                } else {
                    let drills   = localDrillsForFocusArea(name: block.name)
                    let perDrill = max(2, block.minutes / max(1, min(3, drills.count)))
                    for drill in drills.prefix(3) {
                        lines.append("  • \(drill)  [\(perDrill) min]")
                    }
                }
            }
            lines.append("")
        }
        lines.append("💡 Focus on quality reps over speed. Log this session when done!")
        return CoachMessageResponse(
            response: lines.joined(separator: "\n"),
            suggestedActions: ["Start Timer", "Log This Session"],
            tone: "motivating",
            followUpQuestions: ["How did the session feel?"],
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Returns specific, named drills for a focus area name — sport-isolated.
    /// Never leaks drills from another sport. Falls back to sport fundamentals if no match.
    private func localDrillsForFocusArea(name: String) -> [String] {
        let key = name.lowercased()
        switch sport {
        case .basketball:
            let map: [String: [String]] = [
                "left hand dribbling":  ["Figure-8s left hand only: 3×1 min", "Left-hand cone weave: 3×30m", "Weak-hand stationary pound: 3×30s"],
                "weak-hand work":       ["Non-dominant cone dribble: 3×1 min", "Weak-hand layups: 3×10", "Alternate-hand ball series: 2 min"],
                "shooting":             ["Form shooting 5 spots: 20 makes each", "Catch-and-shoot off dribble: 3×15", "Free throws: 30 makes"],
                "free throw shooting":  ["Free throw routine: 50 makes", "Pressure 2-miss-2 drill: 5 sets", "Eyes-closed FT: 10 reps"],
                "layup finishing":      ["Mikan drill: 3×20", "Euro-step layup: 3×10 each side", "Floater off the drive: 3×10"],
                "ball handling":        ["Spider dribble: 3×1 min", "Two-ball pound: 3×30s", "Between-legs–behind-back combo: 3×1 min"],
                "crossover dribbling":  ["Stationary crossover: 3×1 min", "Full-speed crossover attack: 3×10", "Crossover into hesitation: 3×8"],
                "footwork":             ["Mikan footwork pattern: 3×20", "Pivot series front/reverse: 3×10 each", "Jab-step attack: 3×10"],
                "post moves":           ["Drop-step baseline: 3×10", "Hook shot series: 3×10 each hand", "Up-and-under finish: 3×8 each side"],
                "passing":              ["Wall-pass accuracy: 50 reps each hand", "Two-man moving pass: 3×2 min", "Skip-pass decision: 3×10"],
                "pivot footwork":       ["Front pivot series: 3×10 each foot", "Reverse pivot attack: 3×10", "Jab-step pivot combo: 3×10"],
                "finishing at the rim": ["Mikan drill: 3×20", "Contact layup through traffic: 3×10", "Reverse layup series: 3×10"],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return ["Ball handling warm-up: 3×1 min", "Full-court dribble series: 4 runs", "Shooting form 5 spots: 10 makes each"]

        case .football:
            let map: [String: [String]] = [
                "route running":         ["Stem-and-break: 4 routes × 5 reps", "Comeback route precision: 3×8", "In/out at game speed: 3×6 each"],
                "catching":              ["Tennis-ball drop catches: 3×20", "High/low catch ladder: 3×10", "One-hand concentration: 3×12 each"],
                "blocking":              ["Pad-level stance hold: 3×30s", "Drive-block footwork: 3×10 each side", "Pass-pro anchor: 3×5 reps"],
                "first-step explosion":  ["Resistance band hip drive: 3×10", "3-point stance get-off: 6×10m", "Cone reaction starts: 5×10m"],
                "acceleration training": ["10-yard burst: 6 reps", "Flying 20s: 4 reps", "Pro-agility shuttle: 5 reps"],
                "release technique":     ["Release off jam: 3×10 each side", "Stack release: 3×8", "Swim-move release: 3×10"],
                "footwork":              ["Ladder pattern: 3×1 min", "Shuffle-and-sprint: 5×10m", "Three-cone drill: 5 reps"],
                "coverage reads":        ["Zone drop read: 3×5 reps", "Man-coverage mirror: 3×1 min", "Intercept timing: 3×8 reps"],
                "agility training":      ["Pro-agility shuttle: 5 reps", "L-drill: 5 reps", "T-drill cone: 5 reps"],
                "pass rush":             ["Swim-move hand drill: 3×10", "Speed-rush get-off: 6×10m", "Bull-rush anchor: 3×5 reps"],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return ["Route running warm-up: 3×5 routes", "Footwork ladder: 3×1 min", "Catch-and-secure: 3×15"]

        case .soccer:
            let map: [String: [String]] = [
                "first touch":           ["Wall-pass first touch: 50 reps each foot", "Bouncing ball chest control: 3×15", "Moving first-touch cone drill: 3×1 min"],
                "finishing":             ["Shots edge of box: 25 reps", "One-touch finish in box: 3×10", "Volley finish off cross: 3×10"],
                "dribbling":             ["Cone weave both feet: 3×1 min each", "1v1 dribbling box: 4×2 min", "Maradona turn: 3×10 each way"],
                "shooting":              ["Driven shot from 20m: 25 reps", "Curling shot far post: 3×10", "Chip/lob finish: 3×8"],
                "passing":               ["Wall-pass accuracy: 50 reps each foot", "Triangle passing combo: 3×5 min", "Switch-field long ball: 3×10 each"],
                "heading":               ["Stationary header: 3×15", "Jumping header approach: 3×10", "Defensive header clearance: 3×10"],
                "defending":             ["Jockeying drill: 3×1 min", "Tackle timing 1v1: 3×5 reps", "Defensive shape slides: 3×30s"],
                "footwork":              ["Ladder footwork: 3×1 min", "Cone agility grid: 4×30s", "Directional change drill: 3×10"],
                "crossing":              ["Whipped cross from byline: 20 reps each side", "Driven low cross: 3×10", "Cutback cross to far post: 3×10"],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return ["Ball juggling warm-up: 3 min", "Cone dribbling: 3×1 min each foot", "Finishing drill: 20 shots"]

        case .tennis:
            let map: [String: [String]] = [
                "serve":              ["Flat first-serve placement: 30 reps", "Kick-serve spin: 20 reps", "T + wide alternation: 3×10"],
                "forehand":           ["Cross-court topspin rally: 3×5 min", "Inside-out forehand: 3×15", "Running forehand finish: 3×10"],
                "backhand":           ["Backhand cross-court rally: 3×5 min", "Two-handed passing: 3×10", "Slice backhand approach: 3×10"],
                "volley":             ["Punch volley series: 3×15 each side", "Drop volley precision: 3×10", "Approach + volley combo: 3×10"],
                "footwork":           ["Split-step reaction: 3×1 min", "Cone sprint to baseline: 5×10m", "Ladder agility: 3×1 min"],
                "return of serve":    ["Return drives down-the-line: 3×15", "Cross-court chip return: 3×10", "Aggressive block return: 3×10"],
                "topspin":            ["Heavy-topspin rally: 3×5 min", "Looping topspin over net: 3×15", "Topspin passing shot: 3×10"],
                "drop shot":          ["Feather drop shot: 3×15", "Approach-and-drop combo: 3×10", "Cross-court drop shot: 3×10"],
                "net game":           ["Volley exchange at net: 3×5 min", "Half-volley pickup: 3×15", "Approach-shot + overhead: 3×10"],
                "overhead":           ["Overhead smash series: 3×15", "Lob-and-smash: 3×10", "Jumping overhead: 3×8"],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return ["Mini-tennis warm-up: 3 min", "Groundstroke consistency: 3×5 min", "Serve practice: 30 reps"]
        }
    }

    /// Returns full 7-component drill breakdowns for HIGH specificity mode.
    ///
    /// Each entry follows the mandatory format:
    ///   **Name** / Setup / Action / Sets × Reps or Time / Rest / Coaching cue
    ///
    /// Falls back to `expandDrillToStructured()` for areas not in the detailed map so the
    /// local path never silently delivers compact one-liners when HIGH mode was requested.
    private func localDetailedDrillsForFocusArea(name: String) -> [String] {
        let key = name.lowercased()

        switch sport {
        case .basketball:
            let map: [String: [String]] = [
                "left hand dribbling": [
                    "**Figure-8 Left-Only Dribble**\n- Setup: Stand in the key, feet shoulder-width, right hand behind your back\n- Action: Dribble in a continuous figure-8 pattern around both legs using the left hand only. Keep dribbles at waist height.\n- Sets × Time: 3 sets × 60 seconds\n- Rest: 20 seconds between sets\n- Cue: \"Keep the ball at hip height — if it bounces above your waist, slow down until it's consistent\"",
                    "**Weak-Hand Cone Weave**\n- Setup: 5 cones in a straight line, 2 feet apart. Left hand only, right hand behind your back.\n- Action: Dribble through all 5 cones and back at increasing speed, never switching hands. Down-and-back = 1 rep.\n- Sets × Reps: 4 sets × 4 reps\n- Rest: 30 seconds between sets\n- Cue: \"Push through the cone, don't redirect around it — attack the next space\""
                ],
                "shooting": [
                    "**Form Shooting — 5-Spot Makes Circuit**\n- Setup: 5 spots within 8 feet of the basket (both blocks, both elbows, top of key)\n- Action: Shoot 10 MAKES from each spot before moving. Perfect form: 1-2 motion, elbow under ball, follow-through held until ball hits rim.\n- Sets × Makes: 1 round of 50 total makes (10 per spot)\n- Rest: No rest — move to next spot on each make\n- Cue: \"Hold your follow-through until the net moves — every single rep\"",
                    "**Catch-and-Shoot Off Two Dribbles**\n- Setup: Start at the three-point line with a partner or rebounder at the basket\n- Action: Two dribbles right → plant → shoot. Catch the pass back, two dribbles left → plant → shoot. Alternate each rep.\n- Sets × Makes: 3 sets × 15 makes per side\n- Rest: 45 seconds between sets\n- Cue: \"Your feet set BEFORE the ball reaches your hands — early footwork, late catch\""
                ],
                "ball handling": [
                    "**Spider Dribble**\n- Setup: Standing, ball in front between your feet, eyes up\n- Action: Right hand taps the ball in front right, left hand taps in front left, right hand taps behind right, left hand behind left — continuously like a spider. Never let it stop.\n- Sets × Time: 3 sets × 90 seconds\n- Rest: 20 seconds between sets\n- Cue: \"You should be able to name someone across the gym — if you're staring at the ball you're not ready to use this in a game\"",
                    "**Two-Ball Simultaneous Pound**\n- Setup: Two basketballs, solid athletic stance\n- Action: Phase 1 — both balls at same time × 30s. Phase 2 — alternate (one up, one down) × 30s. Phase 3 — offset (each ball half-phase apart) × 30s.\n- Sets × Time: 3 sets × 90 seconds (all 3 phases)\n- Rest: 30 seconds between sets\n- Cue: \"Lock your core — movement comes from your wrists and fingers, not your whole torso\""
                ],
                "footwork": [
                    "**Mikan Footwork Pattern**\n- Setup: 2 feet from the basket on the left block, no dribble\n- Action: Step-step layup off left foot right side → land → step-step layup off right foot left side. Alternate continuously with no pause.\n- Sets × Makes: 3 sets × 20 makes (10 each side)\n- Rest: 30 seconds between sets\n- Cue: \"Land soft, step immediately — zero pause between landing and your next step\"",
                    "**Jab-Step Attack Series**\n- Setup: Triple threat position at the elbow, cone or partner at the rim\n- Action: Strong jab right → 1-second pause → crossover drive left. Then: jab left → pause → crossover right. Alternate each rep.\n- Sets × Reps: 3 sets × 10 reps each direction\n- Rest: 45 seconds between sets\n- Cue: \"Make the defender respect the jab before you go — stab the floor, not the air\""
                ],
                "layup finishing": [
                    "**Mikan Drill**\n- Setup: Under the basket, no dribble\n- Action: Alternate underhand layups on each side of the basket using the inside hand. Step → reach → soft touch — never let the ball hit the floor.\n- Sets × Makes: 3 sets × 20 makes (10 each side)\n- Rest: 30 seconds between sets\n- Cue: \"Shoot off the backboard with a soft touch — power finishers miss; control finishers score\"",
                    "**Euro-Step Layup**\n- Setup: Start at half court, cone at the three-point line to trigger the step\n- Action: Drive hard at the cone → long first step right → second step left (or vice versa) → finish with the inside hand. Full speed.\n- Sets × Reps: 3 sets × 10 reps each direction\n- Rest: 40 seconds between sets\n- Cue: \"The second step is your planting foot — it needs to be decisive, not tentative\""
                ],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return localDrillsForFocusArea(name: name).map { expandDrillToStructured($0) }

        case .football:
            let map: [String: [String]] = [
                "route running": [
                    "**Stem-and-Break Precision Route**\n- Setup: Cone at 5 yards for the stem, break marker at 10 yards. Align at the line of scrimmage.\n- Action: Explode off the line, run a straight 5-yard stem, plant hard on the outside foot, break 90° at the marker. Call your route (in/out/comeback) before each rep.\n- Sets × Reps: 4 sets × 5 reps per route (3 routes × 5 = 15 reps per set)\n- Rest: 30 seconds between reps, 60 seconds between sets\n- Cue: \"Your plant foot is your money — drive the outside edge into the ground, don't just turn\"",
                    "**Release-and-Accelerate**\n- Setup: A partner provides a light press jam at the line of scrimmage\n- Action: Beat the jam with swim, rip, or push technique → immediately accelerate to full speed for 15 yards → finish with a precise route.\n- Sets × Reps: 3 sets × 6 reps per release technique (18 reps per set)\n- Rest: 45 seconds between reps\n- Cue: \"Win the release and GO — don't check to see if you beat the jam, just run\""
                ],
                "catching": [
                    "**Tennis Ball Drop Catch**\n- Setup: Partner on an elevated surface holds two tennis balls at shoulder height. Vary height and direction each rep.\n- Action: Partner drops one ball at random timing. Catch it before the second bounce using soft hands — do NOT trap it against your body.\n- Sets × Reps: 3 sets × 20 catches (mix high/low/left/right)\n- Rest: 20 seconds between sets\n- Cue: \"Reach for the ball — your hands lead, your feet follow\"",
                    "**High/Low Catch Ladder**\n- Setup: Partner throws from 10 yards — alternate between chest-high, knee-high, and overhead throws each rep\n- Action: Catch using correct hand position (thumbs in for below waist, thumbs out for above chest). Simulate securing against a hit after each catch.\n- Sets × Reps: 3 sets × 30 total catches (10 per height)\n- Rest: 45 seconds between sets\n- Cue: \"Thumbs toward each other below your waist, little fingers together above your chest — learn it by feel, not by thinking\""
                ],
                "first-step explosion": [
                    "**Resistance Band Hip Drive**\n- Setup: Mini band around both ankles, athletic stance, 10-yard cone directly ahead\n- Action: Drive off your back foot with maximum hip extension — knee up and through — and sprint the full 10 yards against band resistance. Walk back slowly.\n- Sets × Reps: 3 sets × 10 reps (alternate lead foot)\n- Rest: 45 seconds between sets\n- Cue: \"Drive your knee up and through, not out — the band is your feedback that your hips are working\"",
                    "**3-Point Stance Get-Off**\n- Setup: Full 3-point stance at the line, cone at 10 yards, partner timing your burst\n- Action: Explode on the count. First two steps: short, powerful, on the balls of your feet. Measure your 10-yard time each rep.\n- Sets × Reps: 6 sets × 3 reps (full recovery between sets)\n- Rest: 60 seconds between sets\n- Cue: \"First step goes DOWN into the ground, not forward — short and explosive beats long and slow every time\""
                ],
                "pass rush": [
                    "**Swim-Move Hand Speed**\n- Setup: A partner holds a blocking pad. Start in a speed rush stance 3 yards out.\n- Action: First-step explosion → contact pad → rip one arm up and over (swim) to clear the blocker → burst to the quarterback cone 5 yards behind.\n- Sets × Reps: 3 sets × 10 reps (alternate swim arm each rep)\n- Rest: 40 seconds between sets\n- Cue: \"Dip your inside shoulder as you swim — staying upright kills the move\"",
                    "**Speed Rush Get-Off**\n- Setup: 3-point stance, cone at 10 yards around the outside edge, QB cone 5 yards behind the cone\n- Action: Pure speed rush: first step wide and flat, stay low, bend around the edge, close to the QB cone. No contact — pure angle and bend work.\n- Sets × Reps: 6 sets × 10-yard reps\n- Rest: 45 seconds between reps\n- Cue: \"Lean into the arc like a motorcycle — if you're upright in the bend you're losing half your speed\""
                ],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return localDrillsForFocusArea(name: name).map { expandDrillToStructured($0) }

        case .soccer:
            let map: [String: [String]] = [
                "first touch": [
                    "**Wall-Pass First Touch Isolation**\n- Setup: 5 feet from a flat wall, markers for a 2×2-foot target zone beside your standing foot\n- Action: Pass the ball firmly to the wall at knee height; as it returns, dead the ball inside the target zone using the inside of your foot. Alternate feet each rep.\n- Sets × Reps: 3 sets × 25 touches per foot (50 per set)\n- Rest: 30 seconds between sets\n- Cue: \"Touch the ball, don't stop it — your foot meets it soft and already moving in the new direction\"",
                    "**Moving First-Touch Cone Gate**\n- Setup: 4 cones in a square 6 yards apart. Partner passes from 12 yards. You start outside the square.\n- Action: Move through any gate, receive on the move with your first touch redirecting toward the next gate, and pass back. Change entry gate every rep.\n- Sets × Time: 4 sets × 2 minutes continuous\n- Rest: 45 seconds between sets\n- Cue: \"Point your chest to where you want the ball to go on your touch — your body angle IS the direction\""
                ],
                "finishing": [
                    "**Power Shots Edge of Box**\n- Setup: 20 balls at the top of the 18, targets (cones/towels) in both lower corners\n- Action: Plant foot beside the ball, drive through center with laces, follow through to target corner. Call your corner before each shot. Alternate left/right corner.\n- Sets × Reps: 5 sets × 5 shots (25 total)\n- Rest: 30 seconds between sets\n- Cue: \"Eyes on the ball through contact — you look at the corner AFTER the foot has already passed through\"",
                    "**One-Touch Box Finish**\n- Setup: Partner serves low balls into the 6-yard box. You start 5 yards out, moving to meet the service.\n- Action: Arrive before the ball and finish first-time without controlling it first. Vary the cross angle each time. Alternate feet.\n- Sets × Reps: 3 sets × 10 finishes (5 per foot)\n- Rest: 40 seconds between sets\n- Cue: \"Get your body in line with the cross early — the finish is easy if your position is right\""
                ],
                "dribbling": [
                    "**Cone Weave — Foot Isolation**\n- Setup: 6 cones in a straight line, 2 feet apart\n- Action: Weave through the full line using only the inside and outside of one foot. Down left foot only → back right foot only → down alternating. 3 passes = 1 set.\n- Sets × Reps: 3 sets × 3 passes through the full line\n- Rest: 30 seconds between sets\n- Cue: \"Small touches — the ball should never be more than 18 inches from your foot between cones\"",
                    "**1v1 Escape Box**\n- Setup: 6×6 yard box with a partner defending. Goal: dribble out past the defender.\n- Action: Use body feints, change of pace, or directional change to beat the defender and exit the box. Reset on turnover.\n- Sets × Time: 4 sets × 2 minutes (switch roles every 2 min)\n- Rest: 45 seconds between sets\n- Cue: \"Look at the defender's hips, not their feet — hips commit first\""
                ],
                "shooting": [
                    "**Driven Shot from Distance**\n- Setup: 20 balls at the 20-meter mark, keeper or visual target in goal\n- Action: Approach at a slight angle, plant foot 6 inches beside the ball, lock your ankle, drive through center with the laces, stay over the ball to keep it low.\n- Sets × Reps: 4 sets × 5 shots per foot (40 total)\n- Rest: 30 seconds between sets\n- Cue: \"Stay over the ball — lean back even slightly and it goes over the bar\"",
                    "**Curling Shot Far Post**\n- Setup: Start from a wide angle, 15-18 meters out\n- Action: Wrap the inside of your foot around the outside of the ball, follow through across your body. Aim to bend it around a cone placed 10 meters away.\n- Sets × Reps: 3 sets × 10 reps per foot\n- Rest: 40 seconds between sets\n- Cue: \"Strike the outside half of the ball — if you're hitting the center you get power but not curve\""
                ],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return localDrillsForFocusArea(name: name).map { expandDrillToStructured($0) }

        case .tennis:
            let map: [String: [String]] = [
                "serve": [
                    "**Flat First-Serve Placement**\n- Setup: Full court, towel or cone targets in the T and wide positions in each service box\n- Action: Toss to 1 o'clock, pronate through the hit, drive flat to your called target. Call T or wide before every serve.\n- Sets × Reps: 3 sets × 20 serves (10 to T, 10 wide per set)\n- Rest: 30 seconds between sets\n- Cue: \"Feel the racket face snap upward — pronation finishes the serve, not your arm pulling across\"",
                    "**Kick-Serve Spin Drill**\n- Setup: Full court, deuce and ad service boxes\n- Action: Toss slightly behind your head at 12 o'clock, brush sharply from 7 to 1 on the ball, follow through across your body. Focus exclusively on spin — forget pace.\n- Sets × Reps: 3 sets × 10 kick serves (5 deuce, 5 ad)\n- Rest: 45 seconds between sets\n- Cue: \"Hit UP on the ball, not at it — you're brushing the back, not driving through\""
                ],
                "forehand": [
                    "**Cross-Court Topspin Baseline Rally**\n- Setup: Both players at baseline, cross-court only. Target: 10 consecutive shots before either player misses.\n- Action: Full eastern/semi-western grip, finish with racket over opposite shoulder. Brush 7-to-1 on the ball for heavy topspin. Stay 3 feet behind the baseline.\n- Sets × Time: 3 sets × 5 minutes continuous rally\n- Rest: 60 seconds between sets\n- Cue: \"Swing from your hip, not your shoulder — hip rotation generates the power, the arm just follows\"",
                    "**Inside-Out Forehand Attack**\n- Setup: Coach or partner feeds to your ad side. You circle around and hit inside-out cross-court.\n- Action: Slide left to get fully behind the ball, open your stance completely, rip forehand to the deuce corner. Recover to center immediately after.\n- Sets × Reps: 3 sets × 15 balls\n- Rest: 45 seconds between sets\n- Cue: \"Open your hips fully before you swing — chest still facing the net at contact = lost power\""
                ],
                "footwork": [
                    "**Split-Step Reaction**\n- Setup: On the baseline. Partner at the net points left or right at random timing.\n- Action: As partner signals (simulating opponent contact), execute a loaded split-step hop landing on both feet. Explode to the indicated side, reach the simulated ball position, shadow swing, recover to center.\n- Sets × Time: 3 sets × 90 seconds continuous\n- Rest: 45 seconds between sets\n- Cue: \"Land when the opponent's racket hits — too early or too late and it's useless, timing is everything\"",
                    "**Spider Court Sprint**\n- Setup: 5 cones: center, both sidelines at service line, both baseline corners\n- Action: Sprint from center to each cone and back, touching it. Full shuffle — no crossing feet. Complete all 5 cones = 1 rep.\n- Sets × Reps: 5 sets × full spider pattern\n- Rest: 60 seconds between sets\n- Cue: \"Stay low through every direction change — straightening up between cones costs you a full step each time\""
                ],
                "backhand": [
                    "**Cross-Court Backhand Consistency Rally**\n- Setup: Both players at baseline, backhand cross-court only. Target: 8 consecutive shots.\n- Action: Full unit turn, two-handed finish for topspin or one-handed slice for approach. Stay in the rally until you reach 8.\n- Sets × Time: 3 sets × 5 minutes\n- Rest: 60 seconds between sets\n- Cue: \"Turn your whole upper body on the backswing — arms alone produce a weak shot\"",
                    "**Slice Backhand Approach**\n- Setup: Coach feeds short balls to the backhand side\n- Action: Move forward to the short ball, hit a low slicing backhand approach down the line, follow it to net position.\n- Sets × Reps: 3 sets × 10 approaches\n- Rest: 40 seconds between sets\n- Cue: \"Cut DOWN and through the back of the ball — a slice that bounces up is just a sitter for your opponent\""
                ],
                "volley": [
                    "**Punch Volley Series**\n- Setup: At the net, partner feeds at medium pace from the service line\n- Action: Short backswing — racket in front at all times. Punch volley to targets in the service box using both forehand and backhand sides. No swing.\n- Sets × Reps: 3 sets × 15 volleys per side (30 per set)\n- Rest: 30 seconds between sets\n- Cue: \"Meet the ball in FRONT of your body — if it gets beside you the volley goes in the net\"",
                    "**Approach Shot + Volley Combo**\n- Setup: Coach feeds a mid-court ball, then feeds a passing-shot attempt after your approach\n- Action: Drive approach shot deep cross-court, split-step at the service line, close to net, and volley the incoming pass away.\n- Sets × Reps: 3 sets × 10 combos\n- Rest: 45 seconds between sets\n- Cue: \"Your split step happens when the ball bounces off your approach — don't keep running forward, read first\""
                ],
            ]
            if let d = map[key] ?? map.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value { return d }
            return localDrillsForFocusArea(name: name).map { expandDrillToStructured($0) }
        }
    }

    /// Expands a compact drill string (e.g. "Figure-8s left hand only: 3×1 min") into a
    /// best-effort 7-component structure. Used when a focus area has no detailed map entry
    /// in `localDetailedDrillsForFocusArea` so the local HIGH-mode path never silently
    /// delivers one-liners.
    private func expandDrillToStructured(_ compact: String) -> String {
        let parts = compact.components(separatedBy: ": ")
        let name  = parts.first?.trimmingCharacters(in: .whitespaces) ?? compact
        print("📋 [LocalDrills] expandDrillToStructured() fallback invoked for '\(name)' (\(sport.rawValue)) — no detailed map entry")
        let prescription = parts.count > 1 ? parts.dropFirst().joined(separator: ": ") : "3 sets"
        let setsReps = prescription.contains("×") || prescription.lowercased().contains("min") ? prescription : "3 sets × \(prescription)"
        return "**\(name)**\n- Setup: \(sport.rawValue.capitalized) training area, clear space\n- Action: Perform the drill at moderate intensity with controlled technique — quality over speed\n- Sets × Reps/Time: \(setsReps)\n- Rest: 30 seconds between sets\n- Cue: \"Consistent technique every rep — own it before you try to speed it up\""
    }

    /// Handle failure with honest, actionable error state
    private func handleFailure(_ errorKind: AICoachErrorKind, userMessage: String) {
        let errorMessage: AICoachMessage
        
        switch errorKind {
        case .noConnection:
            errorState = .noConnection
            errorMessage = AICoachMessage(
                content: "No internet connection. Please check your network and try again.",
                isUser: false,
                tone: "error"
            )
            
        case .backendDown:
            errorState = .backendDown
            errorMessage = AICoachMessage(
                content: "The coaching service is unavailable right now. Try again shortly.",
                isUser: false,
                tone: "error"
            )
            
        case .endpointNotFound:
            errorState = .backendDown
            errorMessage = AICoachMessage(
                content: "The coaching service isn't responding right now. Try again in a moment.",
                isUser: false,
                tone: "error"
            )
            
        case .authFailure:
            errorState = .authRequired
            errorMessage = AICoachMessage(
                content: "Your session has expired. Please log out and log back in, then try again.",
                isUser: false,
                tone: "error"
            )
            
        case .premiumRequired:
            errorState = .premiumRequired
            errorMessage = AICoachMessage(
                content: "AI Coach requires a Premium subscription. Upgrade to access personalized coaching.",
                isUser: false,
                tone: "error"
            )
            
        case .timeout:
            errorState = .timeout
            errorMessage = AICoachMessage(
                content: "The request timed out. The AI may be processing a complex query — please try again.",
                isUser: false,
                tone: "error"
            )
            
        case .serverError(let detail):
            errorState = .serverError
            errorMessage = AICoachMessage(
                content: "Server error: \(detail). Please try again in a moment.",
                isUser: false,
                tone: "error"
            )
            
        case .unknown(let detail):
            errorState = .serverError
            errorMessage = AICoachMessage(
                content: "Something went wrong: \(detail). Please try again.",
                isUser: false,
                tone: "error"
            )
        }
        
        messages.append(errorMessage)
        saveMessages()
    }
    
    /// Classify an error into actionable categories
    private func classifyError(_ error: Error) -> AICoachErrorKind {
        if let apiError = error as? APIError {
            switch apiError {
            case .noConnection:
                return .noConnection
            case .cannotConnectToHost, .dnsLookupFailed:
                return .backendDown
            case .notFound:
                return .endpointNotFound
            case .unauthorized:
                return .authFailure
            case .forbidden:
                return .premiumRequired
            case .timeout:
                return .timeout
            case .serverError(let msg):
                return .serverError(msg)
            case .networkError:
                return .backendDown
            default:
                return .unknown(apiError.errorDescription ?? "Unknown API error")
            }
        }
        
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return .noConnection
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return .backendDown
        case NSURLErrorTimedOut:
            return .timeout
        default:
            return .unknown(error.localizedDescription)
        }
    }
    
    /// Retry the last failed user message
    func retryLastMessage() async {
        // Find the last user message
        guard let lastUserMessage = messages.last(where: { $0.isUser }) else { return }
        
        // Remove any error messages that came after the last user message
        if let lastUserIndex = messages.lastIndex(where: { $0.isUser }) {
            messages = Array(messages.prefix(through: lastUserIndex))
            saveMessages()
        }
        
        errorState = nil
        isLoading = true

        let promptCtx = buildPromptContext(for: lastUserMessage.content)
        let apiClient = APIClient.shared

        let result = await attemptSendMessage(
            apiClient:  apiClient,
            content:    lastUserMessage.content,
            context:    promptCtx.apiContext,
            history:    promptCtx.conversationHistory
        )

        switch result {
        case .success(let response):
            let formatted = ResponseFormatter.format(response, context: promptCtx, drillProvider: localDetailedDrillsForFocusArea)
            handleSuccessResponse(formatted, source: .backend)
        case .failure(let error):
            let errorKind = classifyError(error)
            if errorKind.isInfrastructureError {
                handleWithLocalCoaching(promptContext: promptCtx, failureReason: errorKind)
            } else {
                handleFailure(errorKind, userMessage: lastUserMessage.content)
            }
        }

        isLoading = false
    }
    
    func loadProactiveCheckin() async {
        guard messages.isEmpty else { return }
        
        do {
            let response = try await APIClient.shared.getProactiveCheckin(sport: sport)
            
            if response.hasMessage, let message = response.message {
                proactiveCheckin = message
            } else {
                proactiveCheckin = fallbackCoachQuestion()
            }
        } catch {
            print("[AI Coach] Checkin error (non-fatal): \(error)")
            proactiveCheckin = fallbackCoachQuestion()
        }
    }
    
    /// Load the onboarding survey for AI Coach context.
    /// Backend is authoritative; local cache (UserDefaults) is the fallback for offline use.
    /// On success, seeds recurringWeaknesses with critical skills (rated 1–3) so the
    /// prioritization engine has baseline signals from the very first message.
    func loadSurvey() async {
        // 1. Try backend first
        do {
            let response = try await APIClient.shared.getOnboardingSurvey()
            surveyResponse = response
            cacheSurveyLocally(response)
            seedRecurringWeaknessesFromSurvey(response)
            print("[AI Coach] Survey loaded from backend — \(response.skillRatings.count) skill ratings")
            return
        } catch {
            print("[AI Coach] Survey backend load failed (non-fatal): \(error)")
        }

        // 2. Fallback to local cache
        if let data = UserDefaults.standard.data(forKey: Self.surveyLocalKey),
           let cached = try? JSONDecoder().decode(OnboardingSurveyResponse.self, from: data) {
            surveyResponse = cached
            seedRecurringWeaknessesFromSurvey(cached)
            print("[AI Coach] Survey loaded from local cache")
        }
    }

    private func cacheSurveyLocally(_ response: OnboardingSurveyResponse) {
        if let data = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(data, forKey: Self.surveyLocalKey)
        }
        // 5D: Record the fetch date so deriveFocusAreasFromContext() can decay old survey influence.
        UserDefaults.standard.set(Date(), forKey: Self.surveyDateKey)
    }

    // MARK: - 5D: Survey Recency Multiplier

    // surveyRecencyMultiplier computation lives in the file-scope SurveyRecencyConfig enum
    // (above the ViewModel class definition) so it's accessible from both @MainActor code
    // and unit tests.  Call SurveyRecencyConfig.multiplier(ageInWeeks:) directly.

    /// Seeds recurringWeaknesses with critical-rated skills (1–3) so the prioritization
    /// engine has a non-zero starting signal for these areas from the first session.
    /// Uses count = 1 so survey signal is real but doesn't overpower actual conversation.
    private func seedRecurringWeaknessesFromSurvey(_ response: OnboardingSurveyResponse) {
        for (skill, rating) in response.skillRatings where rating <= 3 {
            let key = skill.lowercased()
            if recurringWeaknesses[key] == nil {
                recurringWeaknesses[key] = 1  // Survey baseline seed
            }
        }
        // Also add explicit weakness tags
        for weakness in response.weaknesses {
            let key = weakness.lowercased()
            if recurringWeaknesses[key] == nil {
                recurringWeaknesses[key] = 1
            }
        }
    }

    private func fallbackCoachQuestion() -> String {
        // If survey loaded, ask something specific to their critical skill gaps
        if let survey = surveyResponse {
            let critical = survey.skillRatings.filter { $0.value <= 3 }.keys.sorted()
            if let topGap = critical.first {
                return "I can see \(topGap) is something you want to build. What aspect of it feels hardest right now?"
            }
            if let firstWeakness = survey.weaknesses.first {
                return "You mentioned \(firstWeakness) as a challenge. What does that look like in a real game situation for you?"
            }
        }

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
        availableTimeMinutes = nil
        latestWeakness = nil
        athleticAttributes = []
        recurringWeaknesses = [:]
        errorState = nil
        saveMessages()
        saveContext()
        
        Task {
            try? await APIClient.shared.clearCoachConversation(sport: sport)
        }
    }
    
    // MARK: - Coaching Brief Construction
    // WeaknessType, WeaknessAnalysis, ProgressionStage, CoachPrioritization → AICoachReasoning.swift

    /// Delegates to AICoachReasoning.analyze() — sport context injected here.
    private func analyzeWeakness(concepts: [String], message: String, intent: String) -> WeaknessAnalysis? {
        AICoachReasoning.analyze(concepts: concepts, message: message, intent: intent, sport: sport)
    }



    // ── Multi-signal reasoning types ─────────────────────────────────────────────

    /// What kind of response the user is requesting.
    // Internal (not private) so OutputModeDetector tests can reference this type.
    enum OutputMode: String {
        case schedulePlan          = "schedule_plan"           // Multi-day training schedule (Day 1, Day 2, ...)
        case workoutPlan           = "workout_plan"            // Single session with named drills, sets/reps
        case explanation           = "explanation"             // Concept/why question — no full plan
        case hybrid                = "hybrid"                  // Explanation + session (both signals present)
        case guidance              = "guidance"                // Directional/advisory coaching question — brief + confirming question
        case coachingConversational = "coaching_conversational" // Vague coaching intent — sport-specific gathering question
    }

    /// A named training focus area extracted from the user's message.
    private struct FocusArea {
        let name: String        // Human-readable: "left hand dribbling", "athleticism"
        let concepts: [String]  // Semantic routing concepts: ["direct_skill", "technique"]
        let userWeight: Double  // Relative priority: 1.0 = primary, 0.70 = explicit secondary, 0.35 = supplementary
    }

    /// A time-allocated block within a session plan.
    private struct TimeBlock {
        let name: String
        let minutes: Int
        let blockType: String   // "warmup", "primary", "secondary", "transfer", "cooldown"
    }

    // MARK: - Specificity Mode

    /// Controls how detailed the drill output should be.
    ///
    /// Escalates to `.high` when the user says "specific drills", "more detail", "expand",
    /// "exactly", "break it down", etc. HIGH MODE requires every drill to include all 7
    /// components: name, setup, exact action, sets, reps/time, rest, and coaching cue.
    private enum SpecificityMode {
        case standard  // Named drills with sets × reps or duration (default)
        case high      // Full 7-component drill breakdown — no generic categories allowed

        static func detect(from message: String) -> SpecificityMode {
            let low = message.lowercased()
            let triggers = [
                "specific drill", "more detail", "exact drill", "expand",
                "break it down", "break down", "detailed", "full breakdown",
                "step by step", "step-by-step", "give me the full",
                "all the details", "precisely", "each drill", "every drill",
                "give me specific", "show me exactly", "go deeper"
            ]
            return triggers.contains(where: { low.contains($0) }) ? .high : .standard
        }

        var gptDirective: String {
            switch self {
            case .standard:
                return "DRILL SPECIFICITY: Name each drill explicitly with sets × reps or duration + rest. No generic category descriptions."
            case .high:
                return """
                SPECIFICITY MODE: HIGH — User explicitly requested specific/detailed drills.
                EVERY drill in your response MUST include ALL 7 components:
                1. Drill name — a real named drill, not a category
                2. Setup — exact position on court/field, equipment/cones needed
                3. Exact action — step-by-step what the athlete physically does
                4. Sets — specific number
                5. Reps or time — exact count or duration in seconds/minutes
                6. Rest — exact seconds between sets
                7. Coaching constraint — one specific technical cue (not generic)
                FORBIDDEN output: "ball handling work", "conditioning drills", "apply in game" — these are categories.
                REQUIRED: Every drill must be independently executable. Zero vague instructions.
                ESCALATION RULE: Do NOT repeat the structure from any prior response — increase precision.
                """
            }
        }
    }

    // MARK: - Coach Prompt Context (Typed Pipeline Object)

    /// The single typed context object assembled by buildPromptContext() and passed through
    /// all pipeline stages: Tool Decision → Model Reasoning → Response Formatter.
    ///
    /// Built ONCE per user message. Nothing is assembled inline during reasoning.
    private struct CoachPromptContext {
        let sport: Sport
        let userMessage: String
        let conversationHistory: [ConversationMessage]
        let inferredIntent: String
        let focusAreas: [FocusArea]
        let outputMode: OutputMode
        let specificityMode: SpecificityMode
        let availableTimeMinutes: Int
        let surveyData: OnboardingSurveyResponse?
        let readinessProfile: CoachReadinessProfile
        let recurringWeaknesses: [String: Int]
        let apiContext: CoachContext       // Sent to backend API
        let coachingBrief: String?         // Pre-assembled GPT brief (built inside apiContext)
    }

    // MARK: - Tool Decision Engine (Pipeline Stage 2)

    /// Decides if any tools are needed before model reasoning.
    /// Default is NONE — coaching context is self-contained via the coaching brief.
    /// Reserved for future drill library lookup and calculator integrations.
    private enum ToolPlan {
        case none          // Default: coaching brief is sufficient
        case docsSearch    // Future: live drill library API lookup
        case calculator    // Time/reps arithmetic (currently handled in buildTimeBlocks)

        static func decide(for context: CoachPromptContext) -> ToolPlan {
            // All required context (focus areas, time blocks, survey baseline, readiness)
            // is assembled in buildPromptContext(). No external tools needed for coaching.
            // Future: return .docsSearch when a live drill library is integrated.
            return .none
        }
    }

    // MARK: - Response Formatter (Pipeline Stage 4)

    /// Final validation and structure enforcement layer.
    /// EVERY response — GPT or local — passes through this before reaching the UI.
    ///
    /// Enforces:
    ///   • Drill specificity requirements when specificityMode = .high
    ///   • Multi-focus coverage check (all named areas present in response)
    ///   • Cross-sport drill contamination detection (logged, not blocked — GPT self-validates)
    ///   • Suggested actions alignment with output mode (log action for workout plans)
    private struct ResponseFormatter {

        /// `drillProvider`: optional closure that returns detailed 7-component drills for a focus
        /// area name. Pass `self.localDetailedDrillsForFocusArea` on GPT paths so the validator
        /// can repair a non-compliant GPT response. Leave nil on the local path (already guaranteed).
        static func format(
            _ response: CoachMessageResponse,
            context: CoachPromptContext,
            drillProvider: ((String) -> [String])? = nil
        ) -> CoachMessageResponse {
            var result = response

            // Sport correctness: detect cross-sport patterns (logged for observability)
            detectCrossSportContamination(in: result.response, sport: context.sport)

            // Multi-focus: verify all requested areas appear in the response
            if context.focusAreas.count > 1 {
                detectMissingFocusAreas(in: result.response, focusAreas: context.focusAreas)
            }

            // Specificity: validate all 7 components; repair using drillProvider if violation detected
            if context.specificityMode == .high {
                result = enforceHighSpecificity(result, context: context, drillProvider: drillProvider)
            }

            // Actions: guarantee at least one log/track action for workout-type responses
            result = alignActions(result, outputMode: context.outputMode)

            return result
        }

        // ── Cross-sport contamination detector ─────────────────────────────────────

        private static func detectCrossSportContamination(in text: String, sport: Sport) {
            let lower = text.lowercased()
            var forbidden: [(String, Sport)] = []
            switch sport {
            case .basketball:
                forbidden = [("route running", .football), ("penalty kick", .soccer),
                             ("baseline rally", .tennis), ("bicycle kick", .soccer)]
            case .football:
                forbidden = [("layup drill", .basketball), ("bicycle kick", .soccer),
                             ("split step", .tennis), ("free throw", .basketball)]
            case .soccer:
                forbidden = [("layup", .basketball), ("route running", .football),
                             ("serve practice", .tennis), ("crossover dribble", .basketball)]
            case .tennis:
                forbidden = [("crossover dribble", .basketball), ("route running", .football),
                             ("penalty kick", .soccer), ("post move", .basketball)]
            }
            for (pattern, src) in forbidden where lower.contains(pattern) {
                print("⚠️ [Formatter] Cross-sport pattern '\(pattern)' (\(src.rawValue)) detected in \(sport.rawValue) response")
            }
        }

        // ── Multi-focus coverage check ───────────────────────────────────────────────

        private static func detectMissingFocusAreas(in text: String, focusAreas: [FocusArea]) {
            let lower = text.lowercased()
            for area in focusAreas {
                guard area.name.count >= 5 else { continue }
                let key = String(area.name.lowercased().prefix(6))
                if !lower.contains(key) {
                    print("⚠️ [Formatter] Focus area '\(area.name)' may be missing in response")
                }
            }
        }

        // ── High-specificity structure validator ─────────────────────────────────────
        //
        // VALIDATOR RULES (non-negotiable):
        //   • Checks all 7 required components per HIGH mode contract
        //   • NEVER prepends headers to mask weak content
        //   • NEVER returns fake structure
        //   • Logs violations for observability
        //   • Returns response unchanged — correction happens upstream (in local pipeline)
        //     not here, because the formatter has no access to drill sources or sport context

        private static func enforceHighSpecificity(
            _ response: CoachMessageResponse,
            context: CoachPromptContext,
            drillProvider: ((String) -> [String])? = nil
        ) -> CoachMessageResponse {
            let lower = response.response.lowercased()

            // Validate each of the 7 required components
            let hasName    = lower.contains("**")
            let hasSetup   = lower.contains("setup")
            let hasAction  = lower.contains("action")
            let hasSets    = lower.contains("sets") || lower.contains("set:")
            let hasReps    = lower.contains("reps") || lower.contains("× time")
                          || lower.contains("seconds") || lower.contains("minutes")
            let hasRest    = lower.contains("rest")
            let hasCue     = lower.contains("cue") || lower.contains("coaching cue")

            let missing = [
                hasName   ? nil : "name (bold)",
                hasSetup  ? nil : "setup",
                hasAction ? nil : "action",
                hasSets   ? nil : "sets",
                hasReps   ? nil : "reps/time",
                hasRest   ? nil : "rest",
                hasCue    ? nil : "coaching cue"
            ].compactMap { $0 }

            guard !missing.isEmpty else {
                print("✅ [Formatter] HIGH specificity validation PASSED — all 7 components present")
                return response
            }

            // Violation detected — log it
            print("⚠️ [Formatter] HIGH specificity VIOLATION — missing: \(missing.joined(separator: ", "))")
            print("⚠️ [Formatter] Response length: \(response.response.count) chars. First 120: \(response.response.prefix(120))")

            // If a drillProvider was passed (GPT path), append structured drills for each focus area
            // to make the response meet the 7-component contract. The original GPT coaching text is
            // preserved — we only ADD the structured drills that were missing.
            guard let provider = drillProvider, !context.focusAreas.isEmpty else {
                // No provider (local path violation — should not happen) or no focus areas — return as-is
                print("⚠️ [Formatter] No drillProvider available — returning response unrepaired")
                return response
            }

            print("🔧 [Formatter] Repairing with structured drills for \(context.focusAreas.count) focus area(s) via drillProvider")
            var lines: [String] = [response.response]
            lines.append("\n---\n**Detailed Drill Breakdown** *(auto-corrected — GPT response lacked required structure)*\n")

            for area in context.focusAreas.prefix(2) {
                lines.append("**\(area.name.capitalized)**")
                let drills = provider(area.name)
                for drill in drills.prefix(2) {
                    lines.append(drill)
                }
                lines.append("")
            }

            lines.append("*Note: drills above were generated by the local drill library because the AI response did not include the required detail level.*")

            return CoachMessageResponse(
                response: lines.joined(separator: "\n"),
                suggestedActions: response.suggestedActions,
                tone: response.tone,
                followUpQuestions: response.followUpQuestions,
                timestamp: response.timestamp
            )
        }

        // ── Actions alignment ────────────────────────────────────────────────────────

        private static func alignActions(_ response: CoachMessageResponse, outputMode: OutputMode) -> CoachMessageResponse {
            var actions = response.suggestedActions
            guard outputMode == .workoutPlan || outputMode == .hybrid else { return response }
            let hasLog = actions.contains(where: { $0.lowercased().contains("log") })
            if !hasLog && actions.count < 4 { actions.append("Log this session") }
            guard actions != response.suggestedActions else { return response }
            return CoachMessageResponse(
                response: response.response,
                suggestedActions: actions,
                tone: response.tone,
                followUpQuestions: response.followUpQuestions,
                timestamp: response.timestamp
            )
        }
    }

    // ── Multi-signal helper methods ───────────────────────────────────────────────

    // MARK: - Output Mode Detector (Phase 2)

    /// Classifies coaching-likely messages into a typed output mode.
    /// Called only for messages that already passed Phase 1 as .coachingLikely.
    /// Internal (not private) so that AICoachRoutingTests can verify mode routing directly.
    struct OutputModeDetector {

        static func detect(from message: String) -> OutputMode {
            let low = message.lowercased()

            // ── PRIORITY 1: Multi-day schedule (highest — must beat workoutPlan) ──────
            let scheduleKW = ["schedule", "weekly", "week plan", "days a week", "training plan",
                              "program", "this week", "multi-day", "day 1", "day 2",
                              "make a plan", "build a plan"]
            if scheduleKW.contains(where: { low.contains($0) }) { return .schedulePlan }

            // ── PRIORITY 2: Explicit workout request ─────────────────────────────────
            // Requires BOTH an action verb AND workout vocabulary.
            // "plan" alone does NOT qualify — must have an action verb paired with it.
            let actionVerbs = ["build me", "build a", "create a", "create me",
                               "give me a", "give me the", "make me a", "design a",
                               "write me a", "let's do a", "put together a",
                               "show me drills", "show me a drill", "show me a workout"]
            let workoutVocab = ["drill", "workout", "session", "reps", "sets", "routine",
                                "circuit", "warm up", "warmup", "cool down", "minute"]
            let hasActionVerb = actionVerbs.contains(where: { low.contains($0) })
            let hasWorkoutVocab = workoutVocab.contains(where: { low.contains($0) })

            // ── PRIORITY 3: Explanation ───────────────────────────────────────────────
            let explanationKW = ["why", "how does", "what is", "explain", "what does",
                                 "tell me about", "what should i know", "why do i", "how come"]
            let hasExplanation = explanationKW.contains(where: { low.contains($0) })

            // Hybrid: explanation + explicit workout request
            if hasActionVerb && hasWorkoutVocab && hasExplanation { return .hybrid }
            // Pure explanation (no explicit workout request alongside it)
            if hasExplanation && !(hasActionVerb && hasWorkoutVocab) { return .explanation }
            // Explicit workout request (action verb + workout vocab present)
            if hasActionVerb && hasWorkoutVocab { return .workoutPlan }

            // ── PRIORITY 4: Guidance — directional/advisory coaching question ─────────
            // Brief, direct advice + confirming question. NOT a full plan.
            let guidanceKW = ["what should i focus", "what should i work on",
                              "what's most important", "what is most important",
                              "am i working on the right", "what should i prioritize",
                              "where should i start", "what area should",
                              "what do you recommend", "what would you recommend",
                              "what's your recommendation", "what's next for me",
                              "what should my next", "focus on today", "work on today",
                              "practice today", "what to work on", "what to focus on",
                              "what should i do today"]
            if guidanceKW.contains(where: { low.contains($0) }) { return .guidance }

            // ── PRIORITY 5: Safe fallback ─────────────────────────────────────────────
            // Coaching-intent but underspecified — gather more info before prescribing.
            return .coachingConversational
        }
    }

    /// Determine what type of response the user is asking for.
    private func detectOutputMode(from message: String) -> OutputMode {
        return OutputModeDetector.detect(from: message)
    }

    /// Extract ALL distinct training focus areas named in the user's message, in priority order.
    /// Handles multi-part inputs like "focus on left hand and athleticism, plus other skills".
    private func extractAllFocusAreas(from message: String) -> [FocusArea] {
        let low = message.lowercased()
        var areas: [FocusArea] = []

        // ── Direct skill phrases — SPORT-SPECIFIC to prevent cross-sport drill contamination ──
        // Each sport only detects its own vocabulary. A football user saying "shooting" must
        // NOT trigger basketball skill detection. First matched area is primary (1.0).
        let skillPhrases: [(String, String)]
        switch sport {
        case .basketball:
            skillPhrases = [
                ("left hand",     "left hand dribbling"), ("weak hand",     "weak-hand work"),
                ("off hand",      "off-hand dribbling"),  ("shooting",      "shooting"),
                ("free throw",    "free throw shooting"), ("layup",         "layup finishing"),
                ("crossover",     "crossover dribbling"), ("dribbling",     "dribbling"),
                ("ball handling", "ball handling"),        ("ball control",  "ball control"),
                ("post move",     "post moves"),           ("finishing",     "finishing at the rim"),
                ("passing",       "passing"),              ("footwork",      "footwork"),
                ("pivot",         "pivot footwork"),
            ]
        case .football:
            skillPhrases = [
                ("route running", "route running"),        ("catching",      "catching"),
                ("blocking",      "blocking"),             ("footwork",      "footwork"),
                ("pass rush",     "pass rush"),            ("release",       "release technique"),
                ("off the line",  "first-step explosion"), ("coverage",      "coverage reads"),
                ("acceleration",  "acceleration training"), ("agility",      "agility training"),
            ]
        case .soccer:
            skillPhrases = [
                ("first touch",   "first touch"),          ("heading",       "heading"),
                ("crossing",      "crossing"),             ("finishing",     "finishing"),
                ("passing",       "passing"),              ("dribbling",     "dribbling"),
                ("shooting",      "shooting"),             ("footwork",      "footwork"),
                ("defending",     "defending"),
            ]
        case .tennis:
            skillPhrases = [
                ("serve",         "serve"),                ("forehand",      "forehand"),
                ("backhand",      "backhand"),             ("volley",        "volley"),
                ("topspin",       "topspin"),              ("drop shot",     "drop shot"),
                ("footwork",      "footwork"),             ("return",        "return of serve"),
                ("overhead",      "overhead"),             ("net play",      "net game"),
            ]
        }
        for (phrase, name) in skillPhrases {
            if low.contains(phrase), !areas.contains(where: { $0.name == name }) {
                areas.append(FocusArea(
                    name: name,
                    concepts: ["direct_skill", "technique"],
                    userWeight: areas.isEmpty ? 1.0 : 0.85
                ))
            }
        }

        // ── Athletic attribute phrases ─────────────────────────────────────────────
        let athleticPhrases: [(String, String, [String])] = [
            ("athleticism",   "athleticism",   ["athleticism", "conditioning"]),
            ("speed",         "speed",          ["speed", "quickness"]),
            ("quickness",     "quickness",      ["quickness", "agility"]),
            ("agility",       "agility",        ["agility", "quickness"]),
            ("strength",      "strength",       ["strength", "power"]),
            ("conditioning",  "conditioning",   ["conditioning", "endurance"]),
            ("endurance",     "endurance",      ["endurance", "stamina"]),
            ("stamina",       "stamina",        ["stamina", "conditioning"]),
            ("explosiveness", "explosiveness",  ["explosiveness", "power"]),
            ("vertical",      "vertical jump",  ["explosiveness", "power"]),
            ("cardio",        "cardio fitness", ["conditioning", "stamina"]),
            ("fitness",       "fitness",        ["conditioning", "endurance"]),
        ]
        for (phrase, name, concepts) in athleticPhrases {
            if low.contains(phrase), !areas.contains(where: { $0.name == name }) {
                areas.append(FocusArea(name: name, concepts: concepts, userWeight: 0.70))
            }
        }

        // ── "Other skills" request → pull from survey gaps or sport fundamentals ──
        let hasOtherRequest = low.contains("other skill")    || low.contains("other important") ||
                              low.contains("other area")     || low.contains("everything else")  ||
                              low.contains("other stuff")    || low.contains("other things")     ||
                              (low.contains("also want") && low.contains("skill"))
        if hasOtherRequest {
            if let survey = surveyResponse {
                let critical = survey.skillRatings
                    .filter  { $0.value <= 5 }
                    .sorted  { $0.value < $1.value }
                for (skill, _) in critical.prefix(2) {
                    if !areas.contains(where: { $0.name.lowercased().contains(skill.lowercased()) }) {
                        areas.append(FocusArea(name: skill, concepts: ["technique"], userWeight: 0.35))
                    }
                }
            }
            // Ensure at least one supplementary area even without a survey
            if !areas.contains(where: { $0.userWeight <= 0.35 }) {
                areas.append(FocusArea(
                    name: "\(sport.rawValue) fundamentals",
                    concepts: ["fundamentals", "technique"],
                    userWeight: 0.35
                ))
            }
        }

        return areas
    }

    /// Compute proportional time blocks for a multi-focus session.
    ///
    /// Time allocation rules (per the unified directive):
    ///  - Warmup:   ~10% of total (min 5 min when session ≥ 20 min; scales up for longer sessions)
    ///  - Cooldown: 5 min when session ≥ 30 min (fixed — cooldown doesn't need to scale)
    ///  - Transfer: up to 10 min when session ≥ 40 min (game-like carry-over block)
    ///  - Remaining work minutes distributed proportionally across all focus areas
    private func buildTimeBlocks(totalMinutes: Int, focusAreas: [FocusArea]) -> [TimeBlock] {
        var blocks: [TimeBlock] = []
        // Warmup scales with session length (~10%) — 5 min floor for short sessions
        let warmupMins   = totalMinutes >= 20 ? max(5, totalMinutes / 10) : 0
        let cooldownMins = totalMinutes >= 30 ? 5 : 0
        let transferMins = totalMinutes >= 40 ? min(10, totalMinutes / 8) : 0
        let workMins     = max(0, totalMinutes - warmupMins - cooldownMins - transferMins)

        if warmupMins > 0 {
            blocks.append(TimeBlock(name: "Dynamic warm-up", minutes: warmupMins, blockType: "warmup"))
        }
        if focusAreas.isEmpty {
            blocks.append(TimeBlock(name: "Main work", minutes: workMins, blockType: "primary"))
        } else {
            let totalWeight = focusAreas.reduce(0.0) { $0 + $1.userWeight }
            for (i, area) in focusAreas.enumerated() {
                let proportion  = area.userWeight / totalWeight
                let areaMinutes = max(5, Int((Double(workMins) * proportion).rounded()))
                blocks.append(TimeBlock(
                    name:      area.name,
                    minutes:   areaMinutes,
                    blockType: i == 0 ? "primary" : "secondary"
                ))
            }
        }
        if transferMins > 0 {
            blocks.append(TimeBlock(name: "Game-like transfer", minutes: transferMins, blockType: "transfer"))
        }
        if cooldownMins > 0 {
            blocks.append(TimeBlock(name: "Cool-down", minutes: cooldownMins, blockType: "cooldown"))
        }
        return blocks
    }

    /// Synthesizes all coaching signals into a multi-signal structured brief for GPT-4.
    ///
    /// Implements:
    ///  - Output mode detection (workout_plan / explanation / hybrid)
    ///  - Multi-signal focus area extraction — ALL user-named areas honored, none collapsed
    ///  - Proportional time allocation per focus area
    ///  - Session composition structure (warm-up → primary → secondary → transfer → cool-down)
    ///  - Survey integration (critical gaps woven into supplementary blocks)
    ///  - Response fluidity + decision-strength directives injected into GPT-4 system prompt
    private func buildCoachingBrief(for message: String) -> String? {
        // ── Safety mode classification (runs first — can short-circuit the whole brief) ─
        let weeklyCount   = SafetyDetector.weeklySessionCount(for: sport)
        // Pull wearable recovery score from HealthKit-synced UserDefaults (nil if no wearable data)
        let recoveryScore = UserDefaults.standard.object(forKey: "smartwatch_recovery_score") as? Int
        let safetyMode    = SafetyModeClassifier.classify(
            message: message, weeklySessionCount: weeklyCount, recoveryScore: recoveryScore
        )

        // Record safety mode activation for telemetry (production)
        if safetyMode != .normal {
            CoachTelemetry.recordSafetyMode(sport: sport, mode: safetyMode.modeName)
        }
        if case .injuryCaution = safetyMode {
            CoachTelemetry.recordInjuryContext(sport: sport)
        }
        if case .recoveryBiased = safetyMode {
            CoachTelemetry.recordOvertrainingDetected(sport: sport, sessionCount: weeklyCount)
        }

        // stopAndDefer mode: return the safety block ONLY — no training content.
        if case .stopAndDefer(let reason) = safetyMode {
            return "ACTIVE SPORT: \(sport.rawValue.uppercased())\n" + safetyMode.localBriefPrefix
        }

        let intent     = inferIntent(from: message)
        let fresh      = semanticMap(from: message)
        let outputMode = detectOutputMode(from: message)
        let focusAreas = extractAllFocusAreas(from: message)

        // RULE: When the current message carries a direct_skill signal, analyse ONLY
        // the fresh concepts — don't let session-history athletic attributes hijack
        // an explicit skill request.
        let baseConcepts: [String]
        if fresh.contains("direct_skill") {
            baseConcepts = fresh
        } else {
            baseConcepts = Array(Set(fresh + athleticAttributes))
        }

        // When semantic map returns nothing but we have explicit focus areas,
        // synthesize concepts from those areas so analyze() gets a valid input.
        let allConcepts: [String]
        if baseConcepts.isEmpty && !focusAreas.isEmpty {
            allConcepts = Array(Set(focusAreas.flatMap(\.concepts)))
        } else {
            allConcepts = baseConcepts
        }

        // If still nothing detectable, fall back to survey-grounded brief
        guard !allConcepts.isEmpty else {
            return buildSurveyFallbackBrief()
        }

        // Primary analysis for the highest-priority detected signal
        guard let primaryAnalysis = AICoachReasoning.analyze(
            concepts: allConcepts, message: message, intent: intent, sport: sport
        ) else {
            return buildSurveyFallbackBrief()
        }

        // Prioritization drives the insight banner and directives
        let surveyWeaknesses = SportWeaknesses.load(for: sport)
        let prioritization   = AICoachReasoning.prioritize(
            recurringWeaknesses: recurringWeaknesses,
            latestConcern:       latestWeakness,
            surveyWeaknesses:    surveyWeaknesses,
            surveySkillRatings:  surveyResponse?.skillRatings ?? [:],
            analysis:            primaryAnalysis
        )

        // Update the UI insight banner — prefer explicit user-named areas over inferred
        let bannerPrimary   = focusAreas.first?.name ?? prioritization.primaryFocus
        let bannerSecondary = focusAreas.count > 1    ? focusAreas[1].name : prioritization.secondaryFocus
        sessionInsight = CoachSessionInsight(
            primaryFocus:   bannerPrimary,
            stageLabel:     "Stage \(prioritization.progressionStage.stageNumber)/3 · \(prioritization.progressionStage.displayName)",
            whyToday:       prioritization.whyToday,
            secondaryFocus: bannerSecondary
        )

        var lines: [String] = []

        // ── Safety mode prefix (prepended if active) ──────────────────────────────────
        // injuryCaution and recoveryBiased modes add mandatory override rules that GPT
        // must read before any coaching content. This ensures safety rules are never buried.
        if safetyMode != .normal {
            let prefix = safetyMode.localBriefPrefix
            if !prefix.isEmpty { lines.append(prefix) }
        }

        // ── GLOBAL SPORT ENFORCEMENT (IMMUTABLE — highest priority rule) ─────────────
        // MUST be the first thing GPT reads. ALL drills, movements, and skill references
        // in the response must belong to the active sport. Zero exceptions.
        let (allowedDrills, forbiddenDrills) = sportDrillValidationExamples()
        lines.append("ACTIVE SPORT: \(sport.rawValue.uppercased())")
        lines.append("SPORT RULE (ZERO TOLERANCE): Every drill, movement, and skill reference MUST be \(sport.rawValue)-specific. Allowed types: \(allowedDrills). FORBIDDEN from other sports: \(forbiddenDrills).")

        // ── Output mode directive ─────────────────────────────────────────────────────
        lines.append("OUTPUT MODE: \(outputMode.rawValue)")
        switch outputMode {
        case .schedulePlan:
            let sessionMins = availableTimeMinutes ?? 45
            let days = 4
            lines.append("RESPONSE FORMAT: Generate a MULTI-DAY \(sport.rawValue) training schedule — NOT a single session. Structure as 'Day 1:', 'Day 2:', 'Day 3:', 'Day 4:'. Each day: Warmup (\(max(5, sessionMins/10)) min of dynamic \(sport.rawValue) movement), Primary drill block (≥2 named \(sport.rawValue) drills with sets×reps), Secondary block (1-2 supporting drills), Cooldown (5 min). Vary the primary focus each day. Total per day: \(sessionMins) min. All drills must be \(sport.rawValue)-specific.")
            lines.append("SCHEDULE EMPHASIS: Primary focus — \(focusAreas.first?.name ?? prioritization.primaryFocus). Include \(focusAreas.map(\.name).joined(separator: ", ")) across the schedule.")
        case .workoutPlan:
            lines.append("RESPONSE FORMAT: Prescribe a complete, structured \(sport.rawValue) training session. Name every drill with its actual name (no generic categories). Include explicit sets × reps OR duration + rest for every drill. Total must match any stated time constraint.")
        case .explanation:
            lines.append("RESPONSE FORMAT: Explain the concept clearly using a concrete \(sport.rawValue) example. End with one immediate actionable drill or next step.")
        case .hybrid:
            lines.append("RESPONSE FORMAT: Answer the question in 2–3 sentences, then prescribe a complete \(sport.rawValue) session with named drills, explicit sets, reps, and durations.")
        case .guidance:
            lines.append("RESPONSE FORMAT: Give brief, direct coaching guidance (3–4 sentences max) about what the athlete should prioritize today and why. End with ONE confirming question to make sure it matches what they're feeling. Do NOT generate a full workout plan or list of drills.")
        case .coachingConversational:
            lines.append("RESPONSE FORMAT: The athlete's intent is unclear — do NOT generate a workout plan or drills. Ask ONE targeted \(sport.rawValue)-specific question to understand what they need. Keep it under 2 sentences. Wait for their answer before prescribing anything.")
        }

        // ── Focus areas — enforce multi-signal, no collapse ───────────────────────────
        if focusAreas.count > 1 {
            let focusList = focusAreas.map(\.name).joined(separator: " + ")
            lines.append("MULTI-FOCUS SESSION: Athlete requested \(focusAreas.count) areas — \(focusList).")
            lines.append("RULE: Address ALL areas. Do NOT collapse to one. Each area needs at least 2 named drills.")
            for (i, area) in focusAreas.enumerated() {
                let role = i == 0 ? "PRIMARY" : (i == 1 ? "SECONDARY" : "SUPPLEMENTARY")
                lines.append("  \(role): \(area.name)")
            }
        } else {
            lines.append("PRIMARY FOCUS: \(prioritization.primaryFocus)")
            if let sec = prioritization.secondaryFocus {
                lines.append("SECONDARY FOCUS: \(sec) — address only after primary is covered")
            }
        }

        lines.append("WHY TODAY: \(prioritization.whyToday)")
        lines.append("PROGRESSION STAGE: \(prioritization.progressionStage.displayName) (stage \(prioritization.progressionStage.stageNumber)/3) — \(prioritization.progressionStage.sessionDesignPrinciple)")

        // ── Time allocation ───────────────────────────────────────────────────────────
        if let totalMins = availableTimeMinutes, totalMins > 0 {
            let blocks = buildTimeBlocks(totalMinutes: totalMins, focusAreas: focusAreas)
            lines.append("TIME ALLOCATION (\(totalMins) min total):")
            for block in blocks {
                lines.append("  \(block.blockType.uppercased()) - \(block.name): \(block.minutes) min")
            }
            lines.append("PRECISION RULE: Drill sets + reps + rest for each block MUST sum to that block's time. Be exact.")
        }

        // ── Session composition ───────────────────────────────────────────────────────
        lines.append("SESSION STRUCTURE: warm-up → primary skill block → secondary block(s) → game-like transfer (if time) → cool-down. Each block must name specific drills.")

        // ── Weakness profile (primary signal) ────────────────────────────────────────
        lines.append("PRIMARY WEAKNESS PROFILE:")
        lines.append("  Type: \(primaryAnalysis.type.rawValue) | Drill category: \(primaryAnalysis.drillCategory)")
        lines.append("  Manifestation: \(primaryAnalysis.manifestation)")
        lines.append("  Sport impact (\(sport.rawValue)): \(primaryAnalysis.sportImpact)")
        lines.append("  Training focus: \(primaryAnalysis.trainingFocus)")

        // ── Readiness adaptation (WHOOP-like) ────────────────────────────────────────
        // computeReadiness() pulls HRV, resting HR, sleep, strain, and self-report from
        // UserDefaults (synced from HealthKit via WearableProviderManager). The resulting
        // CoachReadinessProfile sits AFTER the coaching plan is built and BEFORE GPT responds,
        // so intensity/volume modifiers are applied to the already-planned session, not in place of it.
        lines.append(adaptPlanForReadiness(profile: computeReadiness()))

        // ── Memory evolution ──────────────────────────────────────────────────────────
        let topPatterns = recurringWeaknesses.sorted { $0.value > $1.value }.prefix(3).filter { $0.value >= 2 }
        if !topPatterns.isEmpty {
            let patStr = topPatterns.map { "\($0.key) (\($0.value)×)" }.joined(separator: ", ")
            lines.append("RECURRING PATTERNS: \(patStr) — apply progressive overload; add complexity or pressure vs prior sessions")
        }

        // ── Survey integration ────────────────────────────────────────────────────────
        if let survey = surveyResponse {
            let critical = survey.skillRatings.filter { $0.value <= 3 }.sorted { $0.value < $1.value }
            if !critical.isEmpty {
                let critStr = critical.prefix(2).map { "\($0.key) (\($0.value)/10)" }.joined(separator: ", ")
                lines.append("SURVEY CRITICAL GAPS: \(critStr) — weave one drill for each into supplementary blocks if time allows")
            }
            if !survey.strengths.isEmpty {
                let strStr = survey.strengths.prefix(2).joined(separator: ", ")
                lines.append("CONFIRMED STRENGTHS: \(strStr) — use as contrast tool, do NOT repeat as primary focus today")
            }
        }

        // ── Directives ────────────────────────────────────────────────────────────────
        lines.append("PROGRESSION DIRECTIVE: \(prioritization.progressionStage.progressionDirective)")

        if focusAreas.count > 1 {
            let allFocuses = focusAreas.map(\.name).joined(separator: ", ")
            lines.append("COACHING DIRECTIVE: Design a complete \(sport.rawValue) session covering: \(allFocuses). Allocate time per blocks above. Each named area needs ≥2 specific drills with sets×reps or duration + rest. Connect each drill to its skill. Do NOT collapse or skip any area.")
        } else {
            lines.append("COACHING DIRECTIVE: Prescribe an exact \(primaryAnalysis.drillCategory) session addressing \(primaryAnalysis.type.rawValue) at the \(prioritization.progressionStage.displayName) stage. Name specific drills with sets, reps, durations, and rest periods. Do not list categories — prescribe the session.")
        }

        // ── Response fluidity + decision-strength rules ───────────────────────────────
        lines.append("FLUIDITY RULES: Speak directly to this athlete as their coach. Name actual \(sport.rawValue) drills not generic categories. Never say \"it depends\" or \"everyone is different\" — commit to a specific prescription. Never ask clarifying questions when you have enough context above. Write in coaching voice, not a document template.")

        // ── Specificity mode directive ─────────────────────────────────────────────────
        // Escalates to HIGH when user said "specific drills", "more detail", "expand", etc.
        // HIGH mode requires every drill to include all 7 components — name, setup, exact
        // action, sets, reps/time, rest, and coaching cue. No generic categories allowed.
        lines.append(SpecificityMode.detect(from: message).gptDirective)

        // ── Drill realism constraint ───────────────────────────────────────────────────
        // Ensures drills are feasible for a young athlete with typical equipment access.
        lines.append(DrillRealistPromptBlock.generate(for: sport, timeMinutes: availableTimeMinutes))

        // ── FINAL DRILL VALIDATION GUARDRAIL ─────────────────────────────────────────
        // This runs last so GPT validates its own output before responding.
        lines.append("DRILL VALIDATION (REQUIRED before responding): Review every drill/exercise in your planned response. For each drill, verify: 'Is this a \(sport.rawValue) drill?' Forbidden examples: \(forbiddenDrills). If ANY drill belongs to a different sport, replace it with a \(sport.rawValue) equivalent before sending your response. No exceptions.")

        // ── Safety detection (runs last — overrides any preceding training content) ────
        if SafetyDetector.detectsInjury(in: message) {
            lines.append(SafetyDetector.injuryConstraintBlock)
        }
        // weeklyCount already computed at the top of this function for SafetyModeClassifier
        if SafetyDetector.detectsOvertraining(sessionCount: weeklyCount) {
            lines.append(SafetyDetector.overtainingConstraintBlock(sessionCount: weeklyCount))
        }

        // ── Sport team-context guardrail ──────────────────────────────────────────────
        let sportConstraint = SportConstraint.constraint(for: sport)
        if !sportConstraint.allowsSoloDrills || !sportConstraint.allowsOneOnOneMatchFraming {
            lines.append("SPORT TEAM CONTEXT REQUIRED: \(sportConstraint.localPipelineGuardrail)")
        }

        // ── Negative feedback signal ──────────────────────────────────────────────────
        if let feedbackNote = CoachFeedbackStore.negativeSignalSummary(for: sport) {
            lines.append(feedbackNote)
        }

        return lines.joined(separator: "\n")
    }

    /// Returns (allowed drill examples, forbidden drill examples) for sport enforcement in briefs.
    private func sportDrillValidationExamples() -> (allowed: String, forbidden: String) {
        switch sport {
        case .basketball:
            return (
                "dribbling drills, shooting form, lane agility, defensive slides, box-out drills",
                "soccer: ball control/crossing | football: route running/blocking | tennis: groundstrokes/serve"
            )
        case .football:
            return (
                "route running, release off the line, catch drills, cone agility, 40-yard acceleration, footwork ladders",
                "basketball: dribbling/shooting/layups | soccer: ball control/headers | tennis: groundstrokes/serve"
            )
        case .soccer:
            return (
                "ball control, passing combinations, finishing in the box, pressing patterns, 1v1 dribbling moves",
                "basketball: shooting/dribbling | football: route running/blocking | tennis: groundstrokes/serve"
            )
        case .tennis:
            return (
                "groundstroke rallying, serve mechanics, split-step footwork, net approach drills, return of serve",
                "basketball: dribbling/shooting | soccer: ball control | football: route running/blocking"
            )
        }
    }

    /// Dismiss the session insight banner (user tapped X).
    func dismissSessionInsight() {
        sessionInsight = nil
    }

    /// Fallback coaching brief for vague messages ("help me", "what should I work on").
    /// Uses onboarding survey to ground the session plan so the AI never has to ask
    /// "what do you want to work on?" when the athlete's baseline profile is already known.
    private func buildSurveyFallbackBrief() -> String? {
        guard let survey = surveyResponse else { return nil }

        // Rank skill gaps: critical first (1–3), then developing (4–6), then self-labelled weaknesses
        let sortedRatings = survey.skillRatings.sorted { $0.value < $1.value }
        let criticalSkills  = sortedRatings.filter { $0.value <= 3 }
        let developingSkills = sortedRatings.filter { $0.value >= 4 && $0.value <= 6 }

        let primarySkill: String
        let primaryRating: Int?

        if let top = criticalSkills.first {
            primarySkill = top.key
            primaryRating = top.value
        } else if let topWeak = survey.weaknesses.first {
            primarySkill = topWeak
            primaryRating = nil
        } else if let top = developingSkills.first {
            primarySkill = top.key
            primaryRating = top.value
        } else {
            return nil  // Survey exists but has no actionable data — let backend handle it
        }

        // Progression stage based on how often this concept has appeared in conversation
        let mentionCount  = recurringWeaknesses[primarySkill.lowercased()] ?? 1
        let sessionCount  = SafetyDetector.weeklySessionCount(for: sport)
        let feedback      = CoachFeedbackStore.feedbackCounts(for: sport)
        let derivedStage  = OutcomeAwareProgressionStage.derive(
            mentionCount: mentionCount, sessionCount: sessionCount, feedbackRatio: feedback
        )
        let stage = ProgressionStage(mentionCount: derivedStage)

        // Update the UI insight banner
        sessionInsight = CoachSessionInsight(
            primaryFocus: primarySkill,
            stageLabel: "Stage \(stage.stageNumber)/3 · \(stage.displayName)",
            whyToday: "Your declared #1 priority from baseline assessment",
            secondaryFocus: criticalSkills.dropFirst().first?.key
        )

        var lines: [String] = []

        // ── GLOBAL SPORT ENFORCEMENT — same rule as buildCoachingBrief() ─────────────
        let (allowedDrills, forbiddenDrills) = sportDrillValidationExamples()
        lines.append("ACTIVE SPORT: \(sport.rawValue.uppercased())")
        lines.append("SPORT RULE (ZERO TOLERANCE): Every drill, movement, and skill reference MUST be \(sport.rawValue)-specific. Allowed types: \(allowedDrills). FORBIDDEN from other sports: \(forbiddenDrills).")

        lines.append("PRIMARY FOCUS: \(primarySkill)")

        if let rating = primaryRating {
            lines.append("WHY TODAY: Baseline assessment rated \(primarySkill) at \(rating)/10 — the athlete's declared top priority; do not ask what to work on, you already know")
        } else {
            lines.append("WHY TODAY: Athlete self-labelled \(primarySkill) as a weakness in their goals survey — address this without asking for further clarification")
        }

        lines.append("PROGRESSION STAGE: \(stage.displayName) (stage \(stage.stageNumber)/3) — \(stage.sessionDesignPrinciple)")
        lines.append("PROGRESSION DIRECTIVE: \(stage.progressionDirective)")

        if !criticalSkills.isEmpty {
            let gapList = criticalSkills.prefix(3).map { "\($0.key) (\($0.value)/10)" }.joined(separator: ", ")
            lines.append("SKILL GAPS: \(gapList)")
        }

        if !survey.strengths.isEmpty {
            let strengthList = survey.strengths.prefix(2).joined(separator: ", ")
            lines.append("CONFIRMED STRENGTHS: \(strengthList) — athlete is already solid here; don't waste session time on these today")
        }

        lines.append("SURVEY SOURCE: Brief derived from athlete's onboarding baseline — message was non-specific. Use the survey profile above as your coaching plan foundation.")
        lines.append("COACHING DIRECTIVE: The user's message was vague. You have their full baseline profile. Do NOT ask \"what do you want to work on?\" — prescribe a concrete session plan for \(primarySkill) improvement at the \(stage.displayName) stage. Name specific drills with sets, reps, durations, and rest periods.")

        return lines.joined(separator: "\n")
    }

    // MARK: - Intent Inference

    /// Infer what the user is trying to accomplish from their message.
    /// Returns a raw string so it can be included in the Codable CoachContext.
    private func inferIntent(from message: String) -> String {
        let low = message.lowercased()

        // Elaboration / continuation — must check before other patterns
        let elaborationTriggers = ["expand", "elaborate", "what you said", "what you just said",
                                   "more detail", "go deeper", "based on that", "build on",
                                   "what do you mean", "tell me more", "can you explain",
                                   "dive deeper", "tl;dr", "tldr", "simpler", "shorter version",
                                   "turn that into", "what about tomorrow"]
        if elaborationTriggers.contains(where: { low.contains($0) }) {
            return "elaboration"
        }

        // Time / resource constraint
        let hasTimeWord = low.contains("minute") || low.contains("min") || low.contains("hour")
        let hasConstraintWord = low.contains("only have") || low.contains("just have") || low.contains("i have")
        if hasTimeWord && hasConstraintWord {
            return "constraint_adjustment"
        }

        // Match / competition prep
        if low.contains("match") || low.contains("game") || low.contains("tournament") ||
           low.contains("competition") || low.contains("tryout") ||
           (low.contains("prepare") && (low.contains("for") || low.contains("my"))) {
            return "match_prep"
        }

        // Athletic development (speed, strength, conditioning, etc.)
        let athleticTerms = ["speed", "faster", "quicker", "strength", "stronger", "conditioning",
                             "endurance", "stamina", "agility", "agile", "vertical", "explosiveness",
                             "explosive", "power", "fitness", "cardio", "athleticism", "athletic",
                             "get tired", "run out of gas", "feel slow", "slow feet"]
        let weaknessMarkers = ["weak", "struggle", "bad at", "not good", "need to improve",
                               "need help", "can't", "cannot", "difficult", "hard for me"]
        let hasWeaknessMarker = weaknessMarkers.contains { low.contains($0) }
        let hasAthleticTerm = athleticTerms.contains { low.contains($0) }
        if hasWeaknessMarker && hasAthleticTerm {
            return "athletic_development"
        }

        // General weakness / skill help
        if hasWeaknessMarker {
            return "weakness_help"
        }

        // Training recommendation request
        let trainingTriggers = ["workout", "train", "drill", "what should i", "recommend",
                                "help me", "how do i", "how can i", "how to", "what can i",
                                "give me", "i need to get", "improve", "get better"]
        if trainingTriggers.contains(where: { low.contains($0) }) {
            return "training_recommendation"
        }

        return "general"
    }

    /// Map natural-language phrases to underlying athletic/skill concepts.
    ///
    /// SPORT ISOLATION RULE: Sport-specific skill terms only fire for their own sport.
    /// A football user saying "shooting" must NOT inject basketball concepts.
    /// General athletic attributes (speed, conditioning, etc.) apply to all sports.
    private func semanticMap(from message: String) -> [String] {
        let low = message.lowercased()
        var concepts: [String] = []

        // ── SECTION 1: Universal athletic attribute phrases (ALL sports) ────────────
        // These apply regardless of sport — physical/mental attributes, not sport skills.
        let universalPhrases: [(phrase: String, concepts: [String])] = [
            // Cross-sport skill terms (safe for all sports)
            ("footwork",            ["direct_skill", "technique"]),
            // General athletic / physical signals
            ("feel slow",           ["speed", "agility"]),
            ("feeling slow",        ["speed", "agility"]),
            ("too slow",            ["speed", "quickness"]),
            ("not fast enough",     ["speed", "acceleration"]),
            ("get tired quickly",   ["conditioning", "stamina", "endurance"]),
            ("getting tired",       ["conditioning", "stamina"]),
            ("run out of gas",      ["conditioning", "endurance"]),
            ("out of gas",          ["conditioning", "endurance"]),
            ("lose my wind",        ["conditioning", "stamina"]),
            ("not explosive",       ["explosiveness", "power"]),
            ("can't explode",       ["explosiveness", "power"]),
            ("struggle late",       ["endurance", "conditioning"]),
            ("late in game",        ["endurance", "conditioning"]),
            ("can't keep up",       ["speed", "conditioning"]),
            ("slow feet",           ["footwork", "agility"]),
            ("not strong enough",   ["strength", "power"]),
            ("getting pushed",      ["strength", "physicality"]),
            ("pushed around",       ["strength", "physicality"]),
            ("lose balance",        ["balance", "stability", "core"]),
            ("losing balance",      ["balance", "stability"]),
            ("feel heavy",          ["conditioning", "recovery"]),
            ("timing is off",       ["timing", "footwork"]),
            ("lack confidence",     ["confidence", "mental game"]),
            ("nervous before",      ["mental", "confidence"]),
            ("not consistent",      ["consistency", "fundamentals"]),
            ("miss under pressure", ["composure", "clutch"]),
            ("my athleticism",      ["athleticism", "conditioning"]),
            ("my fitness",          ["conditioning", "endurance"]),
            ("my speed",            ["speed", "quickness"]),
            ("my strength",         ["strength", "power"]),
            ("my conditioning",     ["conditioning", "stamina"]),
            ("my agility",          ["agility", "quickness"]),
            ("my endurance",        ["endurance", "stamina"]),
            ("my stamina",          ["stamina", "conditioning"]),
            ("my explosiveness",    ["explosiveness", "power"]),
            ("athleticism",         ["athleticism", "conditioning"]),
        ]

        // ── SECTION 2: Sport-specific skill phrases (ONLY active sport) ─────────────
        // Each sport only matches its own vocabulary. Prevents a football user saying
        // "shooting" from triggering basketball coaching, or a tennis user saying
        // "dribbling" from getting basketball drills.
        let sportPhrases: [(phrase: String, concepts: [String])]
        switch sport {
        case .basketball:
            sportPhrases = [
                ("left hand",        ["direct_skill", "technique"]),
                ("weak hand",        ["direct_skill", "technique"]),
                ("off hand",         ["direct_skill", "technique"]),
                ("non-dominant",     ["direct_skill", "technique"]),
                ("right hand",       ["direct_skill", "technique"]),
                ("shooting",         ["direct_skill", "technique"]),
                ("dribbling",        ["direct_skill", "technique"]),
                ("ball control",     ["direct_skill", "technique"]),
                ("free throw",       ["direct_skill", "technique"]),
                ("layup",            ["direct_skill", "technique"]),
                ("crossover",        ["direct_skill", "technique"]),
                ("ball handling",    ["direct_skill", "technique"]),
                ("post move",        ["direct_skill", "technique"]),
                ("post up",          ["direct_skill", "technique"]),
                ("euro step",        ["direct_skill", "technique"]),
                ("floater",          ["direct_skill", "technique"]),
                ("pull up",          ["direct_skill", "technique"]),
                ("step back",        ["direct_skill", "technique"]),
                ("mid range",        ["direct_skill", "technique"]),
                ("finishing",        ["direct_skill", "technique"]),
                ("pivot",            ["direct_skill", "technique"]),
                ("my shooting",      ["technique"]),
                ("my shot",          ["technique"]),
                ("shooting form",    ["technique"]),
                ("three pointer",    ["technique"]),
                ("three-pointer",    ["technique"]),
                ("three point",      ["technique"]),
                ("my dribble",       ["coordination", "technique"]),
                ("my ball handling", ["coordination", "technique"]),
                ("my crossover",     ["coordination", "technique"]),
                ("my layup",         ["technique"]),
                ("lay up",           ["technique"]),
                ("post moves",       ["technique", "coordination"]),
                ("my post",          ["technique", "strength"]),
                ("my passing",       ["technique"]),
                ("drop passes",      ["technique"]),
                ("drop the ball",    ["technique"]),
            ]

        case .football:
            sportPhrases = [
                ("route running",     ["direct_skill", "technique"]),
                ("catching",          ["direct_skill", "technique"]),
                ("blocking",          ["direct_skill", "technique"]),
                ("pass rush",         ["direct_skill", "explosiveness"]),
                ("off the line",      ["direct_skill", "explosiveness"]),
                ("release",           ["direct_skill", "technique"]),
                ("coverage",          ["direct_skill", "technique"]),
                ("acceleration",      ["speed", "explosiveness"]),
                ("my routes",         ["technique"]),
                ("running routes",    ["technique"]),
                ("my hands",          ["technique"]),
                ("catching the ball", ["technique"]),
                ("drop catches",      ["technique"]),
                ("blocking technique",["technique", "strength"]),
                ("my release",        ["technique", "coordination"]),
            ]

        case .soccer:
            sportPhrases = [
                ("first touch",       ["direct_skill", "technique"]),
                ("heading",           ["direct_skill", "technique"]),
                ("crossing",          ["direct_skill", "technique"]),
                ("finishing",         ["direct_skill", "technique"]),
                ("dribbling",         ["direct_skill", "technique"]),
                ("shooting",          ["direct_skill", "technique"]),
                ("ball control",      ["direct_skill", "technique"]),
                ("my finishing",      ["technique"]),
                ("finishing chances", ["technique"]),
                ("my first touch",    ["coordination", "technique"]),
                ("my headers",        ["technique"]),
                ("my crosses",        ["technique"]),
                ("through balls",     ["technique"]),
                ("my through ball",   ["technique"]),
                ("penalty kick",      ["technique"]),
                ("penalties",         ["technique", "mental"]),
            ]

        case .tennis:
            sportPhrases = [
                ("serve",             ["direct_skill", "technique"]),
                ("forehand",          ["direct_skill", "technique"]),
                ("backhand",          ["direct_skill", "technique"]),
                ("volley",            ["direct_skill", "technique"]),
                ("topspin",           ["direct_skill", "technique"]),
                ("drop shot",         ["direct_skill", "technique"]),
                ("overhead",          ["direct_skill", "technique"]),
                ("net play",          ["direct_skill", "technique"]),
                ("return",            ["direct_skill", "technique"]),
                ("my serve",          ["technique"]),
                ("my serving",        ["technique"]),
                ("first serve",       ["technique"]),
                ("second serve",      ["technique"]),
                ("my forehand",       ["technique"]),
                ("my backhand",       ["technique"]),
                ("my volley",         ["technique"]),
                ("my topspin",        ["technique"]),
                ("my slice",          ["technique"]),
                ("return of serve",   ["technique"]),
                ("my return",         ["technique"]),
                ("my overhead",       ["technique"]),
                ("double faults",     ["technique", "mental"]),
            ]
        }

        // Apply universal + sport-specific phrases
        for (phrase, cs) in universalPhrases + sportPhrases {
            if low.contains(phrase) {
                for concept in cs {
                    if !concepts.contains(concept) {
                        concepts.append(concept)
                    }
                }
            }
        }

        if !concepts.isEmpty {
            print("📱 [AI Coach] Semantic concepts detected (sport: \(sport.rawValue)): \(concepts)")
        }
        return concepts
    }

    // MARK: - Context Management
    
    private func extractContext(from message: String) {
        let lowercased = message.lowercased()
        var didChange = false

        // Extract sport-specific skill weak points — match exact skill names, not full sentences
        let sportSkills: [String]
        switch sport {
        case .basketball:
            sportSkills = ["shooting", "ball handling", "dribbling", "defense", "passing", "finishing",
                           "free throw", "layup", "crossover", "three point", "rebounding", "footwork"]
        case .tennis:
            sportSkills = ["serve", "forehand", "backhand", "volley", "footwork", "overhead",
                           "slice", "topspin", "return", "net game", "movement"]
        case .soccer:
            sportSkills = ["dribbling", "passing", "shooting", "defending", "first touch",
                           "crossing", "heading", "free kick", "dribbling", "positioning"]
        case .football:
            sportSkills = ["throwing", "catching", "route running", "blocking", "speed",
                           "agility", "reads", "footwork", "coverage"]
        }

        // Athletic attributes that apply across all sports
        let athleticTerms = ["speed", "quickness", "explosiveness", "strength", "conditioning",
                             "endurance", "stamina", "agility", "vertical", "flexibility",
                             "power", "athleticism", "cardio", "fitness"]

        let weakKeywords = ["weak", "struggle", "not good at", "bad at", "need help with", "need to improve", "work on", "working on", "improve"]
        if weakKeywords.contains(where: { lowercased.contains($0) }) {
            for skill in sportSkills {
                if lowercased.contains(skill) && !userWeakPoints.contains(skill) {
                    userWeakPoints.append(skill)
                    latestWeakness = skill  // Track most recently mentioned skill concern
                    didChange = true
                }
            }
            // Also capture athletic attributes (speed, conditioning, etc.) as context
            for term in athleticTerms {
                if lowercased.contains(term) {
                    if !athleticAttributes.contains(term) {
                        athleticAttributes.append(term)
                        didChange = true
                    }
                    latestWeakness = term  // Athletic attribute is also a "latest concern"
                }
            }
        }

        // Semantic mapping — runs unconditionally so phrases like "I feel slow" update
        // latestWeakness even without explicit "weak/struggle" markers.
        let messageConcepts = semanticMap(from: message)
        for concept in messageConcepts {
            // "direct_skill" is a transient routing signal, not a persistent athletic attribute.
            // Storing it would contaminate future non-skill messages by injecting it into
            // the athleticAttributes merge inside buildCoachingBrief().
            guard concept != "direct_skill" else { continue }
            if !athleticAttributes.contains(concept) {
                athleticAttributes.append(concept)
                didChange = true
            }
            // Memory evolution: track how often each concept appears across the conversation
            recurringWeaknesses[concept, default: 0] += 1
        }
        if !messageConcepts.isEmpty {
            // Semantic concepts are derived directly from this message — use them as latest concern.
            // This is more specific than a generic weakness keyword match.
            latestWeakness = messageConcepts.prefix(3).joined(separator: ", ")
            didChange = true
            print("📱 [AI Coach] latestWeakness updated from semantic map: \(latestWeakness!)")
        }


        // Extract goals — only store concise goal statements (not long messages)
        let goalKeywords = ["goal", "want to", "trying to", "hoping to", "working toward", "aim to"]
        if goalKeywords.contains(where: { lowercased.contains($0) }) {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 150 && !userGoals.contains(trimmed) {
                userGoals.append(trimmed)
                didChange = true
            }
        }

        // Extract available time using regex — store as Int minutes
        if lowercased.contains("minute") || lowercased.contains("min") || lowercased.contains("hour") || lowercased.contains("hr") {
            let pattern = "(\\d+)\\s*(?:hour|hr|minute|min)"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)),
               let numRange = Range(match.range(at: 1), in: lowercased),
               let num = Int(lowercased[numRange]) {
                let isHours = lowercased.range(of: "hour|\\bhr\\b", options: .regularExpression) != nil &&
                              (match.range.location + match.range.length <= lowercased.count)
                availableTimeMinutes = isHours ? num * 60 : num
                didChange = true
            }
        }

        if didChange {
            saveContext()
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
    
    // MARK: - Prompt Builder (Pipeline Stage 1)

    /// Assembles the single typed CoachPromptContext from all available session signals.
    ///
    /// This is the ONLY place context is assembled — nothing is built inline during reasoning.
    /// All downstream pipeline stages (Tool Decision, Reasoning, Formatting) receive this struct.
    ///
    /// Pipeline: extractContext() → buildPromptContext() → ToolPlan.decide() → reasoning → ResponseFormatter
    private func buildPromptContext(for message: String) -> CoachPromptContext {
        let intent          = inferIntent(from: message)
        var focusAreas      = extractAllFocusAreas(from: message)
        if focusAreas.isEmpty { focusAreas = deriveFocusAreasFromContext() }
        let outputMode      = detectOutputMode(from: message)
        let specificityMode = SpecificityMode.detect(from: message)

        // 5A: If the user named an explicit skill in this message, suppress survey-derived weak
        // points so they cannot pull the plan toward background survey data when the user has
        // given a clear, present-tense focus signal.
        // Uses DirectSkillDetector (canonical phrase list) rather than FocusArea introspection
        // so the suppression decision is identical to the testable path.
        let hasDirectSkill  = DirectSkillDetector.detect(from: message, sport: sport)
        if hasDirectSkill {
            print("🎯 [5A] Direct skill detected — suppressing survey weaknesses from context")
        }
        let apiCtx          = buildCoachContext(for: message,
                                                suppressSurveyWeaknesses: hasDirectSkill)  // also builds coachingBrief inside

        print("📐 [PromptBuilder] sport:\(sport.rawValue) intent:\(intent) mode:\(outputMode.rawValue) specificity:\(specificityMode == .high ? "HIGH 🎯" : "standard") focusAreas:\(focusAreas.count) time:\(availableTimeMinutes ?? 45)min")
        if specificityMode == .high {
            print("🎯 [PromptBuilder] HIGH specificity activated — 7-component drill output required on ALL paths")
        }

        return CoachPromptContext(
            sport:                sport,
            userMessage:          message,
            conversationHistory:  buildConversationHistory(),
            inferredIntent:       intent,
            focusAreas:           focusAreas,
            outputMode:           outputMode,
            specificityMode:      specificityMode,
            availableTimeMinutes: availableTimeMinutes ?? 45,
            surveyData:           surveyResponse,
            readinessProfile:     computeReadiness(),
            recurringWeaknesses:  recurringWeaknesses,
            apiContext:           apiCtx,
            coachingBrief:        apiCtx.coachingBrief
        )
    }

    // 5A: When a direct skill signal is present in the user's message, survey-derived weaknesses
    // must not override the user's explicit focus. This is a hard suppression — survey data is
    // silenced for weakPoints only; goals, time, and all other context remain unaffected.
    private func buildCoachContext(for currentMessage: String? = nil,
                                   suppressSurveyWeaknesses: Bool = false) -> CoachContext {
        var context = CoachContext()
        
        // Merge weak points: survey data (first-class) + chat-inferred (secondary).
        // Survey data is more reliable (user intentionally filled it out), so it goes first.
        // Use ordered deduplication — Set() would randomize order and lose the priority signal.
        // 5A override: when the user has named an explicit skill this message, suppress survey
        // weaknesses entirely so they cannot steer the plan away from the stated focus.
        let surveyWeaknesses: [String] = suppressSurveyWeaknesses ? [] : SportWeaknesses.load(for: sport)
        var combined: [String] = []
        var seen = Set<String>()
        for item in surveyWeaknesses + userWeakPoints {
            if seen.insert(item).inserted {
                combined.append(item)
            }
        }
        if !combined.isEmpty {
            context.weakPoints = Array(combined.prefix(6))
        }
        if !userGoals.isEmpty {
            context.goals = userGoals
        }
        if let minutes = availableTimeMinutes {
            context.availableTime = minutes
        }
        if let concern = latestWeakness {
            context.latestConcern = concern
        }
        
        // Build outcome-aware training summary from last 5 sessions (not just the most recent one).
        // TrainingOutcomeAnalyzer detects drill repetition, effort trends, and training gaps so
        // GPT can avoid repeating sessions and build on prior work instead of starting fresh.
        let sessionsKey = "recent_sessions_\(sport.rawValue)"
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let sessions = try? JSONDecoder().decode([SavedSessionData].self, from: data),
           !sessions.isEmpty {
            let summary = TrainingOutcomeAnalyzer.analyze(sessions: sessions)
            let block = summary.briefBlock
            if !block.isEmpty {
                context.recentTraining = block
            } else if let latest = sessions.first {
                context.recentTraining = "\(latest.drillName) - \(latest.duration)min, effort: \(latest.effortLevel)"
            }
        }
        
        // Add wearable/readiness data if available
        let readinessKey = "daily_readiness_\(sport.rawValue)"
        if let readiness = UserDefaults.standard.string(forKey: readinessKey) {
            context.readinessLevel = readiness
        }
        
        // Add HealthKit wearable data if synced
        if let hrData = UserDefaults.standard.object(forKey: "smartwatch_resting_hr") as? Double {
            var wearable = WearableContext()
            wearable.restingHeartRate = hrData
            if let hrv = UserDefaults.standard.object(forKey: "smartwatch_hrv") as? Double {
                wearable.hrv = hrv
            }
            if let sleep = UserDefaults.standard.object(forKey: "smartwatch_sleep_hours") as? Double {
                wearable.sleepHours = sleep
            }
            if let steps = UserDefaults.standard.object(forKey: "smartwatch_steps") as? Int {
                wearable.stepsToday = steps
            }
            context.wearableData = wearable
        }

        // Onboarding survey — sends the athlete's baseline skill profile to the backend.
        // The backend also loads this from DB, but sending from iOS ensures it's present
        // even if the DB query fails or the session is on a new deployment.
        if let survey = surveyResponse {
            context.surveyMainSport = survey.mainSport
            context.surveySkillRatings = survey.skillRatings.isEmpty ? nil : survey.skillRatings
            context.surveyStrengths = survey.strengths.isEmpty ? nil : survey.strengths
            context.surveyWeaknesses = survey.weaknesses.isEmpty ? nil : survey.weaknesses
        }

        // Per-message enrichment: infer intent and semantic concepts from the current user input.
        // These are the highest-priority signals — always derived fresh from what the user just said.
        if let msg = currentMessage {
            let intent = inferIntent(from: msg)
            let concepts = semanticMap(from: msg)
            context.inferredIntent = intent != "general" ? intent : nil
            context.semanticConcepts = concepts.isEmpty ? nil : concepts

            // Build pre-analyzed coaching brief so GPT-4 receives a structured situation
            // description and plans rather than guessing from raw signals.
            context.coachingBrief = buildCoachingBrief(for: msg)

            #if DEBUG
            // Guard: a non-empty user message should always produce a coaching brief.
            // A nil brief means GPT-4 receives no structured situation description and
            // must guess context from raw signals alone — coaching quality degrades silently.
            if context.coachingBrief == nil, !msg.trimmingCharacters(in: .whitespaces).isEmpty {
                print(
                    "⚠️ [CoherenceValidator] AICoachChatView: buildCoachingBrief returned nil " +
                    "for a non-empty message ('\(msg.prefix(40))…'). " +
                    "GPT-4 will receive no structured brief — check buildCoachingBrief fallback paths."
                )
            }
            #endif

            print("📱 [AI Coach] Context built — intent: \(intent), concepts: \(concepts), latestConcern: \(context.latestConcern ?? "none"), weakPoints: \(context.weakPoints ?? []), briefPresent: \(context.coachingBrief != nil)")
        }

        return context
    }
    
    private func saveContext() {
        var context: [String: Any] = [
            "weakPoints": userWeakPoints,
            "goals": userGoals,
            "athleticAttributes": athleticAttributes,
            "recurringWeaknesses": recurringWeaknesses
        ]
        if let minutes = availableTimeMinutes {
            context["availableTimeMinutes"] = minutes
        }
        if let latest = latestWeakness {
            context["latestWeakness"] = latest
        }
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
        if let minutes = context["availableTimeMinutes"] as? Int {
            availableTimeMinutes = minutes
        }
        if let attrs = context["athleticAttributes"] as? [String] {
            athleticAttributes = attrs
        }
        if let latest = context["latestWeakness"] as? String {
            latestWeakness = latest
        }
        if let recurring = context["recurringWeaknesses"] as? [String: Int] {
            recurringWeaknesses = recurring
        }

        // 5E: Apply mention-count decay once per calendar day.
        // This prevents stale signals (mentioned 10+ sessions ago) from permanently
        // dominating focus area derivation over fresh, recent coaching topics.
        applyMentionCountDecayIfNewDay()
    }

    /// Applies MentionCountDecayConfig.decayFactor to all recurringWeaknesses counts,
    /// but only once per calendar day (checked via lastDecayDate in UserDefaults).
    private func applyMentionCountDecayIfNewDay() {
        guard !recurringWeaknesses.isEmpty else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let lastDecay = UserDefaults.standard.object(forKey: mentionDecayDateKey) as? Date
        let alreadyDecayedToday = lastDecay.map { Calendar.current.startOfDay(for: $0) == today } ?? false
        guard !alreadyDecayedToday else { return }

        recurringWeaknesses = MentionCountDecayConfig.apply(to: recurringWeaknesses)
        UserDefaults.standard.set(today, forKey: mentionDecayDateKey)
        print("📉 [5E] Mention-count decay applied — \(recurringWeaknesses.count) concepts, factor \(MentionCountDecayConfig.decayFactor)")
    }
}

// MARK: - Training Outcome Analyzer

/// Analyzes a history of completed training sessions to produce an outcome-aware
/// context summary for the AI Coach. Replaces naive single-session lookup with
/// multi-session trend detection, drill repetition tracking, and effort-arc analysis.
struct TrainingOutcomeSummary {
    let sessionCountLast7Days: Int
    let recentDrillNames: [String]
    let mostRepeatedDrill: String?
    let repetitionCount: Int
    let effortTrend: String          // "improving", "stable", "declining"
    let averageEffortLabel: String   // "low", "moderate", "high"

    var briefBlock: String {
        var lines: [String] = []
        if !recentDrillNames.isEmpty {
            lines.append("RECENT SESSIONS (\(sessionCountLast7Days) in last 7 days): \(recentDrillNames.joined(separator: " → "))")
        }
        if let repeated = mostRepeatedDrill, repetitionCount >= 2 {
            lines.append("DRILL REPETITION: '\(repeated)' done \(repetitionCount)x this week — add a variation or escalate difficulty.")
        }
        if sessionCountLast7Days >= 3 {
            lines.append("EFFORT TREND: \(effortTrend) (\(averageEffortLabel) average). RULE: Do NOT repeat the same drill structure — add complexity or a new variation.")
        }
        if sessionCountLast7Days == 0 {
            lines.append("TRAINING GAP: No sessions logged in 7 days. Re-establish baseline before pushing intensity.")
        }
        return lines.joined(separator: "\n")
    }
}

enum TrainingOutcomeAnalyzer {
    static func analyze(sessions: [SavedSessionData]) -> TrainingOutcomeSummary {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = sessions.filter { $0.date >= sevenDaysAgo }
        let count = recent.count

        let names = recent.prefix(5).map(\.drillName).filter { !$0.isEmpty }
        var drillFrequency: [String: Int] = [:]
        names.forEach { drillFrequency[$0, default: 0] += 1 }
        let uniqueNames = Array(Set(names)).prefix(3).sorted()
        let topEntry = drillFrequency.max(by: { $0.value < $1.value })
        let topDrill = (topEntry?.value ?? 0) >= 2 ? topEntry?.key : nil

        let effortValues: [Double] = recent.prefix(5).compactMap { s in
            switch s.effortLevel.lowercased() {
            case "low", "easy", "1", "2":      return 1
            case "moderate", "medium", "3", "4", "5": return 3
            case "high", "hard", "6", "7", "8", "9", "10": return 5
            default: return nil
            }
        }
        let avg = effortValues.isEmpty ? 3.0 : effortValues.reduce(0, +) / Double(effortValues.count)
        let effortLabel = avg < 2 ? "low" : avg < 4 ? "moderate" : "high"

        var trend = "stable"
        if effortValues.count >= 3 {
            let firstHalf = effortValues.prefix(effortValues.count / 2).reduce(0, +) / Double(effortValues.count / 2)
            let secondHalf = effortValues.suffix(effortValues.count / 2).reduce(0, +) / Double(effortValues.count / 2)
            if secondHalf > firstHalf + 0.5 { trend = "improving" }
            else if secondHalf < firstHalf - 0.5 { trend = "declining" }
        }

        return TrainingOutcomeSummary(
            sessionCountLast7Days: count,
            recentDrillNames: uniqueNames,
            mostRepeatedDrill: topDrill,
            repetitionCount: topEntry?.value ?? 0,
            effortTrend: trend,
            averageEffortLabel: effortLabel
        )
    }
}

// MARK: - AIConsistencyValidator Support (Debug only)
//
// Exposes the real local pipeline to AIConsistencyValidator without changing
// any method visibilities. Swift `private` is file-scoped, so this extension
// in the same file can call all private pipeline functions directly.

#if DEBUG
extension AICoachChatViewModel {
    /// Run the full local coaching pipeline for `message` and return the result.
    ///
    /// Called exclusively by AIConsistencyValidator. Do not call in production code.
    /// Initialise a fresh `AICoachChatViewModel(sport:)` per test case so that
    /// UserDefaults state from real sessions does not contaminate validator results.
    func validatorLocalResponse(message: String, sessionMins: Int = 45) -> CoachMessageResponse {
        let mode        = detectOutputMode(from: message)
        let specificity = SpecificityMode.detect(from: message)
        var areas       = extractAllFocusAreas(from: message)
        if areas.isEmpty { areas = deriveFocusAreasFromContext() }
        return buildPipelineLocalResponse(
            outputMode:      mode,
            focusAreas:      areas,
            totalMins:       sessionMins,
            specificityMode: specificity
        )
    }
}
#endif

#Preview {
    NavigationStack {
        AICoachChatView(sport: .basketball)
    }
}
