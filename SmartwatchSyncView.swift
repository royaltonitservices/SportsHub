// Wearable Sync View
// Premium Feature - Connect fitness trackers and wearables for recovery insights
// Currently supported: Apple Watch / Apple Health
// Future support: Fitbit, Garmin, WHOOP, Oura, and other wearables

import SwiftUI
import Combine
import HealthKit

struct SmartwatchSyncView: View {
    @StateObject private var wearableManager = WearableProviderManager()
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPremiumUpgrade = false

    // Read domain state from the manager
    private var connection: SmartwatchConnection? { wearableManager.connection }
    private var recentData: [BiometricData] { wearableManager.recentData }
    private var recoveryStatus: RecoveryStatus? { wearableManager.recoveryStatus }
    private var isLoading: Bool { wearableManager.isLoading }
    private var localData: NormalizedWearableData? { wearableManager.currentNormalizedData }
    private var lastSyncDate: Date? { wearableManager.lastSyncDate }
    
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
                
                // Recovery Status (from backend)
                if let recovery = recoveryStatus {
                    recoveryCard(recovery)
                } else if let local = localData {
                    // Show local HealthKit data whenever it exists — regardless of backend status.
                    // This ensures data is NEVER hidden from the user after a successful sync.
                    localDataCard(local)
                } else if case .noDataAvailable = wearableManager.connectionState {
                    // Connected + authorized, but HealthKit returned nothing that passed validation.
                    // Distinct from syncFailed: no error occurred, just no data recorded yet.
                    noDataAvailableCard
                }

                // Sync failure banner — shown when sync ran but hit an actual error
                if case .syncFailed(let reason) = wearableManager.connectionState, localData == nil {
                    syncFailedCard(reason: reason)
                }

