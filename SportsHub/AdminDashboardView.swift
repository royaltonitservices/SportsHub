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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
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
                                value: "1,247",
                                icon: "person.3.fill",
                                color: Color.appPrimary
                            )
                            
                            AdminStatCard(
                                title: "Active Users (24h)",
                                value: "342",
                                icon: "chart.line.uptrend.xyaxis",
                                color: Color.appSuccess
                            )
                            
                            AdminStatCard(
                                title: "Pending Reports",
                                value: "8",
                                icon: "exclamationmark.triangle.fill",
                                color: Color(hex: 0xFFC107)
                            )
                            
                            AdminStatCard(
                                title: "Suspended Accounts",
                                value: "12",
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
                        
                        VStack(spacing: Spacing.sm) {
                            AdminActionRow(
                                action: "Suspended User",
                                target: "@flaggeduser",
                                admin: "Admin",
                                time: "2h ago"
                            )
                            
                            AdminActionRow(
                                action: "Removed Post",
                                target: "Inappropriate content",
                                admin: "Admin",
                                time: "4h ago"
                            )
                            
                            AdminActionRow(
                                action: "Verified Age",
                                target: "@newuser123",
                                admin: "Admin",
                                time: "6h ago"
                            )
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Admin Dashboard")
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
