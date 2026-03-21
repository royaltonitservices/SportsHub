//
//  AdminModels.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import Foundation

// MARK: - User Management Models

struct AdminUserView: Identifiable {
    let id: UUID
    let username: String
    let email: String
    let displayName: String
    let accountStatus: AccountStatus
    let ageVerified: Bool
    let joinDate: Date
    let totalMatches: Int
    let totalPosts: Int
    let totalClips: Int
    let reportsAgainst: Int
    let reportsFiled: Int
    let strikes: Int
    let lastActive: Date
}

enum AccountStatus: String, CaseIterable {
    case active = "Active"
    case suspended = "Suspended"
    case banned = "Banned"
    case shadowBanned = "Shadow Banned"
    case pendingVerification = "Pending Verification"
}

struct AdminAction: Identifiable {
    let id = UUID()
    let adminId: UUID
    let adminName: String
    let targetUserId: UUID?
    let targetContentId: UUID?
    let action: AdminActionType
    let reason: String
    let timestamp: Date
}

enum AdminActionType: String {
    case suspendUser = "Suspend User"
    case banUser = "Ban User"
    case shadowBanUser = "Shadow Ban User"
    case unsuspendUser = "Unsuspend User"
    case removePost = "Remove Post"
    case removeClip = "Remove Clip"
    case removeComment = "Remove Comment"
    case addStrike = "Add Strike"
    case removeStrike = "Remove Strike"
    case resetPassword = "Reset Password"
    case verifyAge = "Verify Age"
    case flagIdentity = "Flag Identity"
    case restoreContent = "Restore Content"
}

// MARK: - Content Moderation Models

struct ReportedContent: Identifiable {
    let id: UUID
    let contentType: ContentType
    let contentId: UUID
    let authorId: UUID
    let authorName: String
    let content: String
    let reportedBy: UUID
    let reporterName: String
    let reportReason: ReportReason
    let reportDate: Date
    let status: ReportStatus
    let aiFlag: AIFlag?
}

enum ContentType: String {
    case post = "Post"
    case clip = "Clip"
    case comment = "Comment"
    case profile = "Profile"
    case message = "Message"
}

enum ReportReason: String, CaseIterable {
    case harassment = "Harassment"
    case spam = "Spam"
    case inappropriateContent = "Inappropriate Content"
    case hateSpeech = "Hate Speech"
    case violence = "Violence"
    case impersonation = "Impersonation"
    case underage = "Underage User"
    case other = "Other"
}

enum ReportStatus: String, CaseIterable {
    case pending = "Pending Review"
    case underReview = "Under Review"
    case resolved = "Resolved"
    case dismissed = "Dismissed"
}

struct AIFlag: Identifiable {
    let id = UUID()
    let flagType: AIFlagType
    let confidence: Double
    let details: String
}

enum AIFlagType: String {
    case profanity = "Profanity"
    case harassment = "Harassment"
    case toxicity = "Toxicity"
    case spam = "Spam"
    case ageInconsistency = "Age Inconsistency"
}

// MARK: - Strike System

struct UserStrike: Identifiable {
    let id = UUID()
    let userId: UUID
    let reason: String
    let issuedBy: UUID
    let issuedDate: Date
    let severity: StrikeSeverity
}

enum StrikeSeverity: String {
    case warning = "Warning"
    case minor = "Minor Violation"
    case major = "Major Violation"
    case severe = "Severe Violation"
}

// MARK: - Suspension

struct Suspension: Identifiable {
    let id = UUID()
    let userId: UUID
    let reason: String
    let startDate: Date
    let endDate: Date?
    let issuedBy: UUID
    let isPermanent: Bool
}

// MARK: - Mock Admin Data (for development)

struct MockAdminData {
    static let users: [AdminUserView] = [
        AdminUserView(
            id: UUID(),
            username: "testuser1",
            email: "test1@example.com",
            displayName: "Test User 1",
            accountStatus: .active,
            ageVerified: true,
            joinDate: Date().addingTimeInterval(-86400 * 30),
            totalMatches: 45,
            totalPosts: 12,
            totalClips: 5,
            reportsAgainst: 0,
            reportsFiled: 1,
            strikes: 0,
            lastActive: Date().addingTimeInterval(-3600)
        ),
        AdminUserView(
            id: UUID(),
            username: "flaggeduser",
            email: "flagged@example.com",
            displayName: "Flagged User",
            accountStatus: .active,
            ageVerified: true,
            joinDate: Date().addingTimeInterval(-86400 * 15),
            totalMatches: 23,
            totalPosts: 8,
            totalClips: 2,
            reportsAgainst: 3,
            reportsFiled: 0,
            strikes: 2,
            lastActive: Date().addingTimeInterval(-7200)
        ),
        AdminUserView(
            id: UUID(),
            username: "suspended_user",
            email: "suspended@example.com",
            displayName: "Suspended User",
            accountStatus: .suspended,
            ageVerified: true,
            joinDate: Date().addingTimeInterval(-86400 * 60),
            totalMatches: 67,
            totalPosts: 34,
            totalClips: 12,
            reportsAgainst: 8,
            reportsFiled: 2,
            strikes: 3,
            lastActive: Date().addingTimeInterval(-86400 * 5)
        )
    ]
    
    static let reportedContent: [ReportedContent] = [
        ReportedContent(
            id: UUID(),
            contentType: .post,
            contentId: UUID(),
            authorId: UUID(),
            authorName: "flaggeduser",
            content: "This is a test post with potentially inappropriate content...",
            reportedBy: UUID(),
            reporterName: "testuser1",
            reportReason: .inappropriateContent,
            reportDate: Date().addingTimeInterval(-7200),
            status: .pending,
            aiFlag: AIFlag(
                flagType: .toxicity,
                confidence: 0.85,
                details: "High toxicity score detected"
            )
        ),
        ReportedContent(
            id: UUID(),
            contentType: .clip,
            contentId: UUID(),
            authorId: UUID(),
            authorName: "flaggeduser",
            content: "Basketball trick shot compilation",
            reportedBy: UUID(),
            reporterName: "testuser1",
            reportReason: .spam,
            reportDate: Date().addingTimeInterval(-14400),
            status: .underReview,
            aiFlag: nil
        )
    ]
}
