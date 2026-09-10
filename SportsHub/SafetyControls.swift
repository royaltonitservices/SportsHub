//
//  SafetyControls.swift
//  SportsHub
//
//  Gate 1.4E — reusable report/block user-safety controls.
//
//  Report goes through the existing `/moderation/report` path (ReportContentView); block/unblock
//  go through the canonical `/friends/block` + `/friends/unblock` routes. The pure types
//  (ReportTarget, SafetyGuard) and the block controller are unit-testable; the SwiftUI menu wraps
//  them for reuse across DM, friend rows and user-search rows.
//

import SwiftUI
import Combine

// MARK: - Report target (pure, testable)

/// What is being reported. Distinguishes reporting a piece of CONTENT from reporting an ACCOUNT,
/// and maps to the backend `content_type` + `content_id` the moderation route expects.
enum ReportTarget: Equatable {
    case post(String)
    case clip(String)
    case comment(String)
    case user(String)

    var contentType: String {
        switch self {
        case .post: return "post"
        case .clip: return "clip"
        case .comment: return "comment"
        case .user: return "user"
        }
    }

    var contentId: String {
        switch self {
        case .post(let id), .clip(let id), .comment(let id), .user(let id):
            return id
        }
    }

    /// True when this reports a person (account) rather than a piece of content.
    var isAccount: Bool {
        if case .user = self { return true }
        return false
    }
}

// MARK: - Self-action guard (pure, testable)

enum SafetyGuard {
    /// You can never report or block yourself. Fails closed on a missing/blank target id; when the
    /// current user is unknown it errs toward allowing the control (the backend remains
    /// authoritative and rejects a self-target).
    static func canActOn(targetUserId: String?, currentUserId: String?) -> Bool {
        guard let target = targetUserId?.trimmingCharacters(in: .whitespaces), !target.isEmpty else {
            return false
        }
        guard let current = currentUserId?.trimmingCharacters(in: .whitespaces), !current.isEmpty else {
            return true
        }
        return target.lowercased() != current.lowercased()
    }
}

// MARK: - Block action controller (testable via injected perform)

/// Drives a single block through the canonical route with an in-flight guard, honest failure
/// reporting, and a relationship-state refresh signal on confirmed success.
@MainActor
final class BlockActionController: ObservableObject {
    @Published var isBlocking = false
    @Published var didBlock = false
    @Published var errorMessage: String?

    private let perform: (String) async throws -> Void

    init(perform: @escaping (String) async throws -> Void = {
        _ = try await APIClient.shared.blockUser(userId: $0)
    }) {
        self.perform = perform
    }

    /// Returns true ONLY on confirmed success. A second call while one is in flight is a no-op
    /// (duplicate-submission guard). Cancellation is never reported as success.
    @discardableResult
    func block(userId: String) async -> Bool {
        if isBlocking { return false }
        isBlocking = true
        errorMessage = nil
        defer { isBlocking = false }
        do {
            try await perform(userId)
            didBlock = true
            // Blocking severs the friendship server-side and hides shared-group messages; refresh
            // relationship-dependent surfaces so stale cache can't contradict the completed block.
            NotificationCenter.default.post(name: .friendListDidChange, object: nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = "We couldn't block this user. Please try again."
            return false
        }
    }
}

// MARK: - Reusable report + block menu for a user surface

/// An ellipsis menu offering "Report" and "Block" for another user, plus any caller-supplied extra
/// actions (e.g. "Remove Friend"). Handles the report sheet, a destructive block confirmation that
/// explains what blocking does and offers report-before-block, the in-flight guard, and an error
/// alert. `onBlocked` fires only after a confirmed block so the host can refresh/dismiss.
struct UserSafetyMenu<Extra: View>: View {
    let userId: String
    let username: String
    var onBlocked: (() -> Void)?
    @ViewBuilder var extraActions: () -> Extra

    @StateObject private var blocker = BlockActionController()
    @State private var showReport = false
    @State private var showBlockConfirm = false
    @State private var showError = false

    init(userId: String,
         username: String,
         onBlocked: (() -> Void)? = nil,
         @ViewBuilder extraActions: @escaping () -> Extra = { EmptyView() }) {
        self.userId = userId
        self.username = username
        self.onBlocked = onBlocked
        self.extraActions = extraActions
    }

    var body: some View {
        Menu {
            extraActions()
            Button {
                showReport = true
            } label: {
                Label("Report @\(username)", systemImage: "flag")
            }
            Button(role: .destructive) {
                showBlockConfirm = true
            } label: {
                Label("Block @\(username)", systemImage: "slash.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Color.appTextSecondary)
        }
        .accessibilityLabel("Safety options for \(username)")
        .disabled(blocker.isBlocking)
        .confirmationDialog("Block @\(username)?",
                            isPresented: $showBlockConfirm,
                            titleVisibility: .visible) {
            // Report-before-block: blocking would hide this person's content, so keep an
            // immediate reporting path. Blocking never requires a report.
            Button("Report Instead…") { showReport = true }
            Button("Block", role: .destructive) {
                Task {
                    if await blocker.block(userId: userId) {
                        onBlocked?()
                    } else {
                        showError = true
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Blocking stops direct contact and hides this person's messages in groups you "
                 + "share. It won't delete existing messages, and it doesn't hide everything across "
                 + "SportsHub. You can report them first if you'd like.")
        }
        .sheet(isPresented: $showReport) {
            ReportContentView(contentType: "user", contentId: userId, contentPreview: "@\(username)")
        }
        .alert("Couldn't Block", isPresented: $showError, presenting: blocker.errorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }
}
