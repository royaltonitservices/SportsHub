#if DEBUG
//
//  CoherenceValidator.swift
//  SportsHub
//
//  Launch-time coherence validator — DEBUG builds only.
//
//  Verifies that architectural invariants established in Phases 1–7 continue
//  to hold as the codebase evolves. Violations print clearly to the console.
//  The entire type is compiled out in release builds.
//
//  Call CoherenceValidator.runLaunchChecks() once at app startup inside
//  a #if DEBUG block. See SportsHubApp.swift for the hook.
//
//  ──────────────────────────────────────────────────────────────
//  Checks performed
//  ──────────────────────────────────────────────────────────────
//  1. CapabilityRegistry completeness
//     Every AppCapability case has an explicit entry in statuses.
//     .available count does not exceed implemented feature count.
//     Every .available capability is backed by a .complete FeatureManifest entry.
//
//  2. FeatureManifest consistency
//     .complete  → all 4 layers present
//     .absent    → not all 4 layers present (would be .partial or .complete)
//     .partial   → at least 1 layer present; if all 4 are present, likely .complete
//
//  3. StorageStrategy disclosure labels
//     All cases produce non-empty label text.
//
//  4. SearchScope placeholder text
//     All scope cases produce non-empty placeholder text.
//

import Foundation

enum CoherenceValidator {

    // MARK: - Internal result types

    private enum Severity { case pass, warn, fail }

    private struct Finding {
        let severity: Severity
        let check: String
        let detail: String?
    }

    // MARK: - Entry point

    static func runLaunchChecks() {
        let divider = String(repeating: "─", count: 62)
        print("\n\(divider)")
        print("🔍  CoherenceValidator — Launch Checks")
        print(divider)

        var findings: [Finding] = []
        findings += checkCapabilityRegistry()
        findings += checkFeatureManifest()
        findings += checkStorageStrategyLabels()
        findings += checkSearchScopePlaceholders()

        for f in findings {
            switch f.severity {
            case .pass:
                print("  ✅ PASS   \(f.check)")
            case .warn:
                print("  ⚠️  WARN   \(f.check)")
                if let d = f.detail { print("            ↳ \(d)") }
            case .fail:
                print("  ❌ FAIL   \(f.check)")
                if let d = f.detail { print("            ↳ \(d)") }
            }
        }

        let passCount = findings.filter { $0.severity == .pass }.count
        let warnCount = findings.filter { $0.severity == .warn }.count
        let failCount = findings.filter { $0.severity == .fail }.count

        print(divider)
        print("  SUMMARY  ✅ \(passCount) passed  ⚠️ \(warnCount) warnings  ❌ \(failCount) failures")
        if failCount > 0 {
            print("  ⛔  \(failCount) coherence failure(s) detected — investigate before shipping")
            assertionFailure(
                "CoherenceValidator: \(failCount) failure(s) detected at launch. " +
                "See console output above for details."
            )
        } else if warnCount > 0 {
            print("  ⚠️  \(warnCount) warning(s) — review before next release")
        } else {
            print("  All coherence checks passed ✓")
        }
        print(divider + "\n")
    }

    // MARK: - Check 1: CapabilityRegistry completeness

    /// Every AppCapability case must have an explicit entry in CapabilityRegistry.statuses.
    /// A missing entry silently defaults to .unavailableHidden — which would hide a real feature.
    private static func checkCapabilityRegistry() -> [Finding] {
        var findings: [Finding] = []

        // 1a — every case must be in the dict
        let allCases = AppCapability.allCases
        let missingEntries = allCases.filter { CapabilityRegistry.statuses[$0] == nil }

        if missingEntries.isEmpty {
            findings.append(.init(
                severity: .pass,
                check: "CapabilityRegistry — all \(allCases.count) capabilities have an explicit status entry",
                detail: nil
            ))
        } else {
            let names = missingEntries.map { "\($0)" }.joined(separator: ", ")
            findings.append(.init(
                severity: .fail,
                check: "CapabilityRegistry — \(missingEntries.count) capability(ies) missing from statuses dict",
                detail: "These will silently default to .unavailableHidden and hide real features: \(names)"
            ))
        }

        // 1c — every .available capability must be backed by a .complete feature
        let availableCapabilities = allCases.filter { CapabilityRegistry.statuses[$0] == .available }
        var unbacked: [(capability: AppCapability, reason: String)] = []

        for cap in availableCapabilities {
            guard let featureId = cap.featureManifestId else {
                unbacked.append((cap, "no featureManifestId mapping — add one in AppCapability.featureManifestId"))
                continue
            }
            guard let feature = FeatureManifest.allFeatures.first(where: { $0.id == featureId }) else {
                unbacked.append((cap, "featureManifestId '\(featureId)' not found in FeatureManifest.allFeatures"))
                continue
            }
            if feature.status != .complete {
                unbacked.append((cap, "'\(feature.name)' is .\(feature.status) — capability should not be .available until feature is .complete"))
            }
        }

        if unbacked.isEmpty {
            findings.append(.init(
                severity: .pass,
                check: "CapabilityRegistry — all .available capabilities backed by .complete features (\(availableCapabilities.count) checked)",
                detail: nil
            ))
        } else {
            for (cap, reason) in unbacked {
                findings.append(.init(
                    severity: .warn,
                    check: "CapabilityRegistry — .available '\(cap)' not backed by .complete feature",
                    detail: reason
                ))
            }
        }

        // 1b — .available count must not exceed implemented feature count
        let availableCount = CapabilityRegistry.statuses.values.filter { $0 == .available }.count
        let implementedCount = FeatureManifest.allFeatures.filter {
            $0.status == .complete || $0.status == .partial
        }.count

        if availableCount <= implementedCount {
            findings.append(.init(
                severity: .pass,
                check: "CapabilityRegistry — .available count (\(availableCount)) within implemented feature count (\(implementedCount))",
                detail: nil
            ))
        } else {
            findings.append(.init(
                severity: .warn,
                check: "CapabilityRegistry — .available count (\(availableCount)) exceeds implemented feature count (\(implementedCount))",
                detail: "Check for capabilities marked .available without a matching FeatureManifest entry"
            ))
        }

        return findings
    }

