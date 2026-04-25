// WearableProviderManager.swift
// SportsHub — Multi-provider wearable architecture
//
// Supported now:   Apple Health / Apple Watch (real HealthKit integration)
// Architected for: WHOOP, Fitbit, Garmin, Oura (stubs; connection pending their SDKs/OAuth)

import SwiftUI
import Combine
import HealthKit

// MARK: - Connection State Machine

enum WearableConnectionState: Equatable {
    case notConnected
    case requestingPermission
    case connecting
    case connected
    case syncing
    case syncFailed(reason: String)
    /// Connected and authorized, but HealthKit returned zero values that passed range validation.
    /// Distinct from .syncFailed (no error) and .notConnected (watch IS registered).
    case noDataAvailable
    case providerNotImplemented
    case unavailableOnDevice

    var displayTitle: String {
        switch self {
        case .notConnected:              return "Not Connected"
        case .requestingPermission:     return "Requesting Permission"
        case .connecting:               return "Connecting..."
        case .connected:                return "Connected"
        case .syncing:                  return "Syncing..."
        case .syncFailed(let reason):   return "Sync Failed: \(reason)"
        case .noDataAvailable:          return "Connected — No Health Data"
        case .providerNotImplemented:   return "Coming Soon"
        case .unavailableOnDevice:      return "Unavailable on This Device"
        }
    }

    var isActive: Bool {
        switch self {
        case .connected, .syncing, .noDataAvailable: return true
        default: return false
        }
    }
}

// MARK: - Normalized Wearable Data
//
// Canonical health data schema used by the AI Coach and training system.
// All provider implementations must map their native data formats to this struct.

struct NormalizedWearableData {
    let date: Date
    let provider: WearableProvider

    // Recovery
    let recoveryScore: Double?       // 0–100 (e.g. WHOOP recovery, Oura readiness)
    let readinessScore: Double?      // 0–100
    let fatigueLevel: FatigueLevel

    // Sleep
    let sleepDurationMinutes: Int?
    let sleepQualityScore: Double?   // 0–100

    // Cardiovascular
    let restingHeartRate: Int?       // bpm
    let avgHeartRate: Int?           // bpm
    let heartRateVariability: Int?   // ms (SDNN or RMSSD depending on device)

    // Activity
    let steps: Int?
    let activeCalories: Int?
    let exerciseMinutes: Int?

    // Derived training guidance
    let intensityRecommendation: WearableIntensityRecommendation
}

// MARK: - Derived Enums

/// Simple fatigue classification derived from biometric signals.
enum FatigueLevel: String {
    case low      = "Low"
    case moderate = "Moderate"
    case high     = "High"
    case extreme  = "Extreme"

    /// Heuristic derivation from available signals.
    /// Lower HRV + higher resting HR + less sleep = higher fatigue.
    static func from(hrv: Int?, rhr: Int?, sleepMinutes: Int?) -> FatigueLevel {
        var score = 0
        if let hrv = hrv        { score += hrv < 40 ? 2 : hrv < 55 ? 1 : 0 }
        if let rhr = rhr        { score += rhr > 65 ? 2 : rhr > 58 ? 1 : 0 }
        if let s   = sleepMinutes { score += s < 360 ? 2 : s < 420 ? 1 : 0 }
        switch score {
        case 0...1: return .low
        case 2...3: return .moderate
        case 4...5: return .high
        default:    return .extreme
        }
    }
}

/// Training intensity guidance computed from recovery signals.
/// Distinct from the DailyReadinessView `TrainingRecommendation` struct (which is a view model).
enum WearableIntensityRecommendation: String {
    case highIntensity     = "High Intensity"
    case moderateIntensity = "Moderate Intensity"
    case lightActivity     = "Light Activity"
    case activeRecovery    = "Active Recovery"
    case fullRest          = "Full Rest"

    static func from(fatigue: FatigueLevel, recoveryScore: Double?) -> WearableIntensityRecommendation {
        let recovery = recoveryScore ?? 50
        switch fatigue {
        case .low:      return recovery > 70 ? .highIntensity : .moderateIntensity
        case .moderate: return recovery > 50 ? .moderateIntensity : .lightActivity
        case .high:     return .activeRecovery
        case .extreme:  return .fullRest
        }
    }
}

