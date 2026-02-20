//
//  SportsHubApp.swift
//  SportsHub
//
//  Created by Aarush Khanna  on 2/17/26.
//

import SwiftUI
import SportsHubCore

@main
struct SportsHubApp: App {
    var body: some Scene {
        WindowGroup {
            WelcomeScreen()
        }
    }
}

struct WelcomeScreen: View {
    
    @State private var showDemo = false
    
    var body: some View {
        if showDemo {
            ContentView()
                .transition(.opacity)
        } else {
            ZStack {
                
                // Background Gradient
                LinearGradient(
                    colors: [.black, .blue.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    
                    Spacer()
                    
                    // App Title
                    VStack(spacing: 12) {
                        
                        Text("SportsHub")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Compete • Improve • Climb the Ranks")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    
                    Spacer()
                    
                    // Enter Button
                    Button {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            showDemo = true
                        }
                    } label: {
                        Text("Enter Arena")
                            .font(.title3.bold())
                            .padding(.horizontal, 40)
                            .padding(.vertical, 16)
                            .background(.white)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                            .shadow(radius: 10)
                    }
                    
                    Spacer()
                }
                .padding()
            }
        }
    }
}

