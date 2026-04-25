
//
//  SearchScope.swift
//  SportsHub
//
//  Co-locates search placeholder text and actual behavior in one type.
//  The UI placeholder is derived from this enum — it cannot silently diverge
//  from what the search action actually does.
//

import Foundation

/// Describes what a search bar actually searches.
/// Add a new case here when a broader search scope is implemented.
enum SearchScope {

    /// Searches for other users by username or display name.
    /// Backend: GET /users/search
    /// iOS action: opens AddFriendView
    case friendSearch

    /// Placeholder text to display in the search field.
    /// Must accurately describe the actual implemented search behavior.
    var placeholder: String {
        switch self {
        case .friendSearch:
            return "Search friends"
        }
    }
}
