//
//  AICoachConnectionTestView.swift
//  SportsHub
//
//  Debug view for testing AI Coach backend connection
//  Only available in DEBUG builds
//

#if DEBUG
import SwiftUI

struct AICoachConnectionTestView: View {
    @State private var testResults: [TestResult] = []
    @State private var isTesting = false
    @State private var backendURL = APIConfig.baseURL
    @State private var testMessage = "What should I work on today?"
    @State private var selectedSport = Sport.basketball
    
    var body: some View {
        NavigationView {
            List {
                Section("Configuration") {
                    HStack {
                        Text("Backend URL")
                        Spacer()
                        Text(backendURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Mock Mode")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { DebugSettings.useAICoachMockMode },
                            set: { DebugSettings.useAICoachMockMode = $0 }
                        ))
                    }
                    
                    Picker("Sport", selection: $selectedSport) {
                        ForEach(Sport.allCases, id: \.self) { sport in
                            Text(sport.rawValue).tag(sport)
                        }
                    }
                    
                    TextField("Test Message", text: $testMessage)
                }
                
                Section("Actions") {
                    Button(action: runAllTests) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Run All Tests")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting)
                    
                    Button(action: clearResults) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear Results")
                        }
                    }
                    .disabled(testResults.isEmpty)
                }
                
                Section("Results") {
                    if testResults.isEmpty {
                        Text("No tests run yet")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(testResults) { result in
                            TestResultRow(result: result)
                        }
                    }
                }
            }
            .navigationTitle("AI Coach Connection Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Test Functions
    
    private func runAllTests() {
        testResults.removeAll()
        isTesting = true
        
        Task {
            await runTest("Health Check", test: testHealth)
            await runTest("Backend Connection", test: testBackendConnection)
            await runTest("Auth Token", test: testAuthToken)
            await runTest("Premium Status", test: testPremiumStatus)
            await runTest("AI Coach Message", test: testCoachMessage)
            
            isTesting = false
        }
    }
    
    private func runTest(_ name: String, test: () async -> TestResult) async {
        let result = await test()
        await MainActor.run {
            testResults.append(result)
        }
    }
    
    private func testHealth() async -> TestResult {
        let isHealthy = await DebugSettings.checkBackendConnection()
        return TestResult(
            name: "Health Check",
            passed: isHealthy,
            message: isHealthy ? "Backend is responding" : "Backend is not accessible",
            details: "URL: \(backendURL)/health"
        )
    }
    
    private func testBackendConnection() async -> TestResult {
        guard let url = URL(string: backendURL) else {
            return TestResult(
                name: "Backend Connection",
                passed: false,
                message: "Invalid URL",
                details: backendURL
            )
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return TestResult(
                    name: "Backend Connection",
                    passed: false,
                    message: "Invalid response type",
                    details: nil
                )
            }
            
            let success = (200...299).contains(httpResponse.statusCode)
            return TestResult(
                name: "Backend Connection",
                passed: success,
                message: "HTTP \(httpResponse.statusCode)",
                details: success ? "Backend is online" : "Backend returned error status"
            )
        } catch {
            return TestResult(
                name: "Backend Connection",
                passed: false,
                message: "Connection failed",
                details: error.localizedDescription
            )
        }
    }
    
    private func testAuthToken() async -> TestResult {
        let apiClient = APIClient.shared
        let hasToken = SessionManager.shared.currentUser != nil
        
        return TestResult(
            name: "Auth Token",
            passed: hasToken,
            message: hasToken ? "Authenticated" : "Not logged in",
            details: hasToken ? "Token is set in APIClient" : "Login required for full testing"
        )
    }
    
    private func testPremiumStatus() async -> TestResult {
        let isPremium = StoreManager.shared.isPremium
        
        return TestResult(
            name: "Premium Status",
            passed: isPremium,
            message: isPremium ? "Premium Active" : "Free Tier",
            details: isPremium ? "AI Coach is unlocked" : "AI Coach requires Premium subscription"
        )
    }
    
    private func testCoachMessage() async -> TestResult {
        let apiClient = APIClient.shared
        
        guard SessionManager.shared.currentUser != nil else {
            return TestResult(
                name: "AI Coach Message",
                passed: false,
                message: "Skipped - Not logged in",
                details: "Login required to test this endpoint"
            )
        }
        
        guard StoreManager.shared.isPremium else {
            return TestResult(
                name: "AI Coach Message",
                passed: false,
                message: "Skipped - Premium required",
                details: "AI Coach requires Premium subscription"
            )
        }
        
        do {
            let response = try await apiClient.sendCoachMessage(
                sport: selectedSport,
                message: testMessage,
                context: nil
            )
            
            let hasContent = !response.response.isEmpty
            return TestResult(
                name: "AI Coach Message",
                passed: hasContent,
                message: hasContent ? "Response received" : "Empty response",
                details: hasContent ? "Preview: \(response.response.prefix(100))..." : nil
            )
        } catch let error as APIError {
            let errorMessage: String
            switch error {
            case .notFound:
                errorMessage = "Endpoint not found (404)"
            case .unauthorized:
                errorMessage = "Unauthorized (401)"
            case .forbidden:
                errorMessage = "Forbidden (403) - Premium required?"
            case .timeout:
                errorMessage = "Request timed out"
            case .cannotConnectToHost:
                errorMessage = "Cannot connect to host"
            case .noConnection:
                errorMessage = "No internet connection"
            default:
                errorMessage = error.localizedDescription
            }
            
            return TestResult(
                name: "AI Coach Message",
                passed: false,
                message: errorMessage,
                details: error.errorDescription
            )
        } catch {
            return TestResult(
                name: "AI Coach Message",
                passed: false,
                message: "Unexpected error",
                details: error.localizedDescription
            )
        }
    }
    
    private func clearResults() {
        testResults.removeAll()
    }
}

// MARK: - Test Result Model

struct TestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let message: String
    let details: String?
    let timestamp = Date()
}

struct TestResultRow: View {
    let result: TestResult
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.passed ? .green : .red)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(result.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if result.details != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded, let details = result.details {
                Text(details)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)
            }
            
            Text(result.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 32)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AICoachConnectionTestView()
}

#endif
