//
//  ClipsView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI
import AVKit

struct ClipsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSport: Sport = .basketball
    @State private var showUploadClip = false
    @State private var clips: [ClipResponse] = []
    @State private var isLoadingClips = false
    @State private var errorMessage: String?

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
                            
                            // Refresh button
                            Button(action: {
                                Task {
                                    await loadClips()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(Color.appPrimary)
                            }
                            .disabled(isLoadingClips)
                        }

                        if !sessionManager.backendAvailable && clips.isEmpty {
                            backendOfflineView
                        } else if isLoadingClips {
                            ProgressView()
                                .padding(Spacing.xl)
                        } else if let error = errorMessage {
                            errorView(error)
                        } else if clips.isEmpty {
                            emptyStateView
                        } else {
                            // Clips list
                            LazyVStack(spacing: Spacing.md) {
                                ForEach(clips) { clip in
                                    ClipCard(clip: clip)
                                }
                            }
                        }
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
                VideoUploadView(onClipUploaded: {
                    Task {
                        await loadClips()
                    }
                })
            }
            .task {
                await loadClips()
            }
            .onChange(of: selectedSport) { _, _ in
                Task {
                    await loadClips()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
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
                    await loadClips()
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.appPrimary)
        }
        .padding(Spacing.xl)
        .cardBackground()
    }
    
    private var backendOfflineView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 44))
                .foregroundStyle(Color.appTextSecondary.opacity(0.35))

            VStack(spacing: Spacing.xs) {
                Text("Clips Unavailable")
                    .font(.headline)
                    .foregroundStyle(Color.appTextPrimary)
                Text("Clips require a server connection. Start the backend server to browse and upload clips.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            Button("Try Anyway") { Task { await loadClips() } }
                .font(.caption)
                .foregroundStyle(Color.appPrimary)
        }
        .padding(Spacing.xl)
    }

    private func loadClips() async {
        guard sessionManager.backendAvailable else {
            isLoadingClips = false
            return
        }
        isLoadingClips = true
        errorMessage = nil
        
        do {
            let fetchedClips = try await APIClient.shared.getClips(sport: selectedSport.rawValue.lowercased(), limit: 50)
            await MainActor.run {
                clips = fetchedClips
                isLoadingClips = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load clips. Please try again."
                isLoadingClips = false
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

// MARK: - Clip Card

struct ClipCard: View {
    let clip: ClipResponse
    @State private var player: AVPlayer?
    @State private var playerLoadFailed = false
    @State private var isLoadingVideo = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Video player
            ZStack {
                if let player = player, !playerLoadFailed {
                    VideoPlayer(player: player)
                        .aspectRatio(16/9, contentMode: .fit)
                        .cornerRadius(CornerRadius.md)
                } else {
                    // Thumbnail / idle / error state
                    Rectangle()
                        .fill(Color.appSurface)
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            if let thumbnailUrl = clip.thumbnailUrl,
                               let url = URL(string: thumbnailUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.appSurface
                                }
                            }
                        }
                        .cornerRadius(CornerRadius.md)
                        .overlay {
                            if playerLoadFailed {
                                // Clear error state with retry
                                VStack(spacing: Spacing.xs) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white.opacity(0.8))
                                    Text("Video unavailable")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.8))
                                    Button("Retry") {
                                        playerLoadFailed = false
                                        loadAndPlay()
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(8)
                                }
                            } else if isLoadingVideo {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                            } else if clip.videoUrl != nil {
                                Button {
                                    loadAndPlay()
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .shadow(radius: 4)
                                }
                            }
                            // nil videoUrl: no overlay — thumbnail (or gray rect) is shown as-is
                        }
                }
            }
            
            // Clip info
            HStack(spacing: Spacing.sm) {
                AvatarView(name: clip.username, size: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextPrimary)
                        .lineLimit(2)
                    
                    HStack(spacing: Spacing.xs) {
                        Text("@\(clip.username)")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Text("\u{2022}")
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Text("\(clip.viewsCount) views")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(Spacing.sm)
        .cardBackground()
        .onDisappear {
            player?.pause()
            player = nil
            playerLoadFailed = false
            isLoadingVideo = false
        }
    }
    
    private func loadAndPlay() {
        guard let rawVideoUrl = clip.videoUrl else {
            playerLoadFailed = true
            return
        }
        // Resolve the video URL — handle relative paths by prepending base URL
        let urlString: String
        if rawVideoUrl.hasPrefix("http://") || rawVideoUrl.hasPrefix("https://") {
            urlString = rawVideoUrl
        } else {
            urlString = APIConfig.baseURL + rawVideoUrl
        }
        
        guard let url = URL(string: urlString) else {
            playerLoadFailed = true
            return
        }
        
        isLoadingVideo = true
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        
        // Poll for item status — max 6 seconds (60 × 100ms)
        Task {
            var attempts = 0
            while item.status == .unknown && attempts < 60 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                attempts += 1
            }
            await MainActor.run {
                if item.status == .readyToPlay {
                    isLoadingVideo = false
                    avPlayer.play()
                } else {
                    isLoadingVideo = false
                    playerLoadFailed = true
                    self.player = nil
                }
            }
        }
    }
}

#Preview {
    ClipsView()
        .environmentObject(SessionManager.shared)
}
