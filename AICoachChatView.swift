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
    
    @StateObject private var storeManager = StoreManager.shared
    @StateObject private var viewModel: AICoachChatViewModel
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    
    init(sport: Sport) {
        self.sport = sport
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
                            AICoachMessageBubble(message: message)
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
                .onChange(of: viewModel.messages.count) { _ in
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
                SuggestionChip(text: "How can I improve my technique?") {
                    messageText = "How can I improve my technique?"
                }
                
                SuggestionChip(text: "What should I work on today?") {
                    messageText = "What should I work on today?"
                }
                
                SuggestionChip(text: "Am I ready for a match?") {
                    messageText = "Am I ready for a match?"
                }
            }
        }
        .padding(.vertical, Spacing.xl)
    }
    
    // MARK: - Input Bar
    
    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Message your coach...", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .lineLimit(1...4)
            
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
    
    // MARK: - Actions
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let message = messageText
        messageText = ""
        isInputFocused = false
        
        Task {
            await viewModel.sendMessage(message)
        }
    }
}

// MARK: - Message Bubble

struct AICoachMessageBubble: View {
    let message: AICoachMessage
    
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
                
                // Suggested actions (for AI messages)
                if !message.isUser && !message.suggestedActions.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(message.suggestedActions, id: \.self) { action in
                            ActionChip(text: action)
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
    
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.appAccent.opacity(0.1))
        .foregroundColor(.appAccent)
        .cornerRadius(12)
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
    
    init(sport: Sport) {
        self.sport = sport
        self.storageKey = "ai_coach_messages_\(sport.rawValue)"
        loadMessages()
    }
    
    func sendMessage(_ content: String) async {
        // Add user message
        let userMessage = AICoachMessage(content: content, isUser: true)
        messages.append(userMessage)
        saveMessages()
        
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
            
        } catch {
            print("[AI Coach] Error: \(error)")
            
            // Fallback response
            let fallback = AICoachMessage(
                content: "I'm having trouble connecting right now. Let's try again in a moment!",
                isUser: false
            )
            messages.append(fallback)
            saveMessages()
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
            }
        } catch {
            print("[AI Coach] Checkin error: \(error)")
        }
    }
    
    func clearConversation() {
        messages = []
        proactiveCheckin = nil
        saveMessages()
        
        Task {
            // Call API to clear backend history
            try? await APIClient.shared.clearCoachConversation(sport: sport)
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
}

#Preview {
    NavigationStack {
        AICoachChatView(sport: .basketball)
    }
}
