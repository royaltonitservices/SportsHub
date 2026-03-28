//
//  DisputeHistoryView.swift
//  SportsHub
//
//  Phase 4: View all disputes for current user
//

import SwiftUI

struct DisputeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    
    @State private var disputes: [DisputeResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading disputes...")
                        .tint(Color.appPrimary)
                } else if let errorMessage {
                    errorView(errorMessage)
                } else if disputes.isEmpty {
                    emptyStateView
                } else {
                    disputesList
                }
            }
            .navigationTitle("Dispute History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadDisputes()
            }
        }
    }
    
    private var disputesList: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Summary card
                summaryCard
                
                // Disputes list
                ForEach(disputes) { dispute in
                    disputeCard(dispute)
                }
            }
            .padding(Spacing.md)
        }
    }
    
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                    .foregroundStyle(Color.appPrimary)
                
                Text("Your Dispute Summary")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                
                Spacer()
            }
            
            Divider()
                .padding(.vertical, 4)
            
            HStack(spacing: Spacing.lg) {
                summaryItem(value: "\(disputes.count)", label: "Total", color: .blue)
                summaryItem(value: "\(pendingCount)", label: "Pending", color: .orange)
                summaryItem(value: "\(resolvedCount)", label: "Resolved", color: .green)
            }
            
            if disputes.count > 0 {
                Text("Keep your dispute rate low by submitting accurate scores.")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 4)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func summaryItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var pendingCount: Int {
        disputes.filter { $0.status == "pending" || $0.status == "under_review" }.count
    }
    
    private var resolvedCount: Int {
        disputes.filter { $0.status == "resolved" }.count
    }
    
    private func disputeCard(_ dispute: DisputeResponse) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Status header
            HStack {
                statusBadge(status: dispute.status)
                
                Spacer()
                
                Text(formatDate(dispute.createdAt))
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            
            // Challenge ID
            Text("Match #\(dispute.challengeId.prefix(8))")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.appTextPrimary)
            
            // Reason
            Text(dispute.reason)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Admin notes (if resolved)
            if let adminNotes = dispute.adminNotes, !adminNotes.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .font(.caption)
                        Text("Admin Resolution")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.appPrimary)
                    
                    Text(adminNotes)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Resolved date
            if let resolvedAt = dispute.resolvedAt {
                Text("Resolved: \(formatDate(resolvedAt))")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 2)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(statusColor(dispute.status).opacity(0.3), lineWidth: 1)
        )
    }
    
    private func statusBadge(status: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon(status))
                .font(.caption2)
            Text(status.capitalized.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor(status).opacity(0.15))
        .clipShape(Capsule())
    }
    
    private func statusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "pending":
            return "clock.fill"
        case "under_review":
            return "magnifyingglass.circle.fill"
        case "resolved":
            return "checkmark.circle.fill"
        case "rejected":
            return "xmark.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "pending":
            return Color.orange
        case "under_review":
            return Color.blue
        case "resolved":
            return Color.green
        case "rejected":
            return Color.red
        default:
            return Color.gray
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.green)
            
            VStack(spacing: Spacing.xs) {
                Text("No Disputes")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appTextPrimary)
                
                Text("You haven't had any disputed matches. Keep it up!")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.xl)
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.red)
            
            Text("Failed to Load Disputes")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await loadDisputes()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(Spacing.xl)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
    
    private func loadDisputes() async {
        isLoading = true
        errorMessage = nil
        
        do {
            disputes = try await APIClient.shared.getMyDisputes()
            
            // Sort by created date (most recent first)
            disputes.sort { dispute1, dispute2 in
                let formatter = ISO8601DateFormatter()
                guard let date1 = formatter.date(from: dispute1.createdAt),
                      let date2 = formatter.date(from: dispute2.createdAt) else {
                    return false
                }
                return date1 > date2
            }
        } catch {
            errorMessage = "We couldn't load your disputes. Check your connection and try again."
        }
        
        isLoading = false
    }
}

#Preview {
    DisputeHistoryView()
        .environmentObject(SessionManager.shared)
}