// MARK: - Validation Result

/// Result of validating HealthKit query output before it reaches the AI Coach pipeline.
/// Three-tier classification: full recovery data → activity only → no usable data.
///
/// Physiological range checks applied:
///   HRV:        1–500 ms (outside = sensor noise / not recorded)
///   Resting HR: 20–250 bpm
///   Sleep:      60–720 min (1h–12h)
///   Steps:      0–100,000 (sanity cap)
enum WearableValidationResult {
    /// Full recovery metrics available: HRV, resting HR, or sleep passed range checks.
    case valid(metrics: [String])
    /// Only activity data (steps/calories/exercise) — no cardiovascular recovery metrics.
    case activityOnly(metrics: [String])
    /// Authorized + synced, but zero values passed physiological range validation.
    case noData

    var isUsable: Bool {
        switch self {
        case .valid, .activityOnly: return true
        case .noData: return false
        }
    }

    var hasRecoveryData: Bool {
        if case .valid = self { return true }
        return false
    }

    var metricNames: [String] {
        switch self {
        case .valid(let m), .activityOnly(let m): return m
        case .noData: return []
        }
    }

    var summaryText: String {
        switch self {
        case .valid(let m):
            return "Recovery data: \(m.joined(separator: ", "))"
        case .activityOnly(let m):
            return "Activity only: \(m.joined(separator: ", "))"
        case .noData:
            return "No health data available"
        }
    }
}

// MARK: - Provider Protocol

protocol WearableProviderProtocol {
    var provider: WearableProvider { get }
    var isCurrentlySupported: Bool { get }

    func isPermissionGranted() -> Bool
    func requestPermissions() async -> Bool
    func fetchTodayData() async -> NormalizedWearableData?
}

// MARK: - Apple Health Provider (Real Implementation)

final class AppleHealthWearableProvider: WearableProviderProtocol {
    let provider: WearableProvider = .appleWatch
    let isCurrentlySupported: Bool = true

    private let healthManager = HealthKitManager.shared

    func isPermissionGranted() -> Bool {
        healthManager.isAuthorized
    }

    func requestPermissions() async -> Bool {
        await healthManager.requestAuthorization()
    }

    func fetchTodayData() async -> NormalizedWearableData? {
        guard let raw = await healthManager.fetchTodayData() else { return nil }
        let hrv   = raw["hrv"] as? Int
        let rhr   = raw["resting_heart_rate"] as? Int
        let sleep = raw["sleep_duration"] as? Int
        let fatigue = FatigueLevel.from(hrv: hrv, rhr: rhr, sleepMinutes: sleep)
        return NormalizedWearableData(
            date:                     Date(),
            provider:                 .appleWatch,
            recoveryScore:            nil,    // HealthKit doesn't expose a single recovery score
            readinessScore:           nil,
            fatigueLevel:             fatigue,
            sleepDurationMinutes:     sleep,
            sleepQualityScore:        nil,
            restingHeartRate:         rhr,
            avgHeartRate:             raw["heart_rate"] as? Int,
            heartRateVariability:     hrv,
            steps:                    raw["steps"] as? Int,
            activeCalories:           raw["active_calories"] as? Int,
            exerciseMinutes:          raw["exercise_minutes"] as? Int,
            intensityRecommendation:  WearableIntensityRecommendation.from(fatigue: fatigue, recoveryScore: nil)
        )
    }
}

// MARK: - Stub Providers (Architecture placeholder; implementation requires their SDKs/OAuth)

private struct UnimplementedWearableProvider: WearableProviderProtocol {
    let provider: WearableProvider
    let isCurrentlySupported: Bool = false

    func isPermissionGranted() -> Bool { false }
    func requestPermissions() async -> Bool { false }
    func fetchTodayData() async -> NormalizedWearableData? { nil }
}

// MARK: - Provider Factory

