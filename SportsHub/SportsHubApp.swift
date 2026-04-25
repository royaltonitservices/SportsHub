//
//  SportsHubApp.swift
//  SportsHub
//
//  Created by Aarush Khanna  on 3/6/26.
//

import SwiftUI

@main
struct SportsHubApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView()
                        .environmentObject(sessionManager)
                } else if sessionManager.isAuthenticated {
                    if let maskedEmail = sessionManager.pendingVerificationEmail {
                        // New user — must verify email before accessing the app
                        EmailVerificationView(maskedEmail: maskedEmail)
                            .environmentObject(sessionManager)
                    } else if sessionManager.requiresSurvey {
                        // Verified but hasn't completed onboarding survey
                        OnboardingSurveyView()
                            .environmentObject(sessionManager)
                    } else if sessionManager.isAdmin {
                        AdminDashboardView()
                            .environmentObject(sessionManager)
                    } else {
                        MainTabView()
                            .environmentObject(sessionManager)
                    }
                } else {
                    AuthenticationView()
                        .environmentObject(sessionManager)
                }
            }
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .task {
                // Startup connectivity check — logs clearly if backend is unreachable
                await APIClient.shared.checkConnectivity()
                #if DEBUG
                CoherenceValidator.runLaunchChecks()
                FeatureManifest.printReport()
                AIConsistencyValidator.runIfEnabled()
                #endif
            }
        }
    }
}
