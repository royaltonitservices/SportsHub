//
//  DebugSettings.swift
//  SportsHub
//
//  Debug configuration for development
//

import Foundation

#if DEBUG
/// Debug settings for development and testing
/// Toggle these to control app behavior during development
struct DebugSettings {
    /// Force AI Coach to use the local coaching engine (skip backend entirely).
    /// When false (default), the app tries the real backend first, then falls back
    /// to the local coaching engine automatically if the backend is unreachable.
    /// Set to true to bypass backend attempts entirely during development.
    static var useAICoachMockMode: Bool {
        get {
            UserDefaults.standard.bool(forKey: "debug_ai_coach_mock_mode")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "debug_ai_coach_mock_mode")
            print("🔧 [Debug] AI Coach local-only mode: \(newValue ? "ENABLED (skipping backend)" : "DISABLED (real backend first)")")
        }
    }
    
    /// Check if backend is reachable
    static func checkBackendConnection() async -> Bool {
        print("🔍 [Debug] Checking backend connection to \(APIConfig.baseURL)...")
        
        guard let url = URL(string: APIConfig.baseURL + "/health") else {
            print("❌ [Debug] Invalid backend URL")
            return false
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ [Debug] Invalid response type")
                return false
            }
            
            print("✅ [Debug] Backend responded with status: \(httpResponse.statusCode)")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("✅ [Debug] Response: \(responseString)")
            }
            
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            print("❌ [Debug] Backend connection failed: \(error.localizedDescription)")
            print("💡 [Debug] Make sure your backend server is running on \(APIConfig.baseURL)")
            return false
        }
    }
    
    /// Check backend and log status
    static func checkAndLogBackendStatus() async {
        let isBackendAvailable = await checkBackendConnection()
        
        if !isBackendAvailable {
            print("⚠️ [Debug] Backend not available — AI Coach will use local coaching engine automatically")
            print("⚠️ [Debug] Smartwatch sync will work locally (data persisted for AI Coach)")
            print("💡 [Debug] Start backend: cd backend && uvicorn main:app --reload --port 8000")
        } else {
            print("✅ [Debug] Backend available — using real API endpoints")
        }
    }
    
    /// Run AIConsistencyValidator at launch: validates all 24 canonical AI path cases
    /// (4 sports × 6 messages) against invariants: mode shape, HIGH specificity markers,
    /// sport confinement, min length, and non-empty suggested actions.
    /// Results are logged to the console. Default: false (expensive at launch).
    static var runAIConsistencyChecks: Bool {
        get {
            UserDefaults.standard.bool(forKey: "debug_ai_consistency_checks")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "debug_ai_consistency_checks")
            print("🔧 [Debug] AI consistency checks: \(newValue ? "ENABLED (runs at next launch)" : "DISABLED")")
        }
    }

    /// Run AIConsistencyValidator at launch: validates all 24 canonical AI path cases
    /// Results are logged to the console. Default: false (expensive at launch).
    static var showTelemetrySummary: Bool {
        get  { UserDefaults.standard.bool(forKey: "debug_show_telemetry_summary") }
        set  { UserDefaults.standard.set(newValue, forKey: "debug_show_telemetry_summary") }
    }

    /// Returns the current 7-day telemetry summary string for display in the debug panel.
    static var telemetrySummary: String {
        CoachTelemetry.debugSummary(lastDays: 7)
    }

    /// Clears all telemetry data. Call from the debug panel to reset counters.
    static func clearTelemetry() {
        CoachTelemetry.clear()
        print("🔧 [Debug] Coach telemetry cleared.")
    }

    /// Print current debug configuration
    static func printConfiguration() {
        print("🔧 [Debug Configuration]")
        print("   Base URL: \(APIConfig.baseURL)")
        print("   AI Coach Local-Only Mode: \(useAICoachMockMode ? "ENABLED" : "DISABLED")")
        print("   Debug Logging: \(APIConfig.enableDebugLogging ? "ENABLED" : "DISABLED")")
    }
}
#endif
