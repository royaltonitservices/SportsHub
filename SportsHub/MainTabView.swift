//
//  MainTabView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
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
