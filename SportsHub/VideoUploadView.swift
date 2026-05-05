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
    
    let onClipUploaded: () -> Void
    
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
            errorMessage = "We couldn't load this video. Try selecting a different video."
            showError = true
        }
    }
    
    private func mapUploadErrorToUserFriendly(_ error: Error) -> String {
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("not found") || errorDescription.contains("404") {
            return "We couldn't upload your clip right now. Please try again."
        } else if errorDescription.contains("internal server error") || errorDescription.contains("500") {
            return "Our servers are having trouble. Please try again in a moment."
        } else if errorDescription.contains("network") || errorDescription.contains("connection") {
            return "Check your internet connection and try again."
        } else if errorDescription.contains("timeout") {
            return "The upload took too long. Try a shorter clip or check your connection."
        } else if errorDescription.contains("unauthorized") || errorDescription.contains("401") {
            return "Your session expired. Please log in again."
        } else if errorDescription.contains("too large") || errorDescription.contains("file size") {
            return "This video is too large. Try a shorter clip under 500 MB."
        } else {
            return "We couldn't upload your clip. Please try again."
        }
    }
    
    private func uploadVideo() {
        guard let videoURL = videoURL else { return }
        guard sessionManager.backendAvailable else {
            errorMessage = "Can't upload while server is offline. Check your connection and try again."
            showError = true
            return
        }
        isUploading = true
        uploadProgress = 0.0
        
        Task {
            do {
                // Update progress indicator
                await MainActor.run {
                    uploadProgress = 0.1
                }
                
                // Actually upload the video file to backend
                _ = try await APIClient.shared.uploadClipVideo(
                    videoURL: videoURL,
                    title: title,
                    sport: selectedSport.apiValue,
                    description: description.isEmpty ? nil : description
                )
                
                // Update progress
                await MainActor.run {
                    uploadProgress = 1.0
                }
                
                // Small delay to show completion
                try? await Task.sleep(nanoseconds: 500_000_000)
                
                // Success - trigger refresh and dismiss
                await MainActor.run {
                    onClipUploaded()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = mapUploadErrorToUserFriendly(error)
                    showError = true
                    isUploading = false
                    uploadProgress = 0.0
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
    VideoUploadView(onClipUploaded: {})
        .environmentObject(SessionManager.shared)
}
