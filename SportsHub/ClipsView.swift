//
//  ClipsView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct ClipsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSport: Sport = .basketball
    @State private var showUploadClip = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Sport Selector
                    sportSelector

                    // Clips Feed
                    VStack(spacing: Spacing.md) {
                        HStack {
                            Image(systemName: "play.rectangle.fill")
                                .foregroundStyle(Color.appPrimary)
                            Text("\(selectedSport.rawValue) Clips")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                        }

                        VStack(spacing: Spacing.md) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.appTextSecondary.opacity(0.3))

                            Text("No clips available")
                                .font(.headline)
                                .foregroundStyle(Color.appTextSecondary)

                            Text("Be the first to upload \(selectedSport.rawValue.lowercased()) highlights")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                        .cardBackground()
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Clips")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showUploadClip = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.appPrimary)
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showUploadClip) {
                VideoUploadView()
            }
        }
    }

    private var sportSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Sport.allCases, id: \.self) { sport in
                    SportPillButton(
                        sport: sport,
                        isSelected: selectedSport == sport,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedSport = sport
                            }
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    ClipsView()
        .environmentObject(SessionManager.shared)
}