                // Recent Data (from backend)
                if !recentData.isEmpty {
                    recentDataSection
                }
            }
            .padding()
        }
        .navigationTitle("Wearable Sync")
        .task {
            await wearableManager.load()
        }
        .onChange(of: wearableManager.errorMessage) { _, newValue in
            if let msg = newValue {
                errorMessage = msg
                showError = true
                wearableManager.dismissError()
            }
        }
        .onChange(of: wearableManager.showPremiumUpgrade) { _, newValue in
            if newValue {
                showPremiumUpgrade = true
                wearableManager.showPremiumUpgrade = false
            }
        }
        .sheet(isPresented: $showPremiumUpgrade) {
            PremiumSubscriptionView()
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
            Image(systemName: wearableManager.isHealthKitAuthorized ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundStyle(wearableManager.isHealthKitAuthorized ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(wearableManager.isHealthKitAuthorized ? "HealthKit Authorized" : "HealthKit Not Authorized")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(wearableManager.isHealthKitAuthorized ? "App can read your health data" : "Tap 'Connect Wearable' to authorize")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(wearableManager.isHealthKitAuthorized ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        )
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Connect Your Fitness Tracker")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Sync health and activity data for AI-powered recovery insights")
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
                    Text(conn.provider?.displayName ?? "Connected Device")
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    if let name = conn.deviceName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Connected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await wearableManager.disconnect()
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
                        // force:true — user tap always bypasses the 30s throttle
                        await wearableManager.sync(force: true)
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
        VStack(spacing: Spacing.md) {
            // Current provider: Apple Watch/HealthKit
            Button(action: {
                Task {
                    await wearableManager.connect(.appleWatch)
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
            
            // Future providers indicator
            Text("Additional trackers coming soon: Fitbit, Garmin, WHOOP, Oura")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
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
    
    // MARK: - Local Data Card (shown when backend is unreachable but HealthKit data is available)

    private func localDataCard(_ data: NormalizedWearableData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Health Data")
                        .font(.headline)
                    Text("Synced from HealthKit · backend offline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Fatigue badge reuses statusBadge color logic
                Text(data.fatigueLevel.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(fatigueLevelColor(data.fatigueLevel).opacity(0.2))
                    .foregroundStyle(fatigueLevelColor(data.fatigueLevel))
                    .cornerRadius(8)
            }

            Divider()

            // Biometric grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                if let rhr = data.restingHeartRate {
                    localMetricTile(icon: "heart.fill",
                                    label: "Resting HR",
                                    value: "\(rhr) bpm",
                                    color: .red)
                }
                if let hrv = data.heartRateVariability {
                    localMetricTile(icon: "waveform.path.ecg",
                                    label: "HRV",
                                    value: "\(hrv) ms",
                                    color: .blue)
                }
                if let sleep = data.sleepDurationMinutes {
                    let hours   = sleep / 60
                    let minutes = sleep % 60
                    let display = minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
                    localMetricTile(icon: "moon.fill",
                                    label: "Sleep",
                                    value: display,
                                    color: .purple)
                }
                if let steps = data.steps {
                    localMetricTile(icon: "figure.walk",
                                    label: "Steps",
                                    value: steps >= 1000 ? String(format: "%.1fk", Double(steps) / 1_000) : "\(steps)",
                                    color: .green)
                }
                if let cal = data.activeCalories {
                    localMetricTile(icon: "flame.fill",
                                    label: "Active Cal",
                                    value: "\(cal) kcal",
                                    color: .orange)
                }
                if let readiness = data.readinessScore {
                    localMetricTile(icon: "bolt.fill",
                                    label: "Readiness",
                                    value: "\(Int(readiness))/100",
                                    color: .yellow)
                }
            }

            // Last-sync footer with validation summary
            VStack(alignment: .leading, spacing: 2) {
                if let syncDate = lastSyncDate {
                    let formatter: RelativeDateTimeFormatter = {
                        let f = RelativeDateTimeFormatter()
                        f.unitsStyle = .abbreviated
                        return f
                    }()
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("Last synced \(formatter.localizedString(for: syncDate, relativeTo: Date()))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                // Validation summary — shows exactly what metrics passed quality checks
                if let validation = wearableManager.lastSyncValidation {
                    HStack(spacing: 4) {
                        Image(systemName: validation.hasRecoveryData ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(validation.hasRecoveryData ? .green : .blue)
                        Text(validation.summaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    /// Grid tile used inside localDataCard
    private func localMetricTile(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    // MARK: - No Data Available Card

    /// Displayed when the watch is connected + authorized but HealthKit returned zero usable values.
    /// Different from syncFailedCard (no error occurred) and connectButton (watch IS registered).
    private var noDataAvailableCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected — No Health Data Yet")
                        .font(.headline)
                    Text("Apple Watch is paired but no data was recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("To get health data:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Label("Wear your Apple Watch for at least 1 hour", systemImage: "applewatch")
                Label("Check that Heart Rate is enabled in Health app", systemImage: "heart.fill")
                Label("Open the Health app and verify data appears there first", systemImage: "checkmark.seal")
                Label("Try syncing again after your next workout or sleep", systemImage: "arrow.clockwise")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(action: {
                Task { await wearableManager.sync(force: true) }
            }) {
                HStack {
                    if isLoading { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "arrow.clockwise") }
                    Text("Sync Again")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .disabled(isLoading)
        }
        .padding()
        .background(Color.blue.opacity(0.06))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Sync Failed Card

    /// Displayed when sync ran but returned no data (e.g., watch not worn, user denied access).
    /// Always surfaces the specific reason — never a silent or empty failure.
    private func syncFailedCard(reason: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync Could Not Complete")
                        .font(.headline)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text("Possible reasons:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Label("Apple Watch not worn today", systemImage: "applewatch.slash")
                Label("HealthKit access was denied", systemImage: "lock.fill")
                Label("No health data recorded yet today", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(action: {
                Task {
                    await wearableManager.sync(force: true)
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(Color.orange)
                .cornerRadius(8)
            }
            .disabled(isLoading)
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    /// Maps FatigueLevel enum to a display color (mirrors readinessColor for String)
    private func fatigueLevelColor(_ level: FatigueLevel) -> Color {
        switch level {
        case .low:      return .green
        case .moderate: return .blue
        case .high:     return .orange
        case .extreme:  return .red
        }
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
    
    // MARK: - Helpers
    
    private func deviceIcon(_ type: String) -> String {
        if let provider = WearableProvider(rawValue: type) {
            return provider.icon
        }
        return "figure.run.circle"
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

// MARK: - Smartwatch Error Handling

enum SmartwatchError {
    case permissionDenied
    case healthKitUnavailable
    case notConnected
    case syncTimeout
    case backendUnavailable
    case unsupportedDevice
    case noDataAvailable
    case unknown(String)
    
    static func from(_ error: Error) -> SmartwatchError {
        // Map API errors to smartwatch-specific errors
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                return .permissionDenied
            case .forbidden:
                // 403 could be either HealthKit permission OR premium requirement
                // Check error message to distinguish
                let errorDesc = apiError.localizedDescription.lowercased()
                if errorDesc.contains("premium") {
                    return .unknown("Premium subscription required for smartwatch sync")
                }
                return .permissionDenied
            case .timeout:
                return .syncTimeout
            case .noConnection, .cannotConnectToHost, .dnsLookupFailed:
                return .backendUnavailable
            case .notFound:
                return .notConnected
            default:
                return .unknown(apiError.localizedDescription)
            }
        }
        
        // Check for HealthKit-specific errors
        let nsError = error as NSError
        if nsError.domain == "com.apple.healthkit" {
            return .healthKitUnavailable
        }
        
        return .unknown(error.localizedDescription)
    }
    
    var userFriendlyMessage: String {
        switch self {
        case .permissionDenied:
            return "We need your permission to access health data. Please grant access in your iPhone Settings under Privacy → Health."
        case .healthKitUnavailable:
            return "HealthKit isn't available on this device. An Apple Watch or iPhone with Health app is required."
        case .notConnected:
            return "Your smartwatch isn't connected yet. Tap 'Connect Apple Watch' below to get started."
        case .syncTimeout:
            return "Syncing is taking longer than usual. Make sure your watch is nearby and try again in a moment."
        case .backendUnavailable:
            return "Can't reach the backend server. Make sure the development server is running on localhost:8000, then try again."
        case .unsupportedDevice:
            return "This device isn't supported. SportsHub works with Apple Watch and compatible fitness trackers."
        case .noDataAvailable:
            return "No health data found. Make sure your watch is recording workouts and try syncing again."
        case .unknown:
            return "We're having trouble syncing your watch right now. Try again in a moment, or contact support if this keeps happening."
        }
    }
    
    var actionableNextStep: String? {
        switch self {
        case .permissionDenied:
            return "Open Settings → Privacy → Health to grant access"
        case .healthKitUnavailable:
            return "Use an iPhone or Apple Watch with HealthKit"
        case .notConnected:
            return "Tap 'Connect Apple Watch' to link your device"
        case .syncTimeout:
            return "Make sure your watch is nearby and unlocked"
        case .backendUnavailable:
            return "Check your internet connection"
        case .noDataAvailable:
            return "Record a workout on your watch first"
        default:
            return nil
        }
    }
}

// MARK: - HealthKit Manager

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    @Published var isAuthorized = false

    private init() {
        checkAuthorization()
    }

    /// Determine whether HealthKit permissions have previously been requested.
    ///
    /// IMPORTANT: Apple deliberately hides read-authorization status from apps for user privacy.
    /// `authorizationStatus` returns:
    ///   .notDetermined  — we have never called requestAuthorization() for this type
    ///   .sharingDenied  — we requested access (the dialog was shown); user MAY have allowed reading
    ///                     (Apple uses .sharingDenied even for read-allowed types to prevent
    ///                      apps from inferring whether the user denied a health category)
    ///   .sharingAuthorized — only for WRITE access; never returned for read-only types
    ///
    /// Therefore the only reliable signal is: if status != .notDetermined, we have asked before
    /// and can proceed. Actual data availability is determined by the query results.
    private func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            let status = healthStore.authorizationStatus(for: heartRateType)
            // .notDetermined = never asked; anything else = dialog was shown at least once
            isAuthorized = (status != .notDetermined)
        }
    }
    
    func requestAuthorization() async -> Bool {
        print("🔐 [HealthKit] Requesting authorization...")

        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ [HealthKit] HealthKit not available on this device")
            return false
        }

        // Check if already authorized — skip the dialog if already asked
        if isAuthorized {
            print("✅ [HealthKit] Authorization already granted — skipping dialog")
            return true
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            // Apple does not expose read authorization status for privacy — a successful
            // request() call means the dialog was presented. Queries return empty data
            // if the user denied access, not errors. We consider authorization "done"
            // and let fetch results determine data availability.
            isAuthorized = true
            print("✅ [HealthKit] Authorization request presented — proceeding with queries")
            return true
        } catch {
            print("❌ [HealthKit] Authorization request failed: \(error)")
            return false
        }
    }
    
    func fetchTodayData() async -> [String: Any]? {
        print("📊 [HealthKit] Starting full biometric fetch...")

        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ [HealthKit] HealthKit not available on this device")
            return nil
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        // Apple Watch records resting HR and HRV during sleep (typically 2–6 AM).
        // Querying only from midnight→now misses pre-midnight readings.
        // Use a 24-hour lookback for cardiovascular recovery metrics.
        let cardioStart = calendar.date(byAdding: .hour, value: -24, to: now)!

        var data: [String: Any] = [:]
        var hasAnyData = false

        // ── Heart rate (average today) ────────────────────────────────────────────
        if let heartRate = await fetchQuantity(
            type: .heartRate, start: startOfDay, end: now, option: .discreteAverage
        ) {
            data["heart_rate"] = Int(heartRate)
            hasAnyData = true
            print("[Wearable] Heart rate: \(Int(heartRate)) bpm")
        }

        // ── Resting heart rate (last 24h — logged by watch in early morning) ─────
        if let restingHR = await fetchQuantity(
            type: .restingHeartRate, start: cardioStart, end: now, option: .discreteAverage
        ) {
            data["resting_heart_rate"] = Int(restingHR)
            hasAnyData = true
            print("[Wearable] Resting HR: \(Int(restingHR)) bpm")
        }

        // ── HRV SDNN (last 24h — recorded during sleep) ──────────────────────────
        if let hrv = await fetchQuantity(
            type: .heartRateVariabilitySDNN, start: cardioStart, end: now, option: .discreteAverage
        ) {
            data["hrv"] = Int(hrv)
            hasAnyData = true
            print("[Wearable] HRV: \(Int(hrv)) ms")
        }

        // ── Steps (today from midnight) ───────────────────────────────────────────
        if let steps = await fetchQuantity(
            type: .stepCount, start: startOfDay, end: now, option: .cumulativeSum
        ) {
            data["steps"] = Int(steps)
            hasAnyData = true
            print("[Wearable] Steps: \(Int(steps))")
        }

        // ── Active calories (today) ───────────────────────────────────────────────
        if let calories = await fetchQuantity(
            type: .activeEnergyBurned, start: startOfDay, end: now, option: .cumulativeSum
        ) {
            data["active_calories"] = Int(calories)
            hasAnyData = true
            print("[Wearable] Active calories: \(Int(calories)) kcal")
        }

        // ── Exercise time (today) ─────────────────────────────────────────────────
        if let exerciseTime = await fetchQuantity(
            type: .appleExerciseTime, start: startOfDay, end: now, option: .cumulativeSum
        ) {
            data["exercise_minutes"] = Int(exerciseTime)
            hasAnyData = true
            print("[Wearable] Exercise: \(Int(exerciseTime)) min")
        }

        // ── Sleep — look back 20 hours from now to capture full overnight session ─
        // A person sleeping 10 PM → 7 AM straddles midnight. The old window
        // (yesterday noon → midnight) would miss the 12 AM–7 AM portion.
        // The 20-hour lookback always captures a full overnight session.
        let sleepStart = calendar.date(byAdding: .hour, value: -20, to: now)!
        if let sleepDuration = await fetchSleepDuration(start: sleepStart, end: now) {
            data["sleep_duration"] = Int(sleepDuration * 60) // hours → minutes
            hasAnyData = true
            print("[Wearable] Sleep: \(String(format: "%.1f", sleepDuration)) hours")
        }

        if !hasAnyData {
            print("[Wearable] No health data available from any source")
            #if targetEnvironment(simulator)
            print("[Wearable] Simulator has no real watch data — mock data will be injected")
            #else
            print("[Wearable] Tip: ensure Apple Watch is paired and has recorded data today")
            #endif
            return nil
        }

        print("[Wearable] Fetch complete — \(data.count) metric(s): \(data.keys.joined(separator: ", "))")
        return data
    }
    
    private func fetchQuantity(
        type: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        option: HKStatisticsOptions
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: option
            ) { _, result, error in
                if let error = error {
                    print("⚠️ [HealthKit] Query error for \(type.rawValue): \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let result = result else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let value: Double?
                let unit: HKUnit
                
                // Determine unit based on type
                switch type {
                case .heartRate, .restingHeartRate:
                    unit = HKUnit.count().unitDivided(by: .minute())
                    value = result.averageQuantity()?.doubleValue(for: unit)
                    
                case .heartRateVariabilitySDNN:
                    unit = .secondUnit(with: .milli)
                    value = result.averageQuantity()?.doubleValue(for: unit)
                    
                case .stepCount:
                    unit = .count()
                    value = result.sumQuantity()?.doubleValue(for: unit)
                    
                case .activeEnergyBurned:
                    unit = .kilocalorie()
                    value = result.sumQuantity()?.doubleValue(for: unit)
                    
                case .appleExerciseTime:
                    unit = .minute()
                    value = result.sumQuantity()?.doubleValue(for: unit)
                    
                default:
                    value = result.averageQuantity()?.doubleValue(for: .count())
                }
                
                continuation.resume(returning: value)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func fetchSleepDuration(start: Date, end: Date) async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("⚠️ [HealthKit] Sleep query error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Calculate total sleep time (excluding awake periods)
                var totalSleep: TimeInterval = 0
                for sample in sleepSamples {
                    // Only count actual sleep, not "in bed" or "awake"
                    if sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                        totalSleep += sample.endDate.timeIntervalSince(sample.startDate)
                    }
                }
                
                // Convert to hours
                let hours = totalSleep / 3600
                continuation.resume(returning: hours > 0 ? hours : nil)
            }
            
            healthStore.execute(query)
        }
    }
}

