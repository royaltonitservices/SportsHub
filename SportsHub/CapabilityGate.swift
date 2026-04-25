
//
//  CapabilityGate.swift
//  SportsHub
//
//  SwiftUI view modifier that enforces AppCapability status at the view layer.
//  Use .capabilityGated(_:) on any view or button that backs an AppCapability.
//

import SwiftUI

extension View {
    /// Gates a view based on the current CapabilityStatus for the given capability.
    ///
    /// - `.available` — renders the view normally.
    /// - `.unavailableHidden` — removes the view from the hierarchy entirely (EmptyView).
    ///   No trace of the element remains: no spacing, no tap target, no disclosure.
    /// - `.unavailableComingSoon` — renders the view disabled with a "Coming Soon" badge overlay.
    ///   Use this when the feature is on the confirmed roadmap and user awareness is intentional.
    /// - `.debugOnly` — renders in DEBUG builds only; EmptyView in release.
    @ViewBuilder
    func capabilityGated(_ capability: AppCapability) -> some View {
        switch CapabilityRegistry.status(for: capability) {
        case .available:
            self

        case .unavailableHidden:
            EmptyView()

        case .unavailableComingSoon:
            self
                .disabled(true)
                .opacity(0.5)
                .overlay(alignment: .topTrailing) {
                    Text("Coming Soon")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.appTextSecondary.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(6)
                }
                .allowsHitTesting(false)

        case .debugOnly:
#if DEBUG
            self
#else
            EmptyView()
#endif
        }
    }
}