    // MARK: - Check 2: FeatureManifest consistency

    /// Status and layer presence must agree.
    private static func checkFeatureManifest() -> [Finding] {
        var findings: [Finding] = []

        // 2a — .complete must have all 4 layers
        let completeMissingLayers = FeatureManifest.allFeatures
            .filter { $0.status == .complete && !$0.layers.isFullyImplemented }
            .map(\.name)

        if completeMissingLayers.isEmpty {
            findings.append(.init(
                severity: .pass,
                check: "FeatureManifest — all .complete features have all 4 layers",
                detail: nil
            ))
        } else {
            findings.append(.init(
                severity: .fail,
                check: "FeatureManifest — .complete features missing layers: \(completeMissingLayers.joined(separator: ", "))",
                detail: "Downgrade to .partial or implement the missing layers"
            ))
        }

        // 2b — .absent must not claim all 4 layers
        let absentWithAllLayers = FeatureManifest.allFeatures
            .filter { $0.status == .absent && $0.layers.isFullyImplemented }
            .map(\.name)

        if absentWithAllLayers.isEmpty {
            findings.append(.init(
                severity: .pass,
                check: "FeatureManifest — no .absent features claim all 4 layers",
                detail: nil
            ))
        } else {
            findings.append(.init(
                severity: .fail,
                check: "FeatureManifest — .absent features claim all layers: \(absentWithAllLayers.joined(separator: ", "))",
                detail: "Mark as .partial, or remove incorrectly claimed layers"
            ))
        }

        // 2c — .partial with all 4 layers is likely misclassified as .partial
        let partialWithAllLayers = FeatureManifest.allFeatures
            .filter { $0.status == .partial && $0.layers.isFullyImplemented }
            .map(\.name)

        if partialWithAllLayers.isEmpty {
            findings.append(.init(
                severity: .pass,
                check: "FeatureManifest — no .partial features have all 4 layers (would suggest .complete)",
                detail: nil
            ))
        } else {
            findings.append(.init(
                severity: .warn,
                check: "FeatureManifest — .partial features with all 4 layers: \(partialWithAllLayers.joined(separator: ", "))",
                detail: "If truly end-to-end, upgrade status to .complete"
            ))
        }

        // 2d — .partial with zero layers should be .absent
        let partialWithNoLayers = FeatureManifest.allFeatures
            .filter { f in
                f.status == .partial &&
                !f.layers.hasUI &&
                !f.layers.hasViewModel &&
                !f.layers.hasAPIClient &&
                !f.layers.hasBackend
            }
            .map(\.name)

        if partialWithNoLayers.isEmpty {
            findings.append(.init(
                severity: .pass,
                check: "FeatureManifest — all .partial features have at least 1 layer",
                detail: nil
            ))
        } else {
            findings.append(.init(
                severity: .warn,
                check: "FeatureManifest — .partial features with zero layers: \(partialWithNoLayers.joined(separator: ", "))",
                detail: "A feature with no layers should be .absent"
            ))
        }

        return findings
    }

    // MARK: - Check 3: StorageStrategy disclosure labels

    /// Disclosure labels must be non-empty. A blank label would render invisible text
    /// in views that surface disclosure information to the user.
    private static func checkStorageStrategyLabels() -> [Finding] {
        let cases: [(StorageStrategy, String)] = [
            (.localOnly,        "localOnly"),
            (.syncedToBackend,  "syncedToBackend"),
            (.hybrid,           "hybrid"),
        ]
        let emptyLabels = cases
            .filter { $0.0.disclosureLabel.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(\.1)

        if emptyLabels.isEmpty {
            return [.init(
                severity: .pass,
                check: "StorageStrategy — all \(cases.count) cases produce non-empty disclosure labels",
                detail: nil
            )]
        } else {
            return [.init(
                severity: .fail,
                check: "StorageStrategy — empty disclosure label(s): \(emptyLabels.joined(separator: ", "))",
                detail: "Views referencing disclosureLabel will render blank text — fix StorageStrategy.swift"
            )]
        }
    }

    // MARK: - Check 4: SearchScope placeholder text

    /// Placeholder text must be non-empty and must accurately describe the actual search behavior.
    /// An empty placeholder silently breaks the search field UX.
    private static func checkSearchScopePlaceholders() -> [Finding] {
        let cases: [(SearchScope, String)] = [
            (.friendSearch, "friendSearch"),
        ]
        let emptyPlaceholders = cases
            .filter { $0.0.placeholder.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(\.1)

        if emptyPlaceholders.isEmpty {
            return [.init(
                severity: .pass,
                check: "SearchScope — all \(cases.count) scope(s) have non-empty placeholder text",
                detail: nil
            )]
        } else {
            return [.init(
                severity: .fail,
                check: "SearchScope — empty placeholder for: \(emptyPlaceholders.joined(separator: ", "))",
                detail: "Fix placeholder text in SearchScope.swift"
            )]
        }
    }
}
#endif
