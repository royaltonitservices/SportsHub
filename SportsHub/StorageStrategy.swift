
//
//  StorageStrategy.swift
//  SportsHub
//
//  Typed source of truth for how a feature persists data.
//  Views must render disclosureLabel instead of hardcoding persistence descriptions.
//  Change the case assignment when an implementation changes — all labels update automatically.
//

import Foundation

/// Describes how a feature stores and syncs its data.
enum StorageStrategy {

    /// Data lives in UserDefaults on this device only.
    /// Lost on reinstall; not available on other devices.
    case localOnly

    /// The backend database is the authoritative copy.
    /// The app may hold a local display cache, but the server owns the state.
    case syncedToBackend

    /// A local cache is the primary runtime store; the backend syncs when
    /// online and wins on conflict. Survives offline use.
    case hybrid

    /// Human-readable disclosure label for display in the UI.
    /// Never hardcode these strings in a view — reference this property instead.
    var disclosureLabel: String {
        switch self {
        case .localOnly:
            return "Stored on this device · not synced"
        case .syncedToBackend:
            return "Synced to your account"
        case .hybrid:
            return "Synced when online · available offline"
        }
    }
}
