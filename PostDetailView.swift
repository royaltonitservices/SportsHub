// Post Detail View
// Full post with comments and sports-native interactions

import SwiftUI

struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var post: PostResponse
    
    @State private var comments: [CommentResponse] = []
    @State private var isLoadingComments = false
    @State private var commentText = ""
    @State private var isPostingComment = false
    @State private var replyingTo: CommentResponse?
    @State private var showReactions = false
    @FocusState private var isCommentFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Original Post
                        originalPostSection
                        
                        Divider()
                        
                        // Reactions Section
                        reactionsSection
                        
                        Divider()
                        
                        // Comments Header
                        commentsHeader
                        
                        // Comments List
                        if isLoadingComments {
                            ProgressView()
                                .padding(Spacing.xl)
                        } else if comments.isEmpty {
                            emptyCommentsView
                        } else {
                            commentsSection
                        }
                    }
                    .padding(Spacing.md)
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appTextSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                commentInputBar
            }
            .task {
                await loadComments()
            }
        }
    }
    
    // MARK: - Original Post Section
    
    private var originalPostSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.sm) {
                AvatarView(name: post.username, size: 48)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(post.username)")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    HStack(spacing: Spacing.xs) {
                        Text(formatDate(post.createdAt))
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        if let sport = post.sport {
                            Text("•")
                                .foregroundStyle(Color.appTextSecondary)
                            Text(sport.capitalized)
                                .font(.caption)
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Content
            Text(post.content)
                .font(.body)
                .foregroundStyle(Color.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            // Engagement Stats
            HStack(spacing: Spacing.md) {
                if post.likesCount > 0 {
                    Text("\(post.likesCount) respect")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                
                if post.commentsCount > 0 {
                    Text("\(post.commentsCount) \(post.commentsCount == 1 ? "reply" : "replies")")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
        }
    }
    
    // MARK: - Reactions Section
    
    private var reactionsSection: some View {
        VStack(spacing: Spacing.sm) {
            // Primary actions
            HStack(spacing: Spacing.lg) {
                // Respect button
                Button(action: {
                    toggleLike()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.title3)
                            .foregroundStyle(post.isLiked ? Color.appPrimary : Color.appTextSecondary)
                        Text("Respect")
                            .font(.caption2)
                            .foregroundStyle(post.isLiked ? Color.appPrimary : Color.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Respond button
                Button(action: {
                    isCommentFocused = true
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.title3)
                            .foregroundStyle(Color.appTextSecondary)
                        Text("Respond")
                            .font(.caption2)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // More reactions button
                Button(action: {
                    showReactions.toggle()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "flame")
                            .font(.title3)
                            .foregroundStyle(Color.appTextSecondary)
                        Text("Hype")
                            .font(.caption2)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Spacing.sm)
            
            // Extended reactions (sports-themed)
            if showReactions {
                VStack(spacing: Spacing.xs) {
                    Text("Quick Reactions")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                        ReactionButton(emoji: "🔥", label: "Fire", action: { sendQuickReaction("Fire") })
                        ReactionButton(emoji: "💪", label: "Strong", action: { sendQuickReaction("Strong") })
                        ReactionButton(emoji: "⚡️", label: "Electric", action: { sendQuickReaction("Electric") })
                        ReactionButton(emoji: "🏆", label: "Champion", action: { sendQuickReaction("Champion") })
                        ReactionButton(emoji: "👊", label: "Respect", action: { sendQuickReaction("Respect") })
                        ReactionButton(emoji: "🎯", label: "On Point", action: { sendQuickReaction("On Point") })
                    }
                }
                .padding(Spacing.sm)
                .background(Color.appSurface)
                .cornerRadius(CornerRadius.md)
            }
        }
    }
    
    // MARK: - Comments Section
    
    private var commentsHeader: some View {
        HStack {
            Text(comments.isEmpty ? "Replies" : "\(comments.count) \(comments.count == 1 ? "Reply" : "Replies")")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            Spacer()
            
            Button(action: {
                Task {
                    await loadComments()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.appPrimary)
            }
            .disabled(isLoadingComments)
        }
    }
    
    private var emptyCommentsView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(Color.appTextSecondary.opacity(0.3))
            
            Text("Be the first to respond")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            
            Text("Share your thoughts, encouragement, or training tips")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
    }
    
    private var commentsSection: some View {
        VStack(spacing: Spacing.md) {
            ForEach(topLevelComments) { comment in
                CommentRow(
                    comment: comment,
                    replies: getReplies(for: comment.id),
                    onReply: { replyToComment(comment) },
                    onLike: { likeComment(comment) }
                )
            }
        }
    }
    
    private var topLevelComments: [CommentResponse] {
        comments.filter { $0.parentCommentId == nil }
    }
    
    private func getReplies(for commentId: String) -> [CommentResponse] {
        comments.filter { $0.parentCommentId == commentId }
    }
    
    // MARK: - Comment Input Bar
    
    private var commentInputBar: some View {
        VStack(spacing: 0) {
            if let replying = replyingTo {
                HStack {
                    Text("Replying to @\(replying.authorUsername ?? "user")")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    
                    Spacer()
                    
                    Button(action: {
                        replyingTo = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(Color.appSurface.opacity(0.5))
            }
            
            HStack(spacing: Spacing.sm) {
                TextField(replyingTo != nil ? "Add your reply..." : "Share your thoughts...", text: $commentText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.appSurface)
                    .cornerRadius(CornerRadius.large)
                    .focused($isCommentFocused)
                
                Button(action: {
                    postComment()
                }) {
                    if isPostingComment {
                        ProgressView()
                            .tint(Color.appPrimary)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.appPrimary)
                    }
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingComment)
            }
            .padding(Spacing.md)
            .background(Color.appBackground)
            .overlay(
                Rectangle()
                    .fill(Color.appBorder)
                    .frame(height: 0.5),
                alignment: .top
            )
        }
    }
    
    // MARK: - Actions
    
    private func toggleLike() {
        let previousState = post.isLiked
        let previousCount = post.likesCount
        
        post.isLiked.toggle()
        post.likesCount += post.isLiked ? 1 : -1
        
        Task {
            do {
                if post.isLiked {
                    _ = try await APIClient.shared.likePost(postId: post.id)
                } else {
                    _ = try await APIClient.shared.unlikePost(postId: post.id)
                }
            } catch {
                await MainActor.run {
                    post.isLiked = previousState
                    post.likesCount = previousCount
                }
            }
        }
    }
    
    private func loadComments() async {
        isLoadingComments = true
        
        do {
            let fetchedComments = try await APIClient.shared.getPostComments(postId: post.id)
            
            // Fetch usernames for comments (in real app, backend should include this)
            var enrichedComments = fetchedComments
            for i in 0..<enrichedComments.count {
                enrichedComments[i].authorUsername = "athlete\(i + 1)" // Mock for now
            }
            
            await MainActor.run {
                comments = enrichedComments.sorted { $0.createdAt > $1.createdAt }
                isLoadingComments = false
            }
        } catch {
            await MainActor.run {
                isLoadingComments = false
            }
        }
    }
    
    private func postComment() {
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isPostingComment = true
        
        Task {
            do {
                let request = CreateCommentRequest(
                    postId: post.id,
                    content: trimmedText,
                    parentCommentId: replyingTo?.id
                )
                
                var newComment = try await APIClient.shared.createComment(request: request)
                newComment.authorUsername = sessionManager.currentUser?.username ?? "You"
                
                await MainActor.run {
                    comments.insert(newComment, at: 0)
                    post.commentsCount += 1
                    commentText = ""
                    replyingTo = nil
                    isPostingComment = false
                    isCommentFocused = false
                }
            } catch {
                await MainActor.run {
                    isPostingComment = false
                }
            }
        }
    }
    
    private func replyToComment(_ comment: CommentResponse) {
        replyingTo = comment
        isCommentFocused = true
    }
    
    private func likeComment(_ comment: CommentResponse) {
        Task {
            _ = try? await APIClient.shared.likeComment(commentId: comment.id)
            await loadComments()
        }
    }
    
    private func sendQuickReaction(_ reaction: String) {
        commentText = reaction
        postComment()
        showReactions = false
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let components = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: now)
            
            if let days = components.day, days > 0 {
                return days == 1 ? "1 day ago" : "\(days) days ago"
            } else if let hours = components.hour, hours > 0 {
                return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
            } else if let minutes = components.minute, minutes > 0 {
                return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
            } else {
                return "just now"
            }
        }
        return dateString
    }
}

// MARK: - Comment Row

struct CommentRow: View {
    let comment: CommentResponse
    let replies: [CommentResponse]
    let onReply: () -> Void
    let onLike: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                AvatarView(name: comment.authorUsername ?? "User", size: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("@\(comment.authorUsername ?? "user")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text(formatRelativeTime(comment.createdAt))
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    Text(comment.content)
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    // Actions
                    HStack(spacing: Spacing.lg) {
                        Button(action: onLike) {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.thumbsup")
                                    .font(.caption)
                                if comment.likesCount > 0 {
                                    Text("\(comment.likesCount)")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(Color.appTextSecondary)
                        }
                        
                        Button(action: onReply) {
                            Text("Reply")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            
            // Nested replies
            if !replies.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(replies) { reply in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Rectangle()
                                .fill(Color.appBorder)
                                .frame(width: 2)
                                .padding(.leading, Spacing.sm)
                            
                            AvatarView(name: reply.authorUsername ?? "User", size: 28)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("@\(reply.authorUsername ?? "user")")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.appTextPrimary)
                                    
                                    Text(formatRelativeTime(reply.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(Color.appTextSecondary)
                                }
                                
                                Text(reply.content)
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextPrimary)
                            }
                        }
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(Spacing.sm)
        .background(Color.appSurface.opacity(0.5))
        .cornerRadius(CornerRadius.md)
    }
    
    private func formatRelativeTime(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let components = Calendar.current.dateComponents([.day, .hour, .minute], from: date, to: now)
            
            if let days = components.day, days > 0 {
                return "\(days)d"
            } else if let hours = components.hour, hours > 0 {
                return "\(hours)h"
            } else if let minutes = components.minute, minutes > 0 {
                return "\(minutes)m"
            } else {
                return "now"
            }
        }
        return ""
    }
}

// MARK: - Reaction Button

struct ReactionButton: View {
    let emoji: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color.appBackground)
            .cornerRadius(CornerRadius.sm)
        }
    }
}

#Preview {
    PostDetailView(post: .constant(PostResponse(
        id: "1",
        userId: "user1",
        username: "athlete23",
        content: "Just hit a new PR on my 3-pointer! 🏀 Consistency is key. Anyone else working on their shot?",
        sport: "basketball",
        likesCount: 24,
        commentsCount: 8,
        createdAt: "2024-01-15T10:30:00Z",
        isLiked: false
    )))
    .environmentObject(SessionManager.shared)
}
