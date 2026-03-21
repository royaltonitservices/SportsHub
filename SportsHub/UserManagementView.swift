//
//  UserManagementView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct UserManagementView: View {
    @State private var searchText = ""
    @State private var filterStatus: AccountStatus? = nil
    @State private var selectedUser: AdminUserView? = nil
    @State private var showUserDetail = false
    
    private var filteredUsers: [AdminUserView] {
        var users = MockAdminData.users
        
        if !searchText.isEmpty {
            users = users.filter {
                $0.username.localizedCaseInsensitiveContains(searchText) ||
                $0.email.localizedCaseInsensitiveContains(searchText) ||
                $0.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if let filterStatus {
            users = users.filter { $0.accountStatus == filterStatus }
        }
        
        return users
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.appTextSecondary)
                    
                    TextField("Search users...", text: $searchText)
                        .foregroundStyle(Color.appTextPrimary)
                }
                .padding(Spacing.md)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .padding(Spacing.md)
                
                // Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        FilterChip(
                            title: "All",
                            isSelected: filterStatus == nil,
                            action: { filterStatus = nil }
                        )
                        
                        ForEach(AccountStatus.allCases, id: \.self) { status in
                            FilterChip(
                                title: status.rawValue,
                                isSelected: filterStatus == status,
                                action: { filterStatus = status }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.bottom, Spacing.sm)
                
                // User List
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(filteredUsers) { user in
                            UserManagementRow(user: user)
                                .onTapGesture {
                                    selectedUser = user
                                    showUserDetail = true
                                }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("User Management")
            .sheet(isPresented: $showUserDetail) {
                if let user = selectedUser {
                    UserDetailView(user: user)
                }
            }
        }
    }
}

struct UserManagementRow: View {
    let user: AdminUserView
    
    private var statusColor: Color {
        switch user.accountStatus {
        case .active: return Color.appSuccess
        case .suspended: return Color(hex: 0xFFC107)
        case .banned: return Color.appError
        case .shadowBanned: return Color(hex: 0x9C27B0)
        case .pendingVerification: return Color.appTextSecondary
        }
    }
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Avatar
            AvatarView(name: user.displayName, size: 44)
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.appTextPrimary)
                
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                
                HStack(spacing: Spacing.xs) {
                    if user.strikes > 0 {
                        Label("\(user.strikes) strikes", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.appError)
                    }
                    
                    if user.reportsAgainst > 0 {
                        Label("\(user.reportsAgainst) reports", systemImage: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: 0xFFC107))
                    }
                }
            }
            
            Spacer()
            
            // Status Badge
            Text(user.accountStatus.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : Color.appTextPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.appPrimary : Color.appSurface)
                .clipShape(Capsule())
        }
    }
}

// MARK: - User Detail View

struct UserDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let user: AdminUserView
    @State private var showSuspendDialog = false
    @State private var showBanDialog = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Profile Header
                    VStack(spacing: Spacing.md) {
                        AvatarView(name: user.displayName, size: 96)
                        
                        Text(user.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Text(user.email)
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    // Stats
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: Spacing.md) {
                        StatItem(label: "Matches", value: "\(user.totalMatches)")
                        StatItem(label: "Posts", value: "\(user.totalPosts)")
                        StatItem(label: "Clips", value: "\(user.totalClips)")
                        StatItem(label: "Strikes", value: "\(user.strikes)")
                        StatItem(label: "Reports Against", value: "\(user.reportsAgainst)")
                        StatItem(label: "Reports Filed", value: "\(user.reportsFiled)")
                    }
                    
                    // Admin Actions
                    VStack(spacing: Spacing.md) {
                        Text("Admin Actions")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if user.accountStatus == .suspended {
                            Button(action: {}) {
                                Text("Unsuspend Account")
                                    .frame(maxWidth: .infinity)
                            }
                            .primaryButton()
                        } else if user.accountStatus == .active {
                            Button(action: { showSuspendDialog = true }) {
                                Text("Suspend Account")
                                    .frame(maxWidth: .infinity)
                            }
                            .secondaryButton()
                        }
                        
                        Button(action: {}) {
                            Text("Add Strike")
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButton()
                        
                        Button(action: {}) {
                            Text("Reset Password")
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButton()
                        
                        if user.accountStatus != .banned {
                            Button(action: { showBanDialog = true }) {
                                Text("Ban Account")
                                    .foregroundStyle(Color.appError)
                                    .frame(maxWidth: .infinity)
                            }
                            .secondaryButton()
                        }
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("User Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.appTextPrimary)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md)
        .cardBackground()
    }
}

#Preview {
    UserManagementView()
}
