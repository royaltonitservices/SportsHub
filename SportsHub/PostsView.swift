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
    @State private var posts: [PostResponse] = []
    @State private var isLoadingPosts = false
    @State private var errorMessage: String?

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
                            
                            // Refresh button
                            Button(action: {
                                Task {
                                    await loadPosts()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(Color.appPrimary)
                                    .font(.title3)
                            }
                            .disabled(isLoadingPosts)
                        }

                        if isLoadingPosts {
                            ProgressView()
                                .padding(Spacing.xl)
                        } else if let error = errorMessage {
                            errorView(error)
                        } else if posts.isEmpty {
                            emptyStateView
                        } else {
                            // Posts list
                            VStack(spacing: Spacing.md) {
                                ForEach(posts, id: \.id) { post in
                                    PostCard(post: post)
                                }
                            }
                        }
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
                CreatePostView(sport: selectedSport, onPostCreated: {
                    Task {
                        await loadPosts()
                    }
                })
            }
            .task {
                await loadPosts()
            }
            .onChange(of: selectedSport) { _, _ in
                Task {
                    await loadPosts()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.md) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.appTextSecondary.opacity(0.3))

                Text("Start the conversation")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)

                Text("Share tips, ask questions, or connect with other \(selectedSport.rawValue.lowercased()) players")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: Spacing.sm) {
                Text("Sports talk happens here:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appTextSecondary)
                
                PostPromptChip(icon: "flame.fill", text: "Share your latest PR or breakthrough")
                PostPromptChip(icon: "figure.run", text: "Training insights and drills that work")
                PostPromptChip(icon: "sportscourt.fill", text: "Challenge others or find opponents")
                PostPromptChip(icon: "hand.thumbsup.fill", text: "Give respect or ask for feedback")
                PostPromptChip(icon: "target", text: "Talk goals, recovery, and improvement")
            }
            
            Button(action: { showCreatePost = true }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("Create First Post")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundStyle(.white)
                .padding(Spacing.md)
                .background(Color.appPrimary)
                .cornerRadius(CornerRadius.md)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .cardBackground()
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(Color.appError)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                Task {
                    await loadPosts()
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.appPrimary)
        }
        .padding(Spacing.xl)
        .cardBackground()
    }
    
    private func loadPosts() async {
        isLoadingPosts = true
        errorMessage = nil
        
        do {
            let fetchedPosts = try await APIClient.shared.getPosts(limit: 50, offset: 0)
            await MainActor.run {
                // Filter by sport if needed
                posts = fetchedPosts.filter { post in
                    if let postSport = post.sport {
                        return postSport.lowercased() == selectedSport.rawValue.lowercased()
                    }
                    return true // Show posts without sport filter
                }
                isLoadingPosts = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load posts. Please try again."
                isLoadingPosts = false
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

// MARK: - Post Prompt Chip

struct PostPromptChip: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.appPrimary)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.appTextPrimary)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.appSurface)
        .cornerRadius(CornerRadius.sm)
    }
}

// MARK: - Post Card

struct PostCard: View {
    @State var post: PostResponse
    @State private var showDetail = false
    @State private var isLiking = false
    
    var body: some View {
        Button(action: {
            showDetail = true
        }) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                HStack(spacing: Spacing.sm) {
                    AvatarView(name: post.username, size: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(post.username)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text(formatDate(post.createdAt))
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    Spacer()
                    
                    if let sport = post.sport {
                        Text(sport.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 4)
                            .background(Color.appPrimary.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                // Content
                Text(post.content)
                    .font(.body)
                    .foregroundStyle(Color.appTextPrimary)
                    .multilineTextAlignment(.leading)
                
                // Actions - Sports themed language
                HStack(spacing: Spacing.xl) {
                    // Respect (Like) button
                    Button(action: {
                        toggleLike()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: post.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .foregroundStyle(post.isLiked ? Color.appPrimary : Color.appTextSecondary)
                            Text(post.likesCount > 0 ? "\(post.likesCount)" : "Respect")
                                .font(.caption)
                                .foregroundStyle(post.isLiked ? Color.appPrimary : Color.appTextSecondary)
                        }
                    }
                    .disabled(isLiking)
                    
                    // Respond button
                    Button(action: {
                        showDetail = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                                .foregroundStyle(Color.appTextSecondary)
                            Text(post.commentsCount > 0 ? "\(post.commentsCount) replies" : "Respond")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                    
                    Spacer()
                }
                .font(.subheadline)
            }
            .padding(Spacing.md)
            .cardBackground()
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            PostDetailView(post: $post)
        }
    }
    
    private func toggleLike() {
        isLiking = true
        let previousState = post.isLiked
        let previousCount = post.likesCount
        
        // Optimistic update
        post.isLiked.toggle()
        post.likesCount += post.isLiked ? 1 : -1
        
        Task {
            do {
                if post.isLiked {
                    _ = try await APIClient.shared.likePost(postId: post.id)
                } else {
                    _ = try await APIClient.shared.unlikePost(postId: post.id)
                }
                await MainActor.run {
                    isLiking = false
                }
            } catch {
                // Revert on error
                await MainActor.run {
                    post.isLiked = previousState
                    post.likesCount = previousCount
                    isLiking = false
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let components = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: now)
            
            if let days = components.day, days > 0 {
                return days == 1 ? "1d" : "\(days)d"
            } else if let hours = components.hour, hours > 0 {
                return hours == 1 ? "1h" : "\(hours)h"
            } else if let minutes = components.minute, minutes > 0 {
                return minutes == 1 ? "1m" : "\(minutes)m"
            } else {
                return "now"
            }
        }
        return dateString
    }
}

// MARK: - Create Post View

struct CreatePostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    let sport: Sport
    let onPostCreated: () -> Void
    @State private var postText = ""
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                // Text editor
                ZStack(alignment: .topLeading) {
                    if postText.isEmpty {
                        Text("Share your thoughts, tips, or questions...")
                            .foregroundStyle(Color.appTextSecondary.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                    }
                    
                    TextEditor(text: $postText)
                        .frame(height: 200)
                        .padding(Spacing.sm)
                        .scrollContentBackground(.hidden)
                        .background(Color.appSurface)
                        .cornerRadius(CornerRadius.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.medium)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                }
                
                // Character count
                HStack {
                    Spacer()
                    Text("\(postText.count) characters")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                // Error message
                if let error = errorMessage {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Color.appError)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.appError)
                    }
                    .padding(Spacing.sm)
                    .background(Color.appError.opacity(0.1))
                    .cornerRadius(CornerRadius.sm)
                }
                
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
                    .foregroundStyle(Color.appTextSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await createPost()
                        }
                    } label: {
                        if isPosting {
                            ProgressView()
                                .tint(Color.appPrimary)
                        } else {
                            Text("Post")
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
        }
    }
    
    private func createPost() async {
        let trimmedText = postText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isPosting = true
        errorMessage = nil
        
        do {
            let request = CreatePostRequest(content: trimmedText, sport: sport.rawValue.lowercased())
            _ = try await APIClient.shared.createPost(request: request)
            
            await MainActor.run {
                isPosting = false
                showSuccessMessage = true
                
                // Notify parent to refresh
                onPostCreated()
                
                // Dismiss after brief success indication
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run {
                isPosting = false
                errorMessage = "Failed to create post. Please try again."
            }
        }
    }
}

#Preview {
    PostsView()
        .environmentObject(SessionManager.shared)
}
