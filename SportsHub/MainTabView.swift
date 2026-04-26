//
//  MainTabView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedTab = 0
    @State private var bannerDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            // Server-offline banner — shown once when backend is unavailable
            if !sessionManager.backendAvailable && !bannerDismissed {
                serverOfflineBanner
            }

            // Content Area
            Group {
                switch selectedTab {
                case 0:
                    HomeView(selectedTab: $selectedTab)
                case 1:
                    PlayView()
                case 2:
                    TrainView()
                case 3:
                    PostsView()
                case 4:
                    ClipsView()
                case 5:
                    ProfileView()
                default:
                    HomeView(selectedTab: $selectedTab)
                }
            }

            // Custom Tab Bar
            CustomTabBar(selectedTab: $selectedTab)
        }
        .background(Color.appBackground)
        .overlay(
            AICoachFloatingView()
                .zIndex(999)
        )
        .onChange(of: sessionManager.backendAvailable) { _, isAvailable in
            // Reset dismiss state when server goes offline again
            if !isAvailable { bannerDismissed = false }
        }
    }

    private var serverOfflineBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))

            Text("Server offline — social and competitive features paused")
                .font(.caption)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button(action: { bannerDismissed = true }) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 8)
        .background(Color(red: 0.25, green: 0.35, blue: 0.55))  // muted blue — not alarming
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: sessionManager.backendAvailable)
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    
    private let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("gamecontroller.fill", "Play"),
        ("figure.run", "Train"),
        ("bubble.left.and.bubble.right.fill", "Posts"),
        ("play.rectangle.fill", "Clips"),
        ("person.circle.fill", "Profile")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: {
                    selectedTab = index
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20))
                        
                        Text(tabs[index].label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == index ? Color.appPrimary : Color.appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color.appSurface)
        .overlay(
            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 0.5),
            alignment: .top
        )
    }
}

#Preview {
    MainTabView()
}
