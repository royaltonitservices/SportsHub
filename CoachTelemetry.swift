// CoachTelemetry.swift
// SportsHub — Phase 12
//
// Lightweight telemetry layer for product decisions.
// All data stored locally in UserDefaults — no external service required.
// Query methods return computed summaries for the DebugSettings panel and product reviews.
//
// To view: open DebugSettings and toggle "Show Telemetry Summary".
// To reset: CoachTelemetry.clear()

import Foundation

// MARK: - Telemetry Entry

/// A single recorded telemetry event. Uses flat fields (not nested enums)
/// to keep Codable synthesis trivial and storage readable.
struct TelemetryEntry: Codable {
    let eventName: String
    let sport: String
    let timestamp: Date
    /// Flexible key-value metadata — differs per event type.
    let metadata: [String: String]
}

// MARK: - Telemetry Recording API

/// All telemetry recording and querying goes through this namespace.
/// Recording is fire-and-forget — failures are silent.
enum CoachTelemetry {
    private static let storageKey = "coach_telemetry_v1"
    private static let maxEntries = 500

    // MARK: — Recording

    /// GPT path returned a successful response.
    static func recordGPTSuccess(sport: Sport) {
        record("gpt_success", sport: sport)
    }

    /// Local coaching path was used (GPT unavailable, failed, or validation rejected).
    static func recordLocalFallback(sport: Sport, reason: String) {
        record("local_fallback", sport: sport, metadata: ["reason": reason])
    }

    /// GPT response violated the coaching contract.
    static func recordGPTViolation(sport: Sport, rule: String, severity: String) {
        record("gpt_violation", sport: sport, metadata: ["rule": rule, "severity": severity])
    }

    /// Injury language was detected in a user message.
    static func recordInjuryContext(sport: Sport) {
        record("injury_context", sport: sport)
    }

    /// Overtraining risk was detected.
    static func recordOvertrainingDetected(sport: Sport, sessionCount: Int) {
        record("overtraining", sport: sport, metadata: ["session_count": "\(sessionCount)"])
    }

    /// A safety coaching mode was activated.
    static func recordSafetyMode(sport: Sport, mode: String) {
        record("safety_mode", sport: sport, metadata: ["mode": mode])
    }

    /// Athlete provided thumbs up/down feedback on a response.
    static func recordFeedback(sport: Sport, helpful: Bool, focusArea: String?) {
        var meta: [String: String] = ["helpful": helpful ? "1" : "0"]
        if let area = focusArea { meta["focus_area"] = area }
        record("feedback", sport: sport, metadata: meta)
    }

    /// Athlete updated their training profile survey from Settings.
    static func recordSurveyUpdated(sport: Sport, changedSkillCount: Int) {
        record("survey_updated", sport: sport, metadata: ["changed_skills": "\(changedSkillCount)"])
    }

    /// High-specificity mode was activated for a session.
    static func recordHighSpecificity(sport: Sport) {
        record("high_specificity", sport: sport)
    }

    /// A coaching session was started (first message sent).
    static func recordSessionStarted(sport: Sport, priorMessageCount: Int) {
        record("session_started", sport: sport, metadata: ["prior_messages": "\(priorMessageCount)"])
    }

    /// GPT response failed the post-response contract validator (one or more critical violations).
    /// Distinct from per-violation recording — this event fires once per validated response that fails.
    static func recordGPTValidationFail(sport: Sport, violationCount: Int) {
        record("gpt_validation_fail", sport: sport, metadata: ["violation_count": "\(violationCount)"])
    }

    /// An inline repair was applied to a GPT response (e.g. football constraint repair).
    static func recordGPTRepairApplied(sport: Sport, rule: String) {
        record("gpt_repair_applied", sport: sport, metadata: ["rule": rule])
    }

    /// GPT path fell back to the local path due to a validation failure.
    /// Use this event (not `recordLocalFallback`) to distinguish validation-triggered fallbacks
    /// from network/API failures.
    static func recordGPTFallbackToLocal(sport: Sport, reason: String) {
        record("gpt_fallback_to_local", sport: sport, metadata: ["reason": reason])
    }

    /// Football constraint repair specifically failed — the response could not be made safe.
    static func recordFootballConstraintRepairFailed(sport: Sport) {
        record("football_repair_failed", sport: sport)
    }

    /// Session depth — how many messages deep the conversation went.
    /// Record at conversation end or when the user navigates away.
    static func recordSessionDepth(sport: Sport, messageCount: Int) {
        record("session_depth", sport: sport, metadata: ["message_count": "\(messageCount)"])
    }