extension WearableProvider {
    func makeProviderImpl() -> WearableProviderProtocol {
        switch self {
        case .appleWatch: return AppleHealthWearableProvider()
        default:          return UnimplementedWearableProvider(provider: self)
        }
    }
}

// MARK: - Manager

/// Centralizes all wearable state and business logic that was previously inline in SmartwatchSyncView.
/// Exposes the same @Published properties the view expects, plus new state-machine properties.
@MainActor
final class WearableProviderManager: ObservableObject {

    // MARK: - Existing state (matches SmartwatchSyncView's @State vars)
    @Published var connection: SmartwatchConnection?
    @Published var recentData: [BiometricData] = []
    @Published var recoveryStatus: RecoveryStatus?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showPremiumUpgrade = false

    // MARK: - Extended state (new capability surface)
    @Published var connectionState: WearableConnectionState = .notConnected
    @Published var currentNormalizedData: NormalizedWearableData?
    @Published var activeProvider: WearableProvider?
    @Published var lastSyncDate: Date?
    @Published var lastSyncValidation: WearableValidationResult?

    private var activeProviderImpl: WearableProviderProtocol?
    private let minimumSyncInterval: TimeInterval = 30  // seconds — prevents double-tap duplicates

    /// Passthrough for views that still need to check HealthKit authorization status.
    var isHealthKitAuthorized: Bool {
        HealthKitManager.shared.isAuthorized
    }

    // MARK: - Initial Load

    func load() async {
        async let c: () = loadConnection()
        async let r: () = loadRecoveryStatus()
        async let d: () = loadRecentData()
        _ = await (c, r, d)

        // Auto-sync HealthKit if connected and data is stale (> 30 min since last sync)
        let staleSyncThreshold: TimeInterval = 30 * 60  // 30 minutes
        let needsSync: Bool
        if let last = lastSyncDate {
            needsSync = Date().timeIntervalSince(last) > staleSyncThreshold
        } else {
            needsSync = connection != nil  // Connected but never synced this session
        }

        if needsSync && connection != nil {
            print("[WearableProviderManager] Auto-syncing stale wearable data on load")
            await sync()
        }
    }

    func loadConnection() async {
        do {
            connection = try await APIClient.shared.getSmartwatchConnection()
            if connection != nil {
                connectionState = .connected
                activeProvider = .appleWatch
                activeProviderImpl = AppleHealthWearableProvider()
                print("[Wearable] Backend connection loaded — provider: Apple Watch")
            }
        } catch {
            // Backend unreachable or no connection record.
            // If HealthKit is available and we've previously authorized, set up local-only mode
            // so the user can still sync without seeing "Connect Apple Watch" (which would loop
            // through the permission flow again unnecessarily).
            print("[Wearable] Backend connection load failed: \(error)")
            if HKHealthStore.isHealthDataAvailable() && HealthKitManager.shared.isAuthorized {
                let userId = SessionManager.shared.currentUser?.id.uuidString ?? "local"
                connection = SmartwatchConnection(
                    id: "local-\(userId)",
                    userId: userId,
                    deviceType: "apple_watch",
                    deviceName: "Apple Watch",
                    deviceId: nil,
                    provider: .appleWatch,
                    isActive: true,
                    lastSync: nil,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )
                activeProvider = .appleWatch
                activeProviderImpl = AppleHealthWearableProvider()
                connectionState = .connected
                print("[Wearable] Backend offline — local HealthKit mode active (previously authorized)")
            }
        }
    }

    func loadRecoveryStatus() async {
        do {
            recoveryStatus = try await APIClient.shared.getRecoveryStatus()
        } catch { }
    }

    func loadRecentData() async {
        do {
            recentData = try await APIClient.shared.getRecentBiometricData(days: 7)
        } catch { }
    }

    // MARK: - Connect

