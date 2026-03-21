//
//  SettingsView.swift
//  SportsHub
//
//  Settings and preferences
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true

    var body: some View {
        List {
            Section("Appearance") {
                Toggle(isOn: $isDarkMode) {
                    HStack {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(.appPrimary)
                        Text("Dark Mode")
                    }
                }

                HStack {
                    Image(systemName: "paintpalette.fill")
                        .foregroundColor(.appPrimary)
                    Text("Theme Color")
                    Spacer()
                    Text("Orange")
                        .foregroundColor(Color.appSecondary)
                }
            }

            Section("Notifications") {
                Toggle(isOn: $notificationsEnabled) {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.appPrimary)
                        Text("Push Notifications")
                    }
                }

                Toggle(isOn: $soundEnabled) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.appPrimary)
                        Text("Sound Effects")
                    }
                }
            }

            Section("Health & Fitness") {
                NavigationLink {
                    SmartwatchSyncView()
                } label: {
                    HStack {
                        Image(systemName: "applewatch")
                            .foregroundColor(.appPrimary)
                        Text("Connect Apple Watch")
                    }
                }
            }

            Section("Account") {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.appPrimary)
                    Text("Email")
                    Spacer()
                    Text(sessionManager.currentUser?.email ?? "")
                        .foregroundColor(Color.appSecondary)
                }

                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.appPrimary)
                    Text("Username")
                    Spacer()
                    Text(sessionManager.currentUser?.username ?? "")
                        .foregroundColor(Color.appSecondary)
                }
                
                // Phase 4: Dispute History
                NavigationLink {
                    DisputeHistoryView()
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Dispute History")
                    }
                }
            }

            Section("About") {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.appPrimary)
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(Color.appSecondary)
                }

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.appPrimary)
                        Text("Privacy Policy")
                    }
                }

                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.appPrimary)
                        Text("Terms of Service")
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    sessionManager.logout()
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.square.fill")
                        Text("Sign Out")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last updated: March 11, 2026")
                    .foregroundColor(.appSecondary)

                Text("SportsHub is committed to protecting your privacy. This policy outlines how we collect, use, and safeguard your information.")
                    .padding(.top, Spacing.md)

                Text("Information We Collect")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• Account information (email, username)\n• Performance data and statistics\n• Match history and rankings\n• User-generated content (posts, clips, messages)")

                Text("How We Use Your Information")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• To provide and improve our services\n• To match you with other players\n• To calculate rankings and statistics\n• To send important notifications")

                Text("Data Security")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("We implement industry-standard security measures to protect your data, including encryption and secure authentication.")
            }
            .padding(Spacing.lg)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Terms of Service")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Last updated: March 11, 2026")
                    .foregroundColor(.appSecondary)

                Text("By using SportsHub, you agree to these terms and conditions.")
                    .padding(.top, Spacing.md)

                Text("User Conduct")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• Be respectful to other users\n• No harassment or bullying\n• No cheating or match manipulation\n• Report inappropriate content")

                Text("Account Responsibilities")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• Maintain accurate information\n• Keep your password secure\n• Don't share your account\n• You're responsible for account activity")

                Text("Content Rights")
                    .font(.headline)
                    .padding(.top, Spacing.lg)

                Text("• You retain rights to content you post\n• You grant SportsHub a license to display your content\n• Don't post copyrighted material without permission")
            }
            .padding(Spacing.lg)
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(SessionManager.shared)
    }
}
