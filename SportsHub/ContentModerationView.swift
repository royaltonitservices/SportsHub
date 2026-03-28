//
//  ContentModerationView.swift
//  SportsHub
//
//  Content reporting interface for user safety
//

import SwiftUI

// MARK: - Report Content View
struct ReportContentView: View {
    @Environment(\.dismiss) var dismiss
    let contentType: String
    let contentId: String
    let contentPreview: String

    @State private var selectedReason: ReportReason?
    @State private var customReason = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingSuccess = false

    enum ReportReason: String, CaseIterable {
        case spam = "Spam"
        case harassment = "Harassment or Bullying"
        case hateSpeech = "Hate Speech"
        case violence = "Violence or Threats"
        case inappropriate = "Inappropriate Content"
        case impersonation = "Impersonation"
        case falseInfo = "False Information"
        case other = "Other"

        var description: String {
            switch self {
            case .spam:
                return "Unwanted promotional content or repeated messages"
            case .harassment:
                return "Bullying, threats, or harassment"
            case .hateSpeech:
                return "Content attacking people based on identity"
            case .violence:
                return "Violent or threatening content"
            case .inappropriate:
                return "Sexual, graphic, or age-inappropriate content"
            case .impersonation:
                return "Pretending to be someone else"
            case .falseInfo:
                return "Misleading or false information"
            case .other:
                return "Other violation of community guidelines"
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showingSuccess {
                    successView
                } else {
                    reportForm
                }
            }
            .navigationTitle("Report Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if !showingSuccess {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") {
                            submitReport()
                        }
                        .disabled(selectedReason == nil || isSubmitting)
                    }
                }
            }
        }
    }

    // MARK: - Report Form
    private var reportForm: some View {
        Form {
            Section {
                Text(contentPreview)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, Spacing.sm)
            } header: {
                Text("Content Being Reported")
            }

            Section {
                ForEach(ReportReason.allCases, id: \.self) { reason in
                    Button {
                        selectedReason = reason
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reason.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text(reason.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if selectedReason == reason {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } header: {
                Text("Reason for Report")
            }

            if selectedReason == .other {
                Section {
                    TextField("Please describe the issue", text: $customReason, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Additional Details")
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Success View
    private var successView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("Report Submitted")
                .font(.title.weight(.semibold))

            Text("Thank you for helping keep SportsHub safe. Our moderation team will review this report.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, Spacing.md)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Submit Report
    private func submitReport() {
        guard let reason = selectedReason else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let finalReason = reason == .other && !customReason.isEmpty ? customReason : reason.rawValue

                let params = [
                    "content_type": contentType,
                    "content_id": contentId,
                    "reason": finalReason
                ]

                let _: MessageResponse = try await APIClient.shared.post("/moderation/report", body: params)

                showingSuccess = true
            } catch {
                errorMessage = "We couldn't submit your report. Please try again."
            }

            isSubmitting = false
        }
    }
}

// MARK: - Admin Moderation Dashboard View
struct AdminModerationDashboardView: View {
    @StateObject private var sessionManager = SessionManager.shared
    @State private var flags: [ModerationFlagResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filterStatus: String = "pending"

    var body: some View {
        NavigationView {
            VStack {
                // Filter Picker
                Picker("Status", selection: $filterStatus) {
                    Text("Pending").tag("pending")
                    Text("Resolved").tag("resolved")
                    Text("Dismissed").tag("dismissed")
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: filterStatus) { _, _ in
                    loadFlags()
                }

                // Flags List
                if isLoading {
                    ProgressView("Loading reports...")
                } else if let error = errorMessage {
                    ErrorView(message: error) {
                        loadFlags()
                    }
                } else if flags.isEmpty {
                    emptyStateView
                } else {
                    flagsList
                }
            }
            .navigationTitle("Moderation")
            .navigationBarTitleDisplayMode(.large)
            .task {
                loadFlags()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("No \(filterStatus.capitalized) Reports")
                .font(.title2.weight(.semibold))

            Text("All clear in this category")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private var flagsList: some View {
        List(flags) { flag in
            ModerationFlagRowView(flag: flag) {
                loadFlags()
            }
        }
        .listStyle(.plain)
    }

    private func loadFlags() {
        Task {
            isLoading = true
            errorMessage = nil

            do {
                flags = try await APIClient.shared.get("/moderation/flags?status_filter=\(filterStatus)")
            } catch {
                errorMessage = "We couldn't load moderation flags. Check your connection and try again."
            }

            isLoading = false
        }
    }
}

// MARK: - Moderation Flag Row
struct ModerationFlagRowView: View {
    let flag: ModerationFlagResponse
    let onResolved: () -> Void

    @State private var showingActions = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: contentIcon)
                    .foregroundColor(.orange)

                Text(flag.contentType.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(flag.reason)
                .font(.headline)

            Text("Reported by User \(flag.reporterId.prefix(8))")
                .font(.caption)
                .foregroundColor(.secondary)

            if flag.status == "pending" {
                HStack(spacing: Spacing.sm) {
                    Button("Remove Content") {
                        resolveFlag(action: "remove")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button("Dismiss") {
                        resolveFlag(action: "dismiss")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, Spacing.xs)
            } else {
                Text("Status: \(flag.status.capitalized)")
                    .font(.caption)
                    .foregroundColor(flag.status == "resolved" ? .green : .secondary)
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private var contentIcon: String {
        switch flag.contentType {
        case "post": return "doc.text.fill"
        case "message": return "message.fill"
        case "clip": return "video.fill"
        case "user": return "person.fill"
        default: return "flag.fill"
        }
    }

    private var formattedDate: String {
        String(flag.createdAt.prefix(10))
    }

    private func resolveFlag(action: String) {
        Task {
            do {
                let _: MessageResponse = try await APIClient.shared.post("/moderation/flags/\(flag.id)/resolve?action=\(action)", body: nil as String?)
                onResolved()
            } catch {
                print("Failed to resolve flag: \(error)")
            }
        }
    }
}

// MARK: - Moderation Models
struct ModerationFlagResponse: Codable, Identifiable {
    let id: String
    let contentType: String
    let contentId: String
    let reporterId: String
    let reason: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case contentId = "content_id"
        case reporterId = "reporter_id"
        case reason, status
        case createdAt = "created_at"
    }
}

#Preview {
    ReportContentView(
        contentType: "post",
        contentId: "123",
        contentPreview: "This is example content that is being reported"
    )
}
