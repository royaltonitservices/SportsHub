//
//  SafetyControlsTests.swift
//  SportsHubTests
//
//  Gate 1.4E — logic tests for the report/block safety controls.
//
//  These exercise the PURE mapping (ReportTarget), the self-action guard, and the
//  BlockActionController's async behavior (success / server-denial / network-failure /
//  cancellation / duplicate-submission prevention / state refresh) via an injected `perform`.
//  They are view-model/logic tests — NOT a substitute for UI/E2E proof of the actual controls.
//

import Testing
import Foundation
@testable import SportsHub

// MARK: - ReportTarget mapping (pure)

@Suite("ReportTarget mapping")
struct ReportTargetTests {
    @Test("content types map to backend content_type")
    func contentTypes() {
        #expect(ReportTarget.post("p").contentType == "post")
        #expect(ReportTarget.clip("c").contentType == "clip")
        #expect(ReportTarget.comment("k").contentType == "comment")
        #expect(ReportTarget.user("u").contentType == "user")
    }

    @Test("content id is carried verbatim")
    func contentIds() {
        #expect(ReportTarget.post("p1").contentId == "p1")
        #expect(ReportTarget.user("u9").contentId == "u9")
    }

    @Test("only a user target is an account report")
    func accountVsContent() {
        #expect(ReportTarget.user("u").isAccount == true)
        #expect(ReportTarget.post("p").isAccount == false)
        #expect(ReportTarget.comment("k").isAccount == false)
        #expect(ReportTarget.clip("c").isAccount == false)
    }
}

// MARK: - Self-action guard (pure)

@Suite("SafetyGuard.canActOn")
struct SafetyGuardTests {
    @Test("cannot act on yourself")
    func selfBlocked() {
        #expect(SafetyGuard.canActOn(targetUserId: "abc", currentUserId: "abc") == false)
        #expect(SafetyGuard.canActOn(targetUserId: "ABC", currentUserId: "abc") == false) // case-insensitive
    }

    @Test("can act on a different user")
    func otherAllowed() {
        #expect(SafetyGuard.canActOn(targetUserId: "abc", currentUserId: "xyz") == true)
    }

    @Test("blank/nil target fails closed")
    func blankTarget() {
        #expect(SafetyGuard.canActOn(targetUserId: "", currentUserId: "abc") == false)
        #expect(SafetyGuard.canActOn(targetUserId: "   ", currentUserId: "abc") == false)
        #expect(SafetyGuard.canActOn(targetUserId: nil, currentUserId: "abc") == false)
    }

    @Test("unknown current user still allows a valid target (backend remains authoritative)")
    func unknownCurrent() {
        #expect(SafetyGuard.canActOn(targetUserId: "abc", currentUserId: nil) == true)
        #expect(SafetyGuard.canActOn(targetUserId: "abc", currentUserId: "") == true)
    }
}

// MARK: - helpers for controller tests

private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private struct DenialError: Error {}

// MARK: - BlockActionController behavior

@Suite("BlockActionController")
struct BlockActionControllerTests {

    @Test("confirmed success sets didBlock, clears flags, no error")
    @MainActor
    func success() async {
        let counter = CallCounter()
        let controller = BlockActionController(perform: { _ in await counter.increment() })
        let ok = await controller.block(userId: "u1")
        #expect(ok == true)
        #expect(controller.didBlock == true)
        #expect(controller.isBlocking == false)
        #expect(controller.errorMessage == nil)
        #expect(await counter.count == 1)
    }

    @Test("server denial returns false with an actionable error, never a false success")
    @MainActor
    func serverDenial() async {
        let controller = BlockActionController(perform: { _ in throw DenialError() })
        let ok = await controller.block(userId: "u1")
        #expect(ok == false)
        #expect(controller.didBlock == false)
        #expect(controller.isBlocking == false)
        #expect(controller.errorMessage != nil)
    }

    @Test("network failure is reported, not swallowed")
    @MainActor
    func networkFailure() async {
        let controller = BlockActionController(perform: { _ in throw URLError(.notConnectedToInternet) })
        let ok = await controller.block(userId: "u1")
        #expect(ok == false)
        #expect(controller.errorMessage != nil)
        #expect(controller.didBlock == false)
    }

    @Test("cancellation is never reported as success and shows no spurious error")
    @MainActor
    func cancellation() async {
        let controller = BlockActionController(perform: { _ in throw CancellationError() })
        let ok = await controller.block(userId: "u1")
        #expect(ok == false)
        #expect(controller.didBlock == false)
        #expect(controller.errorMessage == nil)
    }

    @Test("a second block while one is in flight is a no-op (duplicate-submission guard)")
    @MainActor
    func duplicatePrevented() async {
        let counter = CallCounter()
        let gate = Gate()
        let controller = BlockActionController(perform: { _ in
            await counter.increment()
            await gate.wait()               // hold the first call in flight
        })

        async let first = controller.block(userId: "u1")
        while !controller.isBlocking { await Task.yield() }   // ensure first is in flight

        let second = await controller.block(userId: "u1")     // must be rejected immediately
        #expect(second == false)

        await gate.open()
        let firstResult = await first
        #expect(firstResult == true)
        #expect(await counter.count == 1)                     // perform ran exactly once
    }
}
