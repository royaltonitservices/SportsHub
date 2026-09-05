//
//  ProofSubmissionView.swift
//  SportsHub
//
//  Photo/video proof of completion for challenges
//

import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

/// A video selected from PhotosPicker, copied to an app-owned temp file via a streamed
/// FileRepresentation — the full video is never loaded into memory just to get a URL.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // The system-provided file is temporary; copy it to our own uniquely-named
            // temp file, preserving the real extension (never relabel MP4 as MOV).
            let sourceExt = received.file.pathExtension.lowercased()
            let ext = sourceExt.isEmpty ? "mov" : sourceExt
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("sportshub-evidence-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// Truthful MIME for an evidence video from its real file extension. Both values are
/// accepted by the backend evidence upload (video/mp4, video/quicktime).
func evidenceVideoMIMEType(forExtension ext: String) -> String {
    switch ext.lowercased() {
    case "mov", "qt":       return "video/quicktime"
    case "mp4", "m4v":      return "video/mp4"
    default:
        if let ut = UTType(filenameExtension: ext), let mime = ut.preferredMIMEType, mime.hasPrefix("video/") {
            return mime
        }
        return "video/mp4"
    }
}

struct ProofSubmissionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sessionManager: SessionManager
    
    let challengeName: String
    let challengeId: String
    
    @State private var selectedMedia: [PhotosPickerItem] = []
    @State private var capturedPhotos: [UIImage] = []
    @State private var videoURL: URL?
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showVideoPicker = false
    @State private var notes = ""
    @State private var completionValue = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMessage = ""
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Challenge Info
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "flag.checkered.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.appPrimary)
                            
                            Text("Submit Proof")
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(Color.appTextPrimary)
                        
                        Text(challengeName)
                            .font(.headline)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .cardBackground()
                    
                    // Result Input
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "number.circle.fill")
                                .foregroundStyle(Color.appPrimary)
                            Text("Your Result")
                                .font(.headline)
                        }
                        .foregroundStyle(Color.appTextPrimary)
                        
                        TextField("Enter your score/result", text: $completionValue)
                            .keyboardType(.numberPad)
                            .padding()
                            .background(Color.appCardBackground)
                            .cornerRadius(10)
                    }
                    .padding(Spacing.md)
                    .cardBackground()
                    
                    // Photo Evidence
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .foregroundStyle(Color.appPrimary)
                            Text("Photo Evidence")
                                .font(.headline)
                            Spacer()
                            Text("\(capturedPhotos.count)/3")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        .foregroundStyle(Color.appTextPrimary)
                        
                        // Photo Grid
                        if !capturedPhotos.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Spacing.sm) {
                                    ForEach(Array(capturedPhotos.enumerated()), id: \.offset) { index, image in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            
                                            Button(action: {
                                                capturedPhotos.remove(at: index)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white)
                                                    .background(Circle().fill(Color.red))
                                            }
                                            .padding(4)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Add Photo Buttons
                        HStack(spacing: Spacing.sm) {
                            Button(action: {
                                showCamera = true
                            }) {
                                Label("Take Photo", systemImage: "camera")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.appPrimary)
                                    .cornerRadius(10)
                            }
                            .disabled(capturedPhotos.count >= 3)
                            
                            PhotosPicker(selection: $selectedMedia, maxSelectionCount: 3 - capturedPhotos.count, matching: .images) {
                                Label("Choose Photo", systemImage: "photo.on.rectangle")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.appSecondary)
                                    .cornerRadius(10)
                            }
                            .disabled(capturedPhotos.count >= 3)
                            .onChange(of: selectedMedia) { _, newItems in
                                Task {
                                    await loadPhotos(from: newItems)
                                }
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .cardBackground()
                    
                    // Video Evidence (Optional)
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "video.fill")
                                .foregroundStyle(Color.appSecondary)
                            Text("Video Evidence (Optional)")
                                .font(.headline)
                        }
                        .foregroundStyle(Color.appTextPrimary)
                        
                        if let videoURL = videoURL {
                            VStack(spacing: Spacing.sm) {
                                VideoPlayer(player: AVPlayer(url: videoURL))
                                    .frame(height: 200)
                                    .cornerRadius(10)
                                
                                Button(action: {
                                    self.videoURL = nil
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Remove Video")
                                    }
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Spacing.sm)
                                }
                            }
                        } else {
                            Button(action: {
                                showVideoPicker = true
                            }) {
                                Label("Add Video Clip", systemImage: "video.badge.plus")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.appSecondary)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .cardBackground()
                    
                    // Notes
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Image(systemName: "note.text")
                                .foregroundStyle(Color.appPrimary)
                            Text("Notes (Optional)")
                                .font(.headline)
                        }
                        .foregroundStyle(Color.appTextPrimary)
                        
                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .padding(Spacing.sm)
                            .background(Color.appCardBackground)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appTextSecondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(Spacing.md)
                    .cardBackground()
                    
                    // Requirements Info
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Color.appSecondary)
                            Text("Proof Requirements")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.appTextSecondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            RequirementRow(text: "At least 1 photo showing your completion", isMet: !capturedPhotos.isEmpty)
                            RequirementRow(text: "Result/score value entered", isMet: !completionValue.isEmpty)
                            RequirementRow(text: "Photo clearly shows the activity", isMet: !capturedPhotos.isEmpty)
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color.appSecondary.opacity(0.1))
                    .cornerRadius(10)
                    
                    // Submit Button
                    Button(action: {
                        Task {
                            await submitProof()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Submit Proof")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid ? Color.appPrimary : Color.appTextSecondary.opacity(0.3))
                        .cornerRadius(12)
                    }
                    .disabled(!isFormValid || isLoading)
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Submit Proof")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                ProofImagePicker(selectedImage: Binding(
                    get: { nil },
                    set: { newImage in
                        if let newImage = newImage {
                            capturedPhotos.append(newImage)
                        }
                    }
                ), sourceType: .camera)
            }
            // Privacy-preserving video selection (PhotosPicker) — no broad photo-library
            // authorization; the user explicitly picks one video.
            .photosPicker(isPresented: $showVideoPicker, selection: $selectedVideoItem, matching: .videos)
            .onChange(of: selectedVideoItem) { _, item in
                guard let item else { return }
                Task {
                    // File-backed copy — the picked video is streamed to an app-owned temp
                    // file, not materialized as Data, and its real extension is preserved.
                    if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                        await MainActor.run { videoURL = movie.url }
                    }
                    await MainActor.run { selectedVideoItem = nil }
                }
            }
            .alert("Proof Submitted!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your proof has been submitted for review. You'll be notified once it's verified!")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Form Validation
    
    private var isFormValid: Bool {
        !capturedPhotos.isEmpty &&
        !completionValue.isEmpty &&
        Int(completionValue) != nil
    }
    
    // MARK: - Load Photos
    
    private func loadPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                capturedPhotos.append(image)
            }
        }
        selectedMedia = []
    }
    
    // MARK: - Submit Proof

    private func submitProof() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Upload each photo: extract bytes → server upload → associate with challenge
            for photo in capturedPhotos {
                guard let imageData = photo.jpegData(compressionQuality: 0.8) else { continue }
                let token = try await APIClient.shared.uploadEvidenceFile(data: imageData, mimeType: "image/jpeg")
                _ = try await APIClient.shared.associateEvidence(
                    challengeId: challengeId,
                    uploadId: token.uploadId,
                    evidenceType: "image",
                    description: notes.isEmpty ? nil : notes
                )
            }

            // Upload video if present. The evidence API is byte/multipart based, so the
            // file is read once here at upload time (not double-materialized during
            // selection). MIME is derived truthfully from the real extension. Our temp
            // copy is removed after the attempt — only the app-owned copy, never the
            // user's original asset.
            if let videoURL = videoURL {
                defer {
                    try? FileManager.default.removeItem(at: videoURL)
                    self.videoURL = nil
                }
                let videoData = try Data(contentsOf: videoURL)
                let mimeType = evidenceVideoMIMEType(forExtension: videoURL.pathExtension)
                let token = try await APIClient.shared.uploadEvidenceFile(data: videoData, mimeType: mimeType)
                _ = try await APIClient.shared.associateEvidence(
                    challengeId: challengeId,
                    uploadId: token.uploadId,
                    evidenceType: "video",
                    description: notes.isEmpty ? nil : notes
                )
            }

            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Requirement Row

struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(isMet ? .green : Color.appTextSecondary)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
    }
}

// MARK: - Image Picker

/// Camera-only capture wrapper. Photo/video *selection* uses SwiftUI PhotosPicker
/// (no broad photo-library authorization); this exists solely for live camera capture.
struct ProofImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    var sourceType: UIImagePickerController.SourceType = .camera

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProofImagePicker
        
        init(_ parent: ProofImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    ProofSubmissionView(challengeName: "100 Free Throws Challenge", challengeId: "123")
        .environmentObject(SessionManager.shared)
}
