//
//  IdentityMatch.swift
//  SportsHub
//
//  One canonical primitive for comparing backend user/resource identity.
//

import Foundation

/// Identity equality for SportsHub user/resource IDs. The backend keys identity on
/// UUID columns (`User.id`, `Friendship.user_a_id/user_b_id`, etc.) serialised as
/// LOWERCASE UUID strings, while Swift's `UUID.uuidString` is UPPERCASE — so a plain
/// `==` between the two silently fails. This comparator parses BOTH sides as `UUID`
/// values and compares those, which is case-insensitive by construction.
///
/// Contract (fail-closed — this helper drives ownership and action-target decisions):
/// - `nil` never equals anything, including another `nil`.
/// - A blank / whitespace-only / malformed (non-UUID) string is NOT a valid identity
///   and never matches — including two malformed strings whose text differs only by
///   case. `idsEqual("garbage", "GARBAGE")` is `false`, never `true`.
/// - Two representations of the SAME valid UUID (any casing) match.
/// Use this ONLY for identity IDs — never for usernames or display names.
func idsEqual(_ lhs: String?, _ rhs: String?) -> Bool {
    guard let lhs, let rhs,
          let l = UUID(uuidString: lhs.trimmingCharacters(in: .whitespaces)),
          let r = UUID(uuidString: rhs.trimmingCharacters(in: .whitespaces))
    else { return false }
    return l == r
}

extension FriendshipResponse {
    /// The backend user ID on the other side of this friendship/block relative to
    /// `currentUserId`, using UUID identity matching. Fails closed: returns `nil`
    /// when `currentUserId` matches NEITHER participant (or is nil/malformed), so
    /// callers can never act on a guessed "other user".
    func otherUserId(currentUserId: String?) -> String? {
        if idsEqual(userAId, currentUserId) { return userBId }
        if idsEqual(userBId, currentUserId) { return userAId }
        return nil
    }
}