    /// A backend API call failed (network or HTTP error).
    static func recordEndpointFailure(sport: Sport, endpoint: String, statusCode: Int?) {
        var meta = ["endpoint": endpoint]
        if let code = statusCode { meta["status_code"] = "\(code)" }
        record("endpoint_failure", sport: sport, metadata: meta)
    }

    // MARK: — Constrained Retry Events

    /// iOS started a constrained GPT retry after first-attempt contract validation failure.
    static func recordConstrainedRetryStarted(sport: Sport) {
        record("constrained_retry_started", sport: sport)
    }

    /// Constrained retry returned a GPT response that passed contract validation.
    static func recordConstrainedRetrySucceeded(sport: Sport) {
        record("constrained_retry_succeeded", sport: sport)
    }

    /// Constrained retry also failed validation or had a network error — local fallback used.
    static func recordConstrainedRetryFailed(sport: Sport) {
        record("constrained_retry_failed", sport: sport)
    }

    /// Pre-pipeline intent gate classified a message before the coaching pipeline ran.
    /// bucket: one of greeting_social / arithmetic_factual / off_topic_redirect / unclear / coaching_likely
    static func recordPrePipelineIntent(bucket: String, sport: Sport) {
        record("pre_pipeline_intent", sport: sport, metadata: ["bucket": bucket])
    }

    // MARK: — Internal Write

