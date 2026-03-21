//
//  PostsView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct PostsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSport: Sport = .basketball
    @State private var showCreatePost = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Sport Selector
                    sportSelector

                    // Posts Feed
                    VStack(spacing: Spacing.md) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(Color.appPrimary)
                            Text("\(selectedSport.rawValue) Posts")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                        }

                        VStack(spacing: Spacing.md) {
                            Image(systemName: "text.bubble.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.appTextSecondary.opacity(0.3))

                            Text("No posts yet")
                                .font(.headline)
                                .foregroundStyle(Color.appTextSecondary)

                            Text("Be the first to share in the \(selectedSport.rawValue.lowercased()) community")
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
            .navigationTitle("Posts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showCreatePost = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.appPrimary)
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showCreatePost) {
                CreatePostView(sport: selectedSport)
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

// MARK: - Create Post View

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    let sport: Sport
    @State private var postText = ""
    @State private var isPosting = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                TextEditor(text: $postText)
                    .frame(height: 200)
                    .padding(Spacing.sm)
                    .background(Color.appSurface)
                    .cornerRadius(CornerRadius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(Color.appBorder, lineWidth: 1)
                    )
                
                Spacer()
            }
            .padding()
            .background(Color.appBackground)
            .navigationTitle("Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Post") {
                        Task {
                            await createPost()
                        }
                    }
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
        }
    }
    
    private func createPost() async {
        isPosting = true
        // TODO: Implement API call to create post
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        isPosting = false
        dismiss()
    }
}

#Preview {
    PostsView()
        .environmentObject(SessionManager.shared)
}
