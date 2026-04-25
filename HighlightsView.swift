//
//  HighlightsView.swift
//  SportsHub
//
//  Stories-like highlights feature — wired to /highlights/feed, /highlights/user/{id}, /highlights/upload
//

import SwiftUI
import PhotosUI

// MARK: - Carousel (embedded in HomeView)

struct HighlightsCarouselView: View {
    @State private var feedItems: [HighlightFeedItem] = []
    @State private var isLoading = true
    @State private var selectedItem: HighlightFeedItem?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                AddHighlightButton()

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.appCardBackground)
                            .frame(width: 64, height: 64)
                            .overlay(Circle().stroke(Color.appTextSecondary.opacity(0.2), lineWidth: 2))
                    }
                } else {
                    ForEach(feedItems) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            HighlightAvatarView(item: item)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .frame(height: 100)
        .task {
            await loadFeed()
        }
        .sheet(item: $selectedItem) { item in
            HighlightDetailView(userId: item.userId, highlights: [])
        }
    }

    private func loadFeed() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feedItems = try await APIClient.shared.getHighlightsFeed()
        } catch {
            // Silently fail — carousel is supplementary content
        }
    }
}

// MARK: - Story Avatar

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

// MARK: - Add Highlight Button

struct AddHighlightButton: View {
    @State private var showingCreate = false

    var body: some View {
        Button {
            showingCreate = true
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
        .sheet(isPresented: $showingCreate) {
            CreateHighlightView()
        }
    }
}

// MARK: - Highlight Detail (Story viewer)

struct HighlightDetailView: View {
    let userId: String
    @State var highlights: [Highlight]
    @State private var currentIndex = 0
    @State private var progress: Double = 0
    @State private var timer: Timer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if highlights.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else {
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
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.3))
                                        Rectangle()
                                            .fill(Color.white)
                                            .frame(width: index == currentIndex ? geo.size.width * progress : (index < currentIndex ? geo.size.width : 0))
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
            .onTapGesture { location in
                if location.x < geometry.size.width / 2 {
                    previousHighlight()
                } else {
                    nextHighlight()
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
        }
    }

    private func loadHighlights() async {
        do {
            highlights = try await APIClient.shared.getUserHighlights(userId: userId)
        } catch {
            highlights = []
        }
        if !highlights.isEmpty { startTimer() }
    }

    private func startTimer() {
        timer?.invalidate()
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            progress += 0.01
            if progress >= 1.0 { nextHighlight() }
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

// MARK: - Create Highlight

struct CreateHighlightView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var selectedSport: Sport?
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var selectedImageData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Media") {
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        if selectedImageData != nil {
                            Label("Photo selected — tap to change", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.appPrimary)
                        } else {
                            Label("Select Photo or Video", systemImage: "photo.on.rectangle.angled")
                                .foregroundColor(.appPrimary)
                        }
                    }
                    .onChange(of: pickerItem) { _, newItem in
                        Task {
                            selectedImageData = try? await newItem?.loadTransferable(type: Data.self)
                        }
                    }
                }

                Section("Details") {
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
                        .foregroundColor(.appTextSecondary)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.appError)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isUploading {
                        ProgressView()
                    } else {
                        Button("Share") {
                            Task { await shareHighlight() }
                        }
                        .disabled(selectedImageData == nil)
                    }
                }
            }
        }
    }

    private func shareHighlight() async {
        guard let imageData = selectedImageData else { return }
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let mediaUrl = try await APIClient.shared.uploadHighlightMedia(imageData: imageData)
            _ = try await APIClient.shared.createHighlight(
                mediaUrl: mediaUrl,
                caption: caption.isEmpty ? nil : caption,
                sport: selectedSport?.rawValue
            )
            dismiss()
        } catch {
            errorMessage = "Upload failed. Please try again."
        }
    }
}

// MARK: - Highlight Data Model

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

// MARK: - Highlight Content View

struct HighlightContentView: View {
    let highlight: Highlight

    var body: some View {
        ZStack {
            if let url = resolvedURL(highlight.mediaUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill().clipped()
                    case .failure:
                        gradientPlaceholder
                    case .empty:
                        gradientPlaceholder.overlay(ProgressView().tint(.white))
                    @unknown default:
                        gradientPlaceholder
                    }
                }
            } else {
                gradientPlaceholder
            }

            // Caption overlay
            if let caption = highlight.caption {
                VStack {
                    Spacer()
                    Text(caption)
                        .foregroundColor(.white)
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
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

    private var gradientPlaceholder: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.appPrimary, .appAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func resolvedURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: "\(APIConfig.baseURL)\(path)")
    }
}

#Preview {
    HighlightsCarouselView()
}
