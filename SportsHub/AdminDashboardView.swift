//
//  AdminDashboardView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            AdminOverviewView()
                .tabItem {
                    Label("Overview", systemImage: "chart.bar.fill")
                }
                .tag(0)
            
            UserManagementView()
                .tabItem {
                    Label("Users", systemImage: "person.3.fill")
                }
                .tag(1)
            
            AdminModerationDashboardView()
                .tabItem {
                    Label("Moderation", systemImage: "shield.fill")
                }
                .tag(2)
            
            AdminSettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(Color.appPrimary)
    }
}

// MARK: - Admin Overview

struct AdminOverviewView: View {
    @State private var stats: AdminStatsResponse?
    @State private var recentActions: [AdminActionResponse] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if isLoading {
                        ProgressView("Loading admin data...")
                            .padding(Spacing.xl)
                    } else if let error = errorMessage {
                        VStack(spacing: Spacing.md) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            
                            Text("Unable to load admin data")
                                .font(.headline)
                                .foregroundColor(.appTextPrimary)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button(action: loadData) {
                                Text("Retry")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, Spacing.lg)
                                    .padding(.vertical, Spacing.sm)
                                    .background(Color.appPrimary)
                                    .cornerRadius(CornerRadius.md)
                            }
                        }
                        .padding(Spacing.xl)
                    } else if let stats = stats {
                        // Stats Overview
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("Platform Statistics")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: Spacing.md) {
                                AdminStatCard(
                                    title: "Total Users",
                                    value: "\(stats.users.total)",
                                    icon: "person.3.fill",
                                    color: Color.appPrimary
                                )
                                
                                AdminStatCard(
                                    title: "Active Users",
                                    value: "\(stats.users.active)",
                                    icon: "chart.line.uptrend.xyaxis",
                                    color: Color.appSuccess
                                )
                                
                                AdminStatCard(
                                    title: "Pending Reports",
                                    value: "\(stats.moderation.pendingFlags)",
                                    icon: "exclamationmark.triangle.fill",
                                    color: Color(hex: 0xFFC107)
                                )
                                
                                AdminStatCard(
                                    title: "Suspended Accounts",
                                    value: "\(stats.users.suspended)",
                                    icon: "hand.raised.fill",
                                    color: Color.appError
                                )
                            }
                        }
                        
                        // Recent Actions
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("Recent Admin Actions")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appTextPrimary)
                            
                            if recentActions.isEmpty {
                                VStack(spacing: Spacing.sm) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.green)
                                    
                                    Text("No recent admin actions")
                                        .font(.subheadline)
                                        .foregroundColor(.appTextSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(Spacing.xl)
                                .cardBackground()
                            } else {
                                VStack(spacing: Spacing.sm) {
                                    ForEach(recentActions.prefix(10)) { action in
                                        AdminActionRowLive(action: action)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Admin Dashboard")
            .refreshable {
                await loadDataAsync()
            }
        }
        .task {
            await loadDataAsync()
        }
    }
    
    private func loadData() {
        Task {
            await loadDataAsync()
        }
    }
    
    private func loadDataAsync() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let statsRequest = APIClient.shared.getAdminStats()
            async let actionsRequest = APIClient.shared.getAdminActions(limit: 20)
            
            let (fetchedStats, fetchedActions) = try await (statsRequest, actionsRequest)
            
            await MainActor.run {
                self.stats = fetchedStats
                self.recentActions = fetchedActions
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Failed to load admin data. Please check your connection and try again."
            }
        }
    }
}

struct AdminStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.appTextPrimary)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .cardBackground()
    }
}

struct AdminActionRow: View {
    let action: String
    let target: String
    let admin: String
    let time: String
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(action)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                
                Text(target)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(admin)
                    .font(.caption)
                    .foregroundStyle(Color.appPrimary)
                
                Text(time)
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

struct AdminActionRowLive: View {
    let action: AdminActionResponse
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatActionType(action.actionType))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                
                if let reason = action.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .lineLimit(2)
                } else if let targetId = action.targetUserId {
                    Text("User ID: \(targetId.prefix(8))...")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("@\(action.adminUsername)")
                    .font(.caption)
                    .foregroundStyle(Color.appPrimary)
                
                Text(formatTimestamp(action.timestamp))
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func formatActionType(_ type: String) -> String {
        // Convert snake_case to Title Case
        return type.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    
    private func formatTimestamp(_ timestamp: String) -> String {
        // Parse ISO timestamp and convert to relative time
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: timestamp) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: timestamp) else {
                return "Recently"
            }
            return formatRelativeTime(from: date)
        }
        
        return formatRelativeTime(from: date)
    }
    
    private func formatRelativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Admin Settings

struct AdminSettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Role")
                        Spacer()
                        Text("Administrator")
                            .foregroundStyle(Color.appPrimary)
                    }
                    
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(sessionManager.currentUser?.email ?? "")
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                
                Section {
                    Button(action: {
                        sessionManager.logout()
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                            Text("Logout")
                        }
                        .foregroundStyle(Color.appError)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    AdminDashboardView()
        .environmentObject(SessionManager.shared)
}
