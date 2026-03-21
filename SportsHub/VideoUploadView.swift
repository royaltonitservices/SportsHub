//
//  VideoUploadView.swift
//  SportsHub
//
//  Video upload interface with placeholder storage
//

import SwiftUI
import PhotosUI
import AVKit

struct VideoUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    
    @State private var selectedSport: Sport = .basketball
    @State private var title = ""
    @State private var description = ""
    @State private var selectedVideo: PhotosPickerItem?
    @State private var videoURL: URL?
    @State private var thumbnailImage: UIImage?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0.0
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Video Picker
                    videoPicker
                    
                    // Video Preview
                    if let videoURL = videoURL {
                        videoPreview(url: videoURL)
                    }
                    
                    // Title Input
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Title")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        TextField("Give your clip a catchy title", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Description Input
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Description (Optional)")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        TextEditor(text: $description)
                            .frame(height: 100)
                            .padding(Spacing.sm)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.small)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Sport Selector
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Sport")
                            .font(.headline)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.sm) {
                                ForEach(Sport.allCases, id: \.self) { sport in
                                    Button(action: {
                                        selectedSport = sport
                                    }) {
                                        HStack {
                                            Image(systemName: sport.icon)
                                            Text(sport.rawValue)
                                        }
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        .background(selectedSport == sport ? Color.appPrimary : Color.appSurface)
                                        .foregroundStyle(selectedSport == sport ? .white : Color.appTextPrimary)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                    
                    // Upload Button
                    if isUploading {
                        VStack(spacing: Spacing.md) {
                            ProgressView(value: uploadProgress)
                                .tint(Color.appPrimary)
                            
                            Text("Uploading... \(Int(uploadProgress * 100))%")
                                .font(.subheadline)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        .padding(Spacing.md)
                    } else {
                        Button(action: {
                            uploadVideo()
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("Upload Clip")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(Spacing.md)
                            .background(canUpload ? Color.appPrimary : Color.gray)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                        }
                        .disabled(!canUpload)
                    }
                    
                    // Upload Info
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Color.appPrimary)
                            Text("Upload Guidelines")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.appTextPrimary)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Maximum video length: 2 minutes")
                            Text("• Supported formats: MP4, MOV")
                            Text("• Maximum file size: 500 MB")
                            Text("• Keep content appropriate and sports-related")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    }
                    .padding(Spacing.md)
                    .cardBackground()
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Upload Clip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Upload Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var videoPicker: some View {
        PhotosPicker(selection: $selectedVideo, matching: .videos) {
            VStack(spacing: Spacing.md) {
                if videoURL == nil {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.appPrimary)
                    
                    Text("Select Video")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    Text("Tap to choose from your library")
                        .font(.subheadline)
                        .foregroundStyle(Color.appTextSecondary)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Video selected - Tap to change")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(Color.appPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [10]))
            )
        }
        .onChange(of: selectedVideo) { oldValue, newValue in
            Task {
                await loadVideo(from: newValue)
            }
        }
    }
    
    private func videoPreview(url: URL) -> some View {
        VideoPlayer(player: AVPlayer(url: url))
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
    
    private var canUpload: Bool {
        !title.isEmpty && videoURL != nil && !isUploading
    }
    
    private func loadVideo(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            if let movie = try await item.loadTransferable(type: VideoFile.self) {
                videoURL = movie.url
            }
        } catch {
            errorMessage = "Failed to load video: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func uploadVideo() {
        guard videoURL != nil else { return }
        
        isUploading = true
        uploadProgress = 0.0
        
        // TODO: Implement actual video upload to backend/CDN
        // This is a placeholder that simulates upload progress
        
        Task {
            // Simulate upload progress
            for i in 1...10 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                uploadProgress = Double(i) / 10.0
            }
            
            // TODO: Call backend API to create clip record
            // For now, we'll just simulate success
            
            // Simulated API call
            do {
                // Generate a placeholder URL for the uploaded video
                let videoUrlString = "https://cdn.sportshub.example.com/clips/\(UUID().uuidString).mp4"
                
                let request = CreateClipRequest(
                    title: title,
                    description: description.isEmpty ? nil : description,
                    sport: selectedSport.rawValue,
                    videoUrl: videoUrlString,
                    thumbnailUrl: nil
                )
                
                _ = try await APIClient.shared.createClip(request: request)
                
                // Success - dismiss the view
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to upload clip: \(error.localizedDescription)"
                    showError = true
                    isUploading = false
                }
            }
        }
    }
}

// MARK: - Video File Transfer
struct VideoFile: Transferable {
    let url: URL
    
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = URL.documentsDirectory.appending(path: "video-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

#Preview {
    VideoUploadView()
        .environmentObject(SessionManager.shared)
}
