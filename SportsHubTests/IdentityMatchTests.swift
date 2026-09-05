//
//  IdentityMatchTests.swift
//  SportsHubTests
//
//  Regression guard for the backend-ID vs Swift-UUID casing bug class.
//  Swift's UUID.uuidString is uppercase; the backend serialises UUIDs lowercase.
//  All identity comparisons route through idsEqual / FriendshipResponse.otherUserId,
//  so these pure tests protect every call site at once.
//

import Testing
@testable import SportsHub

struct IdentityMatchTests {

    @Test func lowercaseEqualsLowercase() {
        #expect(idsEqual("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                         "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    @Test func uppercaseSwiftMatchesLowercaseBackend() {
        // The exact production scenario: Swift UUID.uuidString vs backend id.
        #expect(idsEqual("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                         "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    @Test func mixedCaseMatches() {
        #expect(idsEqual("AaAaAaAa-bBbB-cccc-dddd-eeeeeeeeeeee",
                         "aaaaaaaa-BbBb-CCCC-DDDD-EEEEEEEEEEEE"))
    }

    @Test func differentIdsDoNotMatch() {
        #expect(!idsEqual("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                          "ffffffff-bbbb-cccc-dddd-eeeeeeeeeeee"))
    }

    @Test func nilNeverMatches() {
        #expect(!idsEqual(nil, "aaaa"))
        #expect(!idsEqual("aaaa", nil))
        #expect(!idsEqual(nil, nil))
    }

    @Test func blankStringsNeverMatch() {
        // A `?? ""` fallback must never make two "unknown" users look like the same
        // user, and a blank must never match a real id.
        #expect(!idsEqual("", ""))
        #expect(!idsEqual("   ", "   "))
        #expect(!idsEqual("", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        #expect(!idsEqual("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "  "))
    }

    @Test func malformedIdsFailClosed() {
        // Non-UUID identity strings must never compare equal — not even when their
        // text is identical or differs only by case. Fail closed, never fold garbage.
        #expect(!idsEqual("garbage-user", "garbage-user"))
        #expect(!idsEqual("garbage-user", "GARBAGE-USER"))
        #expect(!idsEqual("not-a-uuid", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        // A valid UUID vs a truncated/partial one must not match.
        #expect(!idsEqual("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                          "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeee"))
    }

    // Pairwise "other user" resolution used by friends / group / matchmaking /
    // challenge-creation surfaces. Current user is given in UPPERCASE (as the app
    // supplies UUID.uuidString) while the friendship ids are lowercase.
    private func friendship(_ a: String, _ b: String) -> FriendshipResponse {
        FriendshipResponse(
            id: "f1", userAId: a, userBId: b,
            userAUsername: "aU", userBUsername: "bU",
            userADisplayName: "A", userBDisplayName: "B",
            status: "accepted", createdAt: "2026-01-01T00:00:00Z"
        )
    }

    @Test func otherUserWhenCurrentIsUserA() {
        let f = friendship("aaaaaaaa-1111-1111-1111-111111111111",
                           "bbbbbbbb-2222-2222-2222-222222222222")
        #expect(f.otherUserId(currentUserId: "AAAAAAAA-1111-1111-1111-111111111111")
                == "bbbbbbbb-2222-2222-2222-222222222222")
    }

    @Test func otherUserWhenCurrentIsUserB() {
        let f = friendship("aaaaaaaa-1111-1111-1111-111111111111",
                           "bbbbbbbb-2222-2222-2222-222222222222")
        #expect(f.otherUserId(currentUserId: "BBBBBBBB-2222-2222-2222-222222222222")
                == "aaaaaaaa-1111-1111-1111-111111111111")
    }

    @Test func otherUserNilWhenCurrentIsNeitherParticipant() {
        // Fail closed: a current user on neither side yields NO match — the helper
        // must not silently pick a side, or an action could target a bystander.
        let f = friendship("aaaaaaaa-1111-1111-1111-111111111111",
                           "bbbbbbbb-2222-2222-2222-222222222222")
        #expect(f.otherUserId(currentUserId: "cccccccc-3333-3333-3333-333333333333") == nil)
    }

    @Test func otherUserNilWhenCurrentIdMalformed() {
        let f = friendship("aaaaaaaa-1111-1111-1111-111111111111",
                           "bbbbbbbb-2222-2222-2222-222222222222")
        #expect(f.otherUserId(currentUserId: "not-a-uuid") == nil)
        #expect(f.otherUserId(currentUserId: nil) == nil)
    }
}

