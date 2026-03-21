//
//  HighlightsView.swift
//  SportsHub
//
//  Stories-like highlights feature
//

import SwiftUI

struct HighlightsCarouselView: View {
    @State private var highlights: [HighlightFeedItem] = []
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                // Add your own highlight button
                AddHighlightButton()
                
                ForEach(highlights) { item in
                    NavigationLink {
                        HighlightDetailView(userId: item.userId, highlights: [])
                    } label: {
                        HighlightAvatarView(item: item)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .task {
            await loadHighlights()
        }
    }
    
    private func loadHighlights() async {
        // Placeholder - implement API call
        // highlights = await APIClient.shared.getHighlightsFeed()
        highlights = []
    }
}

struct HighlightFeedItem: Identifiable, Codable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarSeed: String?
    let hasUnviewed: Bool
    let highlightCount: Int
    let latestThumbnail: String?
    
    var id: String { userId }
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarSeed = "avatar_seed"
        case hasUnviewed = "has_unviewed"
        case highlightCount = "highlight_count"
        case latestThumbnail = "latest_thumbnail"
    }
}

struct HighlightAvatarView: View {
    let item: HighlightFeedItem
    
    var body: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                // Ring for unviewed highlights
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: item.hasUnviewed ? [.appPrimary, .appAccent] : [.gray.opacity(0.3), .gray.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 74, height: 74)
                
                // Avatar
                Circle()
                    .fill(Color.appPrimary.opacity(0.3))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(String(item.username.prefix(1)).uppercased())
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.appPrimary)
                    )
            }
            
            Text(item.displayName ?? item.username)
                .font(.caption)
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .frame(width: 74)
        }
    }
}

struct AddHighlightButton: View {
    @State private var showingCamera = false
    
    var body: some View {
        Button {
            showingCamera = true
        } label: {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(Color.appCardBackground)
                        .frame(width: 64, height: 64)
                    
                    Circle()
                        .stroke(Color.appPrimary, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.appPrimary)
                }
                
                Text("Highlight")
                    .font(.caption)
                    .foregroundColor(.appTextPrimary)
            }
        }
        .sheet(isPresented: $showingCamera) {
            CreateHighlightView()
        }
    }
}

struct CreateHighlightView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var selectedSport: Sport?
    @State private var isUploading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Highlight Details") {
                    // In production, add image/video picker here
                    Label("Select Photo/Video", systemImage: "photo.on.rectangle.angled")
                        .foregroundColor(.appPrimary)
                    
                    TextField("Caption (optional)", text: $caption)
                    
                    Picker("Sport", selection: $selectedSport) {
                        Text("None").tag(Sport?.none)
                        ForEach(Sport.allCases, id: \.self) { sport in
                            Text(sport.rawValue.capitalized).tag(Sport?.some(sport))
                        }
                    }
                }
                
                Section {
                    Text("Highlights expire after 24 hours")
                        .font(.caption)
                        .foregroundColor(.appSecondary)
                }
            }
            .navigationTitle("New Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Share") {
                        shareHighlight()
                    }
                    .disabled(isUploading)
                }
            }
        }
    }
    
    private func shareHighlight() {
        isUploading = true
        
        Task {
            // Placeholder - implement media upload and API call
            // await APIClient.shared.createHighlight(mediaUrl: uploadedUrl, caption: caption, sport: selectedSport)
            
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        }
    }
}

struct HighlightDetailView: View {
    let userId: String
    @State var highlights: [Highlight]
    @State private var currentIndex = 0
    @State private var progress: Double = 0
    @State private var timer: Timer?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if highlights.isEmpty {
                ProgressView()
                    .tint(.white)
            } else {
                // Current highlight
                TabView(selection: $currentIndex) {
                    ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                        HighlightContentView(highlight: highlight)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                
                // Progress bars
                VStack {
                    HStack(spacing: 4) {
                        ForEach(0..<highlights.count, id: \.self) { index in
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: index == currentIndex ? geometry.size.width * progress : (index < currentIndex ? geometry.size.width : 0))
                                }
                            }
                            .frame(height: 2)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                    
                    Spacer()
                }
                
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .padding(Spacing.sm)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(Spacing.md)
                    }
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await loadHighlights()
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onTapGesture { location in
            // Tap left side to go back, right side to go forward
            if location.x < UIScreen.main.bounds.width / 2 {
                previousHighlight()
            } else {
                nextHighlight()
            }
        }
    }
    
    private func loadHighlights() async {
        // Placeholder - implement API call
        // highlights = await APIClient.shared.getUserHighlights(userId: userId)
        highlights = []
    }
    
    private func startTimer() {
        timer?.invalidate()
        progress = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            progress += 0.01
            
            if progress >= 1.0 {
                nextHighlight()
            }
        }
    }
    
    private func nextHighlight() {
        if currentIndex < highlights.count - 1 {
            currentIndex += 1
            startTimer()
        } else {
            dismiss()
        }
    }
    
    private func previousHighlight() {
        if currentIndex > 0 {
            currentIndex -= 1
            startTimer()
        }
    }
}

struct Highlight: Identifiable, Codable {
    let id: String
    let userId: String
    let mediaUrl: String
    let thumbnailUrl: String?
    let caption: String?
    let sportString: String?
    let createdAt: String
    let expiresAt: String
    let viewsCount: Int
    
    var sport: Sport? {
        guard let sportString = sportString else { return nil }
        return Sport(rawValue: sportString)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case mediaUrl = "media_url"
        case thumbnailUrl = "thumbnail_url"
        case caption
        case sportString = "sport"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case viewsCount = "views_count"
    }
}

struct HighlightContentView: View {
    let highlight: Highlight
    
    var body: some View {
        ZStack {
            // Placeholder for media content
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.appPrimary, .appAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Caption overlay
            if let caption = highlight.caption {
                VStack {
                    Spacer()
                    
                    Text(caption)
                        .foregroundColor(.white)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            
            // Sport badge
            if let sport = highlight.sport {
                VStack {
                    HStack {
                        Text(sport.rawValue.capitalized)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(CornerRadius.sm)
                            .padding(Spacing.md)
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    HighlightsCarouselView()
}