    func connect(_ provider: WearableProvider) async {
        guard provider.isCurrentlySupported else {
            connectionState = .providerNotImplemented
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Step 1: Device capability check
        guard HKHealthStore.isHealthDataAvailable() else {
            connectionState = .unavailableOnDevice
            #if targetEnvironment(simulator)
            errorMessage = "Running in iOS Simulator\n\nHealthKit is available in the simulator, but won't have real watch data. On a real device, this connects to your Apple Watch.\n\nYou can still test the UI with simulated data."
            #else
            errorMessage = "HealthKit isn't available on this device. An iPhone with the Health app is required."
            #endif
            return
        }

        let impl = provider.makeProviderImpl()
        activeProviderImpl = impl
        activeProvider = provider

        // Step 2: Permission handling
        // HealthKit hides read-authorization status for privacy. isPermissionGranted() returns
        // true once requestAuthorization() has been called at least once (status != .notDetermined).
        if impl.isPermissionGranted() {
            // Already authorized — skip dialog entirely, proceed directly to sync
            print("[Wearable] Authorization: already granted — skipping permission dialog")
        } else {
            // First time — present the HealthKit permission dialog
            connectionState = .requestingPermission
            print("[Wearable] Authorization: not yet requested — presenting dialog")
            let presented = await impl.requestPermissions()
            if !presented {
                // HealthKit itself returned an error (rare — not available, or iOS internal error)
                connectionState = .notConnected
                errorMessage = "HealthKit authorization request failed. Please try again.\n\nIf this persists, check:\nSettings → Privacy & Security → Health → SportsHub"
                return
            }
            print("[Wearable] Authorization: dialog presented — proceeding with data fetch")
            // Note: we do NOT check if the user allowed or denied — Apple hides this.
            // Queries will return empty data if denied; that's handled in sync().
        }

        // Step 3: Backend registration (best-effort — local HealthKit sync is independent)
        connectionState = .connecting
        let request = ConnectDeviceRequest(
            deviceType: "apple_watch",
            deviceName: "Apple Watch",
            deviceId: nil,
            accessToken: nil,
            refreshToken: nil
        )
        do {
            connection = try await APIClient.shared.connectSmartwatch(request: request)
            print("[Wearable] Backend registration: success")
        } catch let error as APIError {
            print("[Wearable] Backend registration: failed (\(error)) — continuing with local HealthKit sync")
            handleAPIError(error)
            // Do NOT return — HealthKit sync is independent of backend availability
        } catch {
            print("[Wearable] Backend registration: unexpected error — continuing with local sync: \(error)")
        }

        // Step 4: Mark connected and run initial sync (force:true — user just initiated this)
        connectionState = .connected
        print("[Wearable] Starting initial data sync...")
        await sync(force: true)
    }

    // MARK: - Disconnect

    func disconnect() async {
        // Clear local state immediately — this is what the user sees
        connection = nil
        recentData = []
        recoveryStatus = nil
        currentNormalizedData = nil
        connectionState = .notConnected
        activeProvider = nil
        activeProviderImpl = nil
        clearWearableDataFromUserDefaults()

        // Notify backend best-effort
        do {
            _ = try await APIClient.shared.disconnectSmartwatch()
        } catch {
            print("⚠️ [WearableProviderManager] Backend disconnect failed (local state cleared): \(error)")
        }
    }

    // MARK: - Sync

    /// Returns true if enough time has passed since the last sync to allow a background/auto sync.
    /// Manual user-initiated syncs always bypass this with `force: true`.
    var canSync: Bool {
        guard let last = lastSyncDate else { return true }
        return Date().timeIntervalSince(last) > minimumSyncInterval
    }

    /// Sync wearable data now.
    ///
    /// - Parameter force: When `true` (user-initiated), the 30s throttle is bypassed.
    ///   Background/auto syncs use the default `false` and respect the throttle.
    func sync(force: Bool = false) async {
        guard force || canSync else {
            print("[Wearable] Auto-sync skipped — last sync was \(Int(Date().timeIntervalSince(lastSyncDate ?? Date())))s ago (throttle: \(Int(minimumSyncInterval))s). Use force:true to override.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        connectionState = .syncing
        print("[Wearable] Sync started (force: \(force))")

        let impl = activeProviderImpl ?? AppleHealthWearableProvider()

        // Verify HealthKit is available before querying
        guard HKHealthStore.isHealthDataAvailable() else {
            connectionState = .syncFailed(reason: "HealthKit not available on this device")
            print("[Wearable] Sync failed — HealthKit not available")
            return
        }

        // Ensure authorization was requested (may be first sync after cold-launch)
        if !HealthKitManager.shared.isAuthorized {
            print("[Wearable] Authorization: status is not yet determined — requesting now")
            let granted = await impl.requestPermissions()
            if !granted {
                connectionState = .syncFailed(reason: "HealthKit authorization not granted")
                print("[Wearable] Sync failed — HealthKit authorization request failed")
                return
            }
        }

        print("[Wearable] Authorization: granted — executing HealthKit queries")
        let normalized = await impl.fetchTodayData()

        #if targetEnvironment(simulator)
        // Simulator returns nil from HealthKit — inject realistic mock so AI Coach has context
        let effectiveData: NormalizedWearableData? = normalized ?? buildSimulatorMockData()
        let isSimulatorMock = normalized == nil
        #else
        let effectiveData: NormalizedWearableData? = normalized
        let isSimulatorMock = false
        #endif

        guard let data = effectiveData else {
            // Real device returned nil — authorization likely denied or watch not paired
            connectionState = .syncFailed(reason: "No health data returned — ensure Apple Watch is paired and worn")
            lastSyncValidation = .noData
            print("[Wearable] Sync returned nil. Ensure Apple Watch is paired, worn today, and HealthKit access is allowed in Settings → Privacy & Security → Health → SportsHub")
            return
        }

        // ── Validation gate ───────────────────────────────────────────────────────────
        // Classify what data is actually usable before touching UserDefaults or the backend.
        let validation = isSimulatorMock
            ? WearableValidationResult.valid(metrics: ["HRV (sim)", "RHR (sim)", "sleep (sim)"])
            : validateWearableData(data)

        lastSyncValidation = validation
        currentNormalizedData = data

        guard validation.isUsable else {
            // Queries ran but all values were nil or outside physiological ranges.
            // This is NOT a sync failure — the watch is connected, it just has no data yet.
            connectionState = .noDataAvailable
            lastSyncDate = Date()  // Record the attempt so throttle works correctly
            print("[Wearable] Sync complete but no usable data. If wearing your watch, try again after a few minutes.")
            return
        }

        // ── Local persistence (always runs, regardless of backend status) ─────────────
        persistForAICoach(data, validation: validation)
        lastSyncDate = Date()
        if isSimulatorMock {
            print("[Wearable] Simulator — mock health data injected for AI Coach: \(validation.summaryText)")
        } else {
            print("[Wearable] Local sync success — \(validation.summaryText)")
        }

        // ── Backend sync (best-effort — failure is non-fatal) ─────────────────────────
        let syncPayload = buildBiometricData(from: data)
        do {
            _ = try await APIClient.shared.syncBiometricData(data: syncPayload)
            print("[Wearable] Backend sync: success")
            connectionState = .connected
            await loadRecoveryStatus()
            await loadRecentData()
        } catch {
            // Backend offline or endpoint unavailable — local data is already persisted
            connectionState = .connected
            print("[Wearable] Backend sync: failed (local data still available) — \(error)")
        }

        // Refresh connection's lastSync timestamp
        if let conn = connection {
            connection = SmartwatchConnection(
                id: conn.id,
                userId: conn.userId,
                deviceType: conn.deviceType,
                deviceName: conn.deviceName,
                deviceId: conn.deviceId,
                provider: conn.provider,
                isActive: conn.isActive,
                lastSync: ISO8601DateFormatter().string(from: Date()),
                createdAt: conn.createdAt
            )
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Data Validation

    /// Validate HealthKit query results against physiological ranges before persisting.
    /// This is the gate between raw HealthKit output and the AI Coach pipeline.
    ///
    /// Ranges (conservative — catches sensor noise and missing data):
    ///   HRV:        1–500 ms
    ///   Resting HR: 20–250 bpm
    ///   Sleep:      60–720 min (1h–12h)
    ///   Steps:      0–100,000
    private func validateWearableData(_ data: NormalizedWearableData) -> WearableValidationResult {
        var recoveryMetrics: [String] = []
        var activityMetrics: [String] = []

        // Recovery metrics — require physiological plausibility
        if let hrv = data.heartRateVariability, (1...500).contains(hrv) {
            recoveryMetrics.append("HRV \(hrv)ms")
        } else if let hrv = data.heartRateVariability {
            print("[Wearable] Validation: HRV \(hrv)ms out of range [1–500] — discarded")
        }

        if let rhr = data.restingHeartRate, (20...250).contains(rhr) {
            recoveryMetrics.append("RHR \(rhr)bpm")
        } else if let rhr = data.restingHeartRate {
            print("[Wearable] Validation: Resting HR \(rhr)bpm out of range [20–250] — discarded")
        }

        if let sleep = data.sleepDurationMinutes, (60...720).contains(sleep) {
            let h = sleep / 60, m = sleep % 60
            recoveryMetrics.append(m > 0 ? "sleep \(h)h\(m)m" : "sleep \(h)h")
        } else if let sleep = data.sleepDurationMinutes {
            print("[Wearable] Validation: Sleep \(sleep)min out of range [60–720] — discarded")
        }

        // Activity metrics — less strict, but cap steps at 100k
        if let steps = data.steps, steps >= 0 && steps <= 100_000 {
            activityMetrics.append("\(steps) steps")
        }
        if let cal = data.activeCalories, cal >= 0 {
            activityMetrics.append("\(cal) cal")
        }
        if let ex = data.exerciseMinutes, ex >= 0 {
            activityMetrics.append("\(ex)min exercise")
        }

        if !recoveryMetrics.isEmpty {
            let allMetrics = recoveryMetrics + activityMetrics
            print("[Wearable] Validation: VALID — \(allMetrics.joined(separator: ", "))")
            return .valid(metrics: allMetrics)
        } else if !activityMetrics.isEmpty {
            print("[Wearable] Validation: ACTIVITY ONLY — \(activityMetrics.joined(separator: ", "))")
            return .activityOnly(metrics: activityMetrics)
        } else {
            print("[Wearable] Validation: NO DATA — all fields nil or out of physiological range")
            return .noData
        }
    }

    // MARK: - AI Coach Integration

    /// Write validated biometric data to UserDefaults keys that AI Coach context builder reads.
    /// Includes validation metadata so the AI Coach can gate readiness calculations correctly.
    /// Keys must match what AICoachChatViewModel.buildCoachContext() and computeReadiness() expect.
    func persistForAICoach(_ data: NormalizedWearableData, validation: WearableValidationResult) {
        let defaults = UserDefaults.standard

        // Core biometric values (only write if present — don't overwrite with nil)
        if let rhr   = data.restingHeartRate     { defaults.set(Double(rhr),  forKey: "smartwatch_resting_hr") }
        if let hrv   = data.heartRateVariability  { defaults.set(Double(hrv),  forKey: "smartwatch_hrv") }
        if let sleep = data.sleepDurationMinutes  { defaults.set(Double(sleep) / 60.0, forKey: "smartwatch_sleep_hours") }
        if let steps    = data.steps              { defaults.set(steps,    forKey: "smartwatch_steps") }
        if let calories = data.activeCalories     { defaults.set(calories, forKey: "smartwatch_active_calories") }
        if let exercise = data.exerciseMinutes    { defaults.set(exercise, forKey: "smartwatch_exercise_minutes") }
        if let hr       = data.avgHeartRate       { defaults.set(Double(hr), forKey: "smartwatch_avg_hr") }

        // Sync timestamp — AI Coach staleness gate reads this
        defaults.set(Date().timeIntervalSince1970, forKey: "smartwatch_last_sync")

        // Validation metadata — AI Coach reads these to gate readiness scoring
        defaults.set(validation.isUsable,        forKey: "wearable_data_valid")
        defaults.set(validation.hasRecoveryData, forKey: "wearable_has_recovery_data")
        defaults.set(validation.metricNames.joined(separator: ","), forKey: "wearable_available_metrics")

        print("✅ [WearableProviderManager] Data persisted — valid:\(validation.isUsable) recovery:\(validation.hasRecoveryData) metrics:[\(validation.metricNames.joined(separator: ", "))]")
    }

    // MARK: - Private Helpers

    private func handleAPIError(_ error: APIError) {
        switch error {
        case .forbidden:
            let desc = error.errorDescription?.lowercased() ?? ""
            if desc.contains("premium") {
                showPremiumUpgrade = true
            } else {
                errorMessage = "Access denied. Please check your account permissions."
            }
        case .notFound:
            #if DEBUG
            errorMessage = "Backend endpoint not yet implemented.\n\nHealthKit data is still being read locally, but won't sync to the server yet."
            #else
            errorMessage = "Server endpoint not available. Please check for app updates."
            #endif
        case .cannotConnectToHost, .noConnection:
            #if DEBUG
            errorMessage = "Cannot connect to backend server.\n\nMake sure your development server is running:\ncd backend && uvicorn main:app --reload --port 8000\n\nHealthKit data is still being read locally."
            #else
            errorMessage = "Cannot reach the server. Please check your internet connection and try again."
            #endif
        case .timeout:
            errorMessage = "Connection timed out. Please try again."
        default:
            errorMessage = "Connection failed: \(error.userFriendlyMessage)"
        }
    }

    private func buildBiometricData(from data: NormalizedWearableData) -> BiometricData {
        let isoString = ISO8601DateFormatter().string(from: data.date)
        return BiometricData(
            id:                   UUID().uuidString,
            date:                 isoString,
            restingHeartRate:     data.restingHeartRate,
            avgHeartRate:         data.avgHeartRate,
            maxHeartRate:         data.avgHeartRate,
            heartRateVariability: data.heartRateVariability,
            sleepDuration:        data.sleepDurationMinutes,
            deepSleep:            nil,
            remSleep:             nil,
            lightSleep:           nil,
            sleepQualityScore:    nil,
            steps:                data.steps,
            activeCalories:       data.activeCalories,
            totalCalories:        nil,
            exerciseMinutes:      data.exerciseMinutes,
            recoveryScore:        nil,
            trainingStrain:       nil,
            dayStrain:            nil,
            readinessScore:       nil,
            fatigueLevel:         nil,
            performancePrediction: nil,
            createdAt:            isoString
        )
    }

    private func buildSimulatorMockData() -> NormalizedWearableData {
        let hrv   = Int.random(in: 45...75)
        let rhr   = Int.random(in: 55...68)
        let sleep = Int.random(in: 390...480)
        let fatigue = FatigueLevel.from(hrv: hrv, rhr: rhr, sleepMinutes: sleep)
        return NormalizedWearableData(
            date:                    Date(),
            provider:                .appleWatch,
            recoveryScore:           nil,
            readinessScore:          nil,
            fatigueLevel:            fatigue,
            sleepDurationMinutes:    sleep,
            sleepQualityScore:       nil,
            restingHeartRate:        rhr,
            avgHeartRate:            Int.random(in: 72...88),
            heartRateVariability:    hrv,
            steps:                   Int.random(in: 3000...9000),
            activeCalories:          Int.random(in: 250...600),
            exerciseMinutes:         Int.random(in: 15...60),
            intensityRecommendation: WearableIntensityRecommendation.from(fatigue: fatigue, recoveryScore: nil)
        )
    }

    private func clearWearableDataFromUserDefaults() {
        let keys = [
            "smartwatch_resting_hr", "smartwatch_hrv", "smartwatch_sleep_hours",
            "smartwatch_steps", "smartwatch_active_calories", "smartwatch_exercise_minutes",
            "smartwatch_avg_hr", "smartwatch_last_sync",
            // Validation metadata keys
            "wearable_data_valid", "wearable_has_recovery_data", "wearable_available_metrics"
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        lastSyncValidation = nil
        print("🗑️ [WearableProviderManager] Cleared wearable data from UserDefaults")
    }
}
