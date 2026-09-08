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

    @Test func dobCompletionRetainsTheCorrectAttempt() {
        // Gate 1.3: the DOB completion must resubmit the SAME server-bound attempt + nonce
        // captured in the first authorization — never a freshly minted one.
        let c = AppleOnboardingCoordinator()
        let result = AppleSignInResult(identityToken: "tok", userIdentifier: "u",
                                       email: nil, fullName: nil,
                                       nonce: "raw-nonce-9", attemptId: "attempt-9")
        _ = c.stepForInitial(.dobRequired, result: result)
        #expect(c.resultForCompletion()?.attemptId == "attempt-9")
        #expect(c.resultForCompletion()?.nonce == "raw-nonce-9")
    }
}

// Gate 1.3 — server-bound attempt ownership on the iOS side. Proves the overlap guard,
// the isAuthenticating lifecycle, and per-attempt state reset directly against
// OAuthManager.acquireAppleAttempt (isolated from Apple/UI via an injected provider).
@MainActor
struct OAuthAttemptOwnershipTests {

    // Reference boxes so escaping-provider mutation is unambiguous under strict concurrency.
    private final class IntBox { var n = 0 }
    private final class FlagBox { var on: Bool; init(_ v: Bool) { on = v } }

    @Test func acquireBindsAttemptAndHoldsOwnership() async throws {
        let m = OAuthManager(testAttemptProvider: { ("attempt-1", "nonce-1") })
        let a = try await m.acquireAppleAttempt()
        #expect(a.attemptId == "attempt-1")
        #expect(a.nonce == "nonce-1")
        // The delegate callback reads these — they are bound to THIS acquired attempt.
        #expect(m._testCurrentAttemptId == "attempt-1")
        #expect(m._testCurrentNonce == "nonce-1")
        #expect(m.isAuthenticating == true)   // ownership held until the delegate callback fires
    }

    @Test func overlappingLoginRejectedBeforeCreatingAnotherAttempt() async {
        let calls = IntBox()
        let m = OAuthManager(testAttemptProvider: { calls.n += 1; return ("id", "n") })
        m.isAuthenticating = true            // an authorization is already in flight
        var threw = false
        do { _ = try await m.acquireAppleAttempt() }
        catch { threw = true; #expect(error is OAuthError) }
        #expect(threw)
        #expect(calls.n == 0)                // no second attempt was minted
        #expect(m._testCurrentAttemptId == nil)   // in-flight per-attempt state left untouched
    }

    @Test func attemptFetchFailureClearsStateAndReleasesOwnership() async {
        struct Boom: Error {}
        let m = OAuthManager(testAttemptProvider: { throw Boom() })
        var threw = false
        do { _ = try await m.acquireAppleAttempt() } catch { threw = true }
        #expect(threw)
        #expect(m.isAuthenticating == false)      // ownership released
        #expect(m._testCurrentAttemptId == nil)   // no partial per-attempt state
        #expect(m._testCurrentNonce == nil)
    }

    @Test func freshLoginSucceedsAfterAFailure() async throws {
        let fail = FlagBox(true)
        let m = OAuthManager(testAttemptProvider: {
            if fail.on { struct E: Error {}; throw E() }
            return ("attempt-2", "nonce-2")
        })
        do { _ = try await m.acquireAppleAttempt() } catch { /* expected first failure */ }
        #expect(m.isAuthenticating == false)      // prior failure did not wedge ownership
        fail.on = false
        let a = try await m.acquireAppleAttempt()  // fresh login not blocked
        #expect(a.attemptId == "attempt-2")
        #expect(m._testCurrentAttemptId == "attempt-2")
        #expect(m.isAuthenticating == true)
    }
}

// Gate 1.3 — callback ownership. Each delegate callback is bound to its originating
// authorization (token); a late/duplicate/superseded callback can neither resolve nor
// clear a newer attempt. Drives the production dispatch (deliverAppleResult). Live
// ASAuthorization delegate invocation remains manual/device (Gate 3.2).
@MainActor
struct OAuthCallbackOwnershipTests {

    private final class IntBox { var n = 0 }

    private func sample() -> AppleSignInResult {
        AppleSignInResult(identityToken: "t", userIdentifier: "u", email: nil, fullName: nil)
    }

    @Test func lateCallbackFromSupersededAttemptDoesNotDisturbNewer() async {
        let m = OAuthManager(testAttemptProvider: { ("id", "n") })
        let aFired = IntBox(), bFired = IntBox()
        let tokenA = m._testRegisterAuthorization { _ in aFired.n += 1 }
        #expect(m.deliverAppleResult(token: tokenA, .failure(OAuthError.cancelled)) == true)
        #expect(aFired.n == 1)
        #expect(m._testIsAuthenticating == false)
        // Attempt B begins after A resolved.
        let tokenB = m._testRegisterAuthorization { _ in bFired.n += 1 }
        // A late delivery from the superseded attempt A must be ignored — B stays intact.
        #expect(m.deliverAppleResult(token: tokenA, .success(sample())) == false)
        #expect(aFired.n == 1)                       // A did not fire again
        #expect(bFired.n == 0)                       // B undisturbed
        #expect(m._testHasPendingCompletion == true) // B's completion intact
        #expect(m._testIsAuthenticating == true)
        _ = tokenB
    }

    @Test func cancellationClearsStateAndPermitsFreshLogin() async throws {
        let m = OAuthManager(testAttemptProvider: { ("id2", "n2") })
        let t = m._testRegisterAuthorization { _ in }
        #expect(m.deliverAppleResult(token: t, .failure(OAuthError.cancelled)) == true)
        #expect(m._testIsAuthenticating == false)
        #expect(m._testHasPendingCompletion == false)
        let a = try await m.acquireAppleAttempt()    // fresh login not blocked by the cancel
        #expect(a.attemptId == "id2")
    }

    @Test func duplicateCallbackCannotCompleteTwice() {
        let m = OAuthManager(testAttemptProvider: { ("id", "n") })
        let fired = IntBox()
        let t = m._testRegisterAuthorization { _ in fired.n += 1 }
        #expect(m.deliverAppleResult(token: t, .success(sample())) == true)
        #expect(m.deliverAppleResult(token: t, .success(sample())) == false)  // second ignored
        #expect(fired.n == 1)
    }

    @Test func successfulCallbackCarriesItsOwnAttemptIdAndNonce() async throws {
        let m = OAuthManager(testAttemptProvider: { ("attempt-77", "nonce-77") })
        _ = try await m.acquireAppleAttempt()        // binds per-attempt nonce + attemptId
        var received: AppleSignInResult?
        let t = m._testRegisterAuthorization { r in if case .success(let v) = r { received = v } }
        // Build the result exactly as the delegate does, then dispatch it.
        let built = m._testMakeAppleResult(identityToken: "tok", userIdentifier: "u",
                                           email: nil, fullName: nil)
        #expect(m.deliverAppleResult(token: t, .success(built)) == true)
        #expect(received?.attemptId == "attempt-77")
        #expect(received?.nonce == "nonce-77")
    }
}
