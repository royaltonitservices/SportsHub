// Smartwatch Sync View
// Premium Feature - HealthKit integration for Apple Watch

import SwiftUI
import HealthKit
import Combine

struct SmartwatchSyncView: View {
    @StateObject private var healthManager = HealthKitManager.shared
    @State private var connection: SmartwatchConnection?
    @State private var recentData: [BiometricData] = []
    @State private var recoveryStatus: RecoveryStatus?
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // Header
                headerSection
                
                // Authorization Status
                authorizationStatusCard
                
                // Connection Status
                if let conn = connection {
                    connectionCard(conn)
                } else {
                    connectButton
                }
                
                // Recovery Status
                if let recovery = recoveryStatus {
                    recoveryCard(recovery)
                }
                
                // Recent Data
                if !recentData.isEmpty {
                    recentDataSection
                }
            }
            .padding()
        }
        .navigationTitle("Smartwatch Sync")
        .task {
            await loadConnection()
            await loadRecoveryStatus()
            await loadRecentData()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Authorization Status Card
    
    private var authorizationStatusCard: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: healthManager.isAuthorized ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(healthManager.isAuthorized ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(healthManager.isAuthorized ? "HealthKit Authorized" : "HealthKit Not Authorized")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(healthManager.isAuthorized ? "App can read your health data" : "Tap 'Connect Apple Watch' to authorize")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(healthManager.isAuthorized ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "applewatch.watchface")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Connect Your Smartwatch")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Sync health data for AI-powered recovery insights and performance predictions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Connection Card
    
    private func connectionCard(_ conn: SmartwatchConnection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: deviceIcon(conn.deviceType))
                    .font(.title)
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading) {
                    Text("Connected")
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    if let name = conn.deviceName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await disconnect()
                    }
                }) {
                    Text("Disconnect")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Last Sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let lastSync = conn.lastSync {
                        Text(formatDate(lastSync))
                            .font(.subheadline)
                    } else {
                        Text("Never")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await syncNow()
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Sync Now")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(isLoading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Connect Button
    
    private var connectButton: some View {
        Button(action: {
            Task {
                await connectAppleWatch()
            }
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "applewatch")
                    Text("Connect Apple Watch")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
        .disabled(isLoading)
    }
    
    // MARK: - Recovery Card
    
    private func recoveryCard(_ recovery: RecoveryStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                
                Text("Recovery Status")
                    .font(.headline)
                
                Spacer()
                
                statusBadge(recovery.fatigueLevel)
            }
            
            if let readiness = recovery.readinessScore {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Readiness Score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(Int(readiness))")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(readinessColor(recovery.fatigueLevel))
                        
                        Text("/ 100")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if let hrv = recovery.sleepQuality {
                metricRow(icon: "moon.fill", label: "Sleep Quality", value: "\(Int(hrv))/100", color: .purple)
            }
            
            Text(recovery.recommendation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Recent Data Section
    
    private var recentDataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Recent Biometric Data")
                .font(.headline)
            
            ForEach(recentData.prefix(7)) { data in
                biometricDataRow(data)
            }
        }
    }
    
    private func biometricDataRow(_ data: BiometricData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(formatDate(data.date))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if let readiness = data.readinessScore {
                    Text("\(Int(readiness))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(readinessColor(data.fatigueLevel ?? "unknown").opacity(0.2))
                        .foregroundStyle(readinessColor(data.fatigueLevel ?? "unknown"))
                        .cornerRadius(6)
                }
            }
            
            HStack(spacing: Spacing.lg) {
                if let hr = data.restingHeartRate {
                    miniMetric(icon: "heart.fill", value: "\(hr)", label: "RHR", color: .red)
                }
                
                if let hrv = data.heartRateVariability {
                    miniMetric(icon: "waveform.path.ecg", value: "\(hrv)", label: "HRV", color: .blue)
                }
                
                if let sleep = data.sleepDuration {
                    miniMetric(icon: "moon.fill", value: "\(sleep/60)h", label: "Sleep", color: .purple)
                }
                
                if let steps = data.steps {
                    miniMetric(icon: "figure.walk", value: "\(steps)", label: "Steps", color: .green)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Helper Views
    
    private func statusBadge(_ status: String) -> some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(readinessColor(status).opacity(0.2))
            .foregroundStyle(readinessColor(status))
            .cornerRadius(8)
    }
    
    private func metricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
            
            Text(label)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
    
    private func miniMetric(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Data Functions
    
    private func loadConnection() async {
        do {
            connection = try await APIClient.shared.getSmartwatchConnection()
        } catch {
            // Not connected yet - that's okay
        }
    }
    
    private func loadRecoveryStatus() async {
        do {
            recoveryStatus = try await APIClient.shared.getRecoveryStatus()
        } catch {
            // No data yet
        }
    }
    
    private func loadRecentData() async {
        do {
            recentData = try await APIClient.shared.getRecentBiometricData(days: 7)
        } catch {
            // No data yet
        }
    }
    
    private func connectAppleWatch() async {
        isLoading = true
        defer { isLoading = false }
        
        // Request HealthKit authorization
        let authorized = await healthManager.requestAuthorization()
        
        guard authorized else {
            errorMessage = "HealthKit authorization denied. Please enable in Settings."
            showError = true
            return
        }
        
        // Connect to backend
        let request = ConnectDeviceRequest(
            deviceType: "apple_watch",
            deviceName: "Apple Watch",
            deviceId: nil,
            accessToken: nil,
            refreshToken: nil
        )
        
        do {
            connection = try await APIClient.shared.connectSmartwatch(request: request)
            
            // Sync initial data
            await syncNow()
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func disconnect() async {
        do {
            _ = try await APIClient.shared.disconnectSmartwatch()
            connection = nil
            recentData = []
            recoveryStatus = nil
        } catch {
            errorMessage = "Failed to disconnect: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func syncNow() async {
        isLoading = true
        defer { isLoading = false }
        
        // Fetch today's health data
        guard await healthManager.fetchTodayData() != nil else {
            errorMessage = "No health data available"
            showError = true
            return
        }
        
        // Sync to backend (would need proper BiometricData encoding)
        // For now, just reload
        await loadRecoveryStatus()
        await loadRecentData()
    }
    
    // MARK: - Helpers
    
    private func deviceIcon(_ type: String) -> String {
        switch type {
        case "apple_watch": return "applewatch"
        case "fitbit": return "watch"
        case "garmin": return "watch"
        default: return "watch"
        }
    }
    
    private func readinessColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "low", "excellent": return .green
        case "medium", "good": return .blue
        case "high", "fair": return .orange
        case "very_high", "poor": return .red
        default: return .gray
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none
        return displayFormatter.string(from: date)
    }
}

// MARK: - HealthKit Manager

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    
    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            return true
        } catch {
            return false
        }
    }
    
    func fetchTodayData() async -> [String: Any]? {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        // Fetch heart rate
        guard let heartRate = await fetchQuantity(
            type: .heartRate,
            start: startOfDay,
            end: now
        ) else {
            return nil
        }
        
        // Fetch HRV
        let hrv = await fetchQuantity(
            type: .heartRateVariabilitySDNN,
            start: startOfDay,
            end: now
        )
        
        // Fetch steps
        let steps = await fetchQuantity(
            type: .stepCount,
            start: startOfDay,
            end: now
        )
        
        return [
            "heart_rate": heartRate,
            "hrv": hrv as Any,
            "steps": steps as Any
        ]
    }
    
    private func fetchQuantity(
        type: HKQuantityTypeIdentifier,
        start: Date,
        end: Date
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, result, _ in
                guard let result = result, let average = result.averageQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let unit: HKUnit
                switch type {
                case .heartRate, .restingHeartRate:
                    unit = HKUnit.count().unitDivided(by: .minute())
                case .heartRateVariabilitySDNN:
                    unit = .secondUnit(with: .milli)
                case .stepCount:
                    unit = .count()
                default:
                    unit = .kilocalorie()
                }
                
                continuation.resume(returning: average.doubleValue(for: unit))
            }
            
            healthStore.execute(query)
        }
    }
}