    private static func record(
        _ eventName: String,
        sport: Sport,
        metadata: [String: String] = [:]
    ) {
        let entry = TelemetryEntry(
            eventName: eventName,
            sport: sport.rawValue,
            timestamp: Date(),
            metadata: metadata
        )
        // Local storage — source of truth
        var existing = loadEntries()
        existing.append(entry)
        if existing.count > maxEntries {
            existing = Array(existing.suffix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        // External: fire-and-forget POST to backend telemetry route.
        // Failure is silently ignored — local storage is the authoritative record.
        fireAndForget(entry)
    }

    /// Posts a single telemetry entry to the backend POST /telemetry/event endpoint.
    /// Completely non-blocking — a network failure is silently discarded.
    /// The local UserDefaults write is the source of truth; this is a supplemental export.
    private static func fireAndForget(_ entry: TelemetryEntry) {
        guard let url = URL(string: APIConfig.baseURL + "/telemetry/event") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "event_name": entry.eventName,
            "sport":      entry.sport,
            "timestamp":  iso.string(from: entry.timestamp),
            "metadata":   entry.metadata,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    // MARK: — Loading

    static func loadEntries() -> [TelemetryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([TelemetryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    // MARK: — Queries

    /// Returns (GPT success count, local fallback count) for the last N days.
    static func gptVsLocalRate(lastDays: Int) -> (gpt: Int, local: Int) {
        let recent = entriesSince(days: lastDays)
        let gpt   = recent.filter { $0.eventName == "gpt_success" }.count
        let local = recent.filter { $0.eventName == "local_fallback" }.count
        return (gpt, local)
    }

    /// Returns frequency of injury context detections per total sessions.
    static func injuryContextRate(lastDays: Int) -> Double {
        let recent   = entriesSince(days: lastDays)
        let sessions = recent.filter { $0.eventName == "gpt_success" || $0.eventName == "local_fallback" }.count
        let injury   = recent.filter { $0.eventName == "injury_context" }.count
        guard sessions > 0 else { return 0 }
        return Double(injury) / Double(sessions)
    }

    /// Returns GPT violation counts grouped by rule name.
    static func gptViolationSummary(lastDays: Int) -> [String: Int] {
        var summary: [String: Int] = [:]
        for entry in entriesSince(days: lastDays) where entry.eventName == "gpt_violation" {
            let rule = entry.metadata["rule"] ?? "unknown"
            summary[rule, default: 0] += 1
        }
        return summary
    }

    /// Returns safety mode activation counts grouped by mode.
    static func safetyModeDistribution(lastDays: Int) -> [String: Int] {
        var summary: [String: Int] = [:]
        for entry in entriesSince(days: lastDays) where entry.eventName == "safety_mode" {
            let mode = entry.metadata["mode"] ?? "unknown"
            summary[mode, default: 0] += 1
        }
        return summary
    }

    /// Returns helpful vs not-helpful feedback counts.
    static func feedbackRatio(lastDays: Int) -> (helpful: Int, notHelpful: Int) {
        var helpful = 0; var notHelpful = 0
        for entry in entriesSince(days: lastDays) where entry.eventName == "feedback" {
            if entry.metadata["helpful"] == "1" { helpful += 1 } else { notHelpful += 1 }
        }
        return (helpful, notHelpful)
    }

    /// Returns GPT validation fail rate: validation_fails / (gpt_success + gpt_fallback_to_local).
    static func gptValidationFailRate(lastDays: Int) -> Double {
        let recent  = entriesSince(days: lastDays)
        let total   = recent.filter { $0.eventName == "gpt_success" || $0.eventName == "gpt_fallback_to_local" }.count
        let fails   = recent.filter { $0.eventName == "gpt_validation_fail" }.count
        guard total > 0 else { return 0 }
        return Double(fails) / Double(total)
    }

    /// Returns average session depth over the last N days.
    static func averageSessionDepth(lastDays: Int) -> Double {
        let depths = entriesSince(days: lastDays)
            .filter { $0.eventName == "session_depth" }
            .compactMap { Int($0.metadata["message_count"] ?? "") }
        guard !depths.isEmpty else { return 0 }
        return Double(depths.reduce(0, +)) / Double(depths.count)
    }

    /// Returns a formatted multi-line summary for the debug panel.
    static func debugSummary(lastDays: Int = 7) -> String {
        let (gpt, local) = gptVsLocalRate(lastDays: lastDays)
        let total  = gpt + local
        let gptPct = total > 0 ? Int(Double(gpt) / Double(total) * 100) : 0
        let injuryPct = Int(injuryContextRate(lastDays: lastDays) * 100)
        let violations = gptViolationSummary(lastDays: lastDays)
        let safety = safetyModeDistribution(lastDays: lastDays)
        let (helpful, notHelpful) = feedbackRatio(lastDays: lastDays)

        var lines = ["=== Coach Telemetry (last \(lastDays)d) ==="]
        lines.append("GPT path: \(gpt)/\(total) (\(gptPct)%)   Local: \(local)/\(total)")
        lines.append("Injury context: \(injuryPct)% of sessions")
        if !violations.isEmpty {
            let vs = violations.sorted { $0.value > $1.value }.map { "\($0.key):\($0.value)" }.joined(separator: " ")
            lines.append("GPT violations: \(vs)")
        } else {
            lines.append("GPT violations: none")
        }
        if !safety.isEmpty {
            let ss = safety.sorted { $0.value > $1.value }.map { "\($0.key):\($0.value)" }.joined(separator: " ")
            lines.append("Safety modes: \(ss)")
        }
        lines.append("Feedback: \(helpful)👍  \(notHelpful)👎")
        let failRate = Int(gptValidationFailRate(lastDays: lastDays) * 100)
        lines.append("GPT validation fail rate: \(failRate)%")
        let avgDepth = averageSessionDepth(lastDays: lastDays)
        lines.append(String(format: "Avg session depth: %.1f messages", avgDepth))
        let footballFails = entriesSince(days: lastDays).filter { $0.eventName == "football_repair_failed" }.count
        if footballFails > 0 { lines.append("Football repair failures: \(footballFails)") }
        return lines.joined(separator: "\n")
    }

    // MARK: — Utilities

    private static func entriesSince(days: Int) -> [TelemetryEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return loadEntries().filter { $0.timestamp >= cutoff }
    }

    /// Clears all telemetry data. Use for testing or privacy reset.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Outcome-Aware Progression Stage Deriver

/// Derives a coaching ProgressionStage from real training evidence rather than
/// from raw mention frequency alone.
///
/// Priority: session count → feedback quality → mentionCount (weak fallback)
///
///   Stage 1 — Baseline:    <2 completed sessions or no evidence
///   Stage 2 — Building:    2–4 sessions AND positive feedback trend
///   Stage 3 — Progressive: 5+ sessions AND positive or neutral feedback
///
/// mentionCount is a tie-breaker only — it can push within a stage boundary
/// but cannot override session count evidence.
enum OutcomeAwareProgressionStage {

    static func derive(
        mentionCount: Int,
        sessionCount: Int,
        feedbackRatio: (helpful: Int, notHelpful: Int)
    ) -> Int {
        // No session evidence → baseline regardless of mentions
        if sessionCount == 0 { return 1 }

        let total    = feedbackRatio.helpful + feedbackRatio.notHelpful
        // Positive feedback ratio: > 50% helpful (or no feedback yet)
        let positive = total == 0 || (Double(feedbackRatio.helpful) / Double(total) > 0.5)

        switch sessionCount {
        case 1:
            // One session → still baseline unless they've talked about it a lot
            return mentionCount >= 5 ? 2 : 1
        case 2...4:
            // Building phase — feedback quality determines stage ceiling
            return positive ? 2 : 1
        default:
            // 5+ sessions → progressive if feedback is good; building if not
            return positive ? 3 : 2
        }
    }
}