// Gate 1.2 — first-time Apple onboarding continuity. Proves the two-phase
// (authorize → DOB → complete) flow reuses the SAME Apple authorization result and
// never treats an expiry/cancel as success. Tests the exact logic AuthenticationView
// runs (it delegates to AppleOnboardingCoordinator).
@MainActor
struct AppleOnboardingCoordinatorTests {

    private func makeResult(_ token: String = "apple-token-1") -> AppleSignInResult {
        AppleSignInResult(identityToken: token, userIdentifier: "user-1",
                          email: "a@example.com", fullName: "A Athlete")
    }

    @Test func dobRequiredRetainsFirstResult() {
        let c = AppleOnboardingCoordinator()
        let result = makeResult()
        let step = c.stepForInitial(.dobRequired, result: result)
        #expect(step == .needsDateOfBirth)
        // (A) the first authorization result is retained after dob_required
        #expect(c.pendingResult?.identityToken == "apple-token-1")
    }

    @Test func completionSubmitsTheSamePendingResult() {
        let c = AppleOnboardingCoordinator()
        let result = makeResult("apple-token-XYZ")
        _ = c.stepForInitial(.dobRequired, result: result)
        // (B/C) completion re-uses the SAME retained result — no fresh authorization.
        #expect(c.resultForCompletion()?.identityToken == "apple-token-XYZ")
        #expect(c.resultForCompletion()?.userIdentifier == result.userIdentifier)
    }

    @Test func successfulCompletionClearsPending() {
        let c = AppleOnboardingCoordinator()
        _ = c.stepForInitial(.dobRequired, result: makeResult())
        let step = c.stepForCompletion(.authenticated(token: "session-jwt"))
        #expect(step == .authenticated(token: "session-jwt"))
        // (D) successful completion clears pending state
        #expect(c.resultForCompletion() == nil)
    }

    @Test func cancelClearsPending() {
        let c = AppleOnboardingCoordinator()
        _ = c.stepForInitial(.dobRequired, result: makeResult())
        c.cancel()
        // (E) cancellation clears pending state safely
        #expect(c.resultForCompletion() == nil)
    }

    @Test func expiredOrFailedCompletionClearsPendingAndRequiresFreshAuth() {
        let c = AppleOnboardingCoordinator()
        _ = c.stepForInitial(.dobRequired, result: makeResult())
        // (F/G) expiry/401/network failure clears pending — no partial success, and a
        // fresh authorization is required (resultForCompletion is now nil).
        c.completionFailed()
        #expect(c.resultForCompletion() == nil)
    }

    @Test func incompleteCompletionIsFailureNotSuccess() {
        let c = AppleOnboardingCoordinator()
        _ = c.stepForInitial(.dobRequired, result: makeResult())
        // A backend identity_incomplete/dob_required on completion is a failure, and
        // pending is still cleared — it is never treated as an authenticated session.
        #expect(c.stepForCompletion(.identityIncomplete) == .failed)
        #expect(c.resultForCompletion() == nil)

        let c2 = AppleOnboardingCoordinator()
        _ = c2.stepForInitial(.dobRequired, result: makeResult())
        #expect(c2.stepForCompletion(.dobRequired) == .failed)
        #expect(c2.resultForCompletion() == nil)
    }

    @Test func immediateAuthenticationDoesNotRetainResult() {
        let c = AppleOnboardingCoordinator()
        // A returning user (authenticated on first exchange) never enters DOB flow.
        let step = c.stepForInitial(.authenticated(token: "jwt"), result: makeResult())
        #expect(step == .authenticated(token: "jwt"))
        #expect(c.resultForCompletion() == nil)
    }
}
