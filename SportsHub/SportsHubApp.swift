//
//  SportsHubApp.swift
//  SportsHub
//
//  Created by Aarush Khanna  on 3/6/26.
//

import SwiftUI
import SwiftData

@main
struct SportsHubApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView()
                        .environmentObject(sessionManager)
                } else if sessionManager.isAuthenticated {
                    if sessionManager.isAdmin {
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
        }
        .modelContainer(sharedModelContainer)
    }
}
