//
//  ProfileView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var storeManager = StoreManager.shared
    @State private var selectedSport: Sport = .basketball
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var customProfilePicture: Image?
    @State private var showEditBio = false
    @State private var bioText = ""
    @State private var showPremiumSheet = false
    @State private var sportProfile: SportProfileResponse?
    @State private var isLoadingProfile = false
    @State private var uploadErrorMessage: String? = nil
    
    private var bioButtonText: String {
        if let bio = sessionManager.currentUser?.bio, !bio.isEmpty {
            return "Edit Bio"
        } else {
            return "Add Bio"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Profile Header
                    VStack(spacing: Spacing.md) {
                        ZStack(alignment: .bottomTrailing) {
                            if let customPic = customProfilePicture {
                                customPic
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                            } else {
                                AvatarView(name: sessionManager.currentUser?.username ?? "Athlete", size: 96)
                            }
                            
                            // Edit button
                            Button(action: {
                                showImagePicker = true
                            }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.appPrimary)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.appBackground, lineWidth: 2)
                                    )
                            }
                        }

                        Text(sessionManager.currentUser?.displayName ?? "Athlete")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary)

                        Text("@\(sessionManager.currentUser?.username ?? "athlete")")
                            .font(.subheadline)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        // Bio section
                        if let bio = sessionManager.currentUser?.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.body)
                                .foregroundStyle(Color.appTextPrimary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.top, Spacing.sm)
                        }
                        
                        // Edit Bio button
                        Button(action: {
                            bioText = sessionManager.currentUser?.bio ?? ""
                            showEditBio = true
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                Text(bioButtonText)
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.appPrimary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.appPrimary.opacity(0.1))
                            .cornerRadius(CornerRadius.sm)
                        }
                        .padding(.top, Spacing.xs)
                    }
                    .padding(.vertical, Spacing.md)

                    // Premium Section
                    premiumSection
                    
                    // Sport Selector
                    sportSelector

                    // Sport Stats
                    VStack(spacing: Spacing.md) {
                        HStack {
                            Image(systemName: selectedSport.icon)
                                .foregroundStyle(Color.appPrimary)
                            Text("\(selectedSport.rawValue) Stats")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.appTextPrimary)
                            Spacer()
                        }

                        VStack(spacing: Spacing.md) {
                            if isLoadingProfile {
                                ProgressView()
                                    .padding()
                            } else {
                                HStack(spacing: Spacing.lg) {
                                    StatCard(title: "Games", value: "\(sportProfile?.gamesPlayed ?? 0)")
                                    StatCard(title: "Wins", value: "\(sportProfile?.wins ?? 0)")
                                    StatCard(title: "Rating", value: "\(sportProfile?.rating ?? 1500)")
                                }
                            }
                            
                            // Helpful tip for new users
                            if let profile = sportProfile, profile.gamesPlayed == 0 {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.appPrimary)
                                    Text("Play your first match to establish your rating")
                                        .font(.caption)
                                        .foregroundStyle(Color.appTextSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, Spacing.sm)
                            }
                        }
                        .cardBackground()
                    }

                    // Badges Link
                    NavigationLink {
                        BadgeSystemView(sport: selectedSport)
                    } label: {
                        HStack {
                            Image(systemName: "star.circle.fill")
                                .foregroundStyle(Color.appSecondary)
                            Text("View Badges")
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                        .foregroundStyle(Color.appTextPrimary)
                        .padding(Spacing.md)
                    }
                    .cardBackground()
                    
                    // Account Actions
                    VStack(spacing: Spacing.sm) {
                        Button(action: {
                            sessionManager.logout()
                        }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .foregroundStyle(Color.appError)
                            .padding(Spacing.md)
                        }
                        .cardBackground()
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Color.appTextPrimary)
                    }
                }
            }
            .task(id: selectedSport) {
                await loadSportProfile()
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showEditBio) {
                EditBioSheet(bioText: $bioText, onSave: {
                    // Update the user's bio
                    sessionManager.updateBio(bioText.isEmpty ? nil : bioText)
                    showEditBio = false
                })
            }
            .alert("Upload Failed", isPresented: Binding(
                get: { uploadErrorMessage != nil },
                set: { if !$0 { uploadErrorMessage = nil } }
            )) {
                Button("OK") { uploadErrorMessage = nil }
            } message: {
                Text(uploadErrorMessage ?? "")
            }
            .alert("Bio Sync Warning", isPresented: Binding(
                get: { sessionManager.bioSyncError != nil },
                set: { if !$0 { sessionManager.bioSyncError = nil } }
            )) {
                Button("OK") { sessionManager.bioSyncError = nil }
            } message: {
                Text(sessionManager.bioSyncError ?? "")
            }
            .onChange(of: selectedImage) { oldValue, newImage in
                if let newImage = newImage {
                    customProfilePicture = Image(uiImage: newImage)
                    // Save locally for offline use
                    if let data = newImage.jpegData(compressionQuality: 0.8) {
                        UserDefaults.standard.set(data, forKey: "profile_picture_data")
                        // Upload to backend
                        Task {
                            do {
                                let _ = try await APIClient.shared.uploadProfilePicture(imageData: data)
                            } catch {
                                uploadErrorMessage = "Photo upload failed. Your picture was saved locally and will retry next time."
                            }
                        }
                    }
                }
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
    
    // MARK: - Premium Section
    
    private var premiumSection: some View {
        VStack(spacing: 0) {
            if storeManager.isPremium {
                // Premium Active State
                premiumActiveCard
            } else {
                // Premium Upgrade CTA
                premiumUpgradeCard
            }
        }
        .sheet(isPresented: $showPremiumSheet) {
            PremiumSubscriptionView()
        }
    }
    
    private var premiumActiveCard: some View {
        Button(action: {
            showPremiumSheet = true
        }) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "star.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Premium Plan")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text("Active • All features unlocked")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(Color.green)
                }
                
                Divider()
                    .padding(.vertical, Spacing.xs)
                
                // Top Premium Benefits
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top Benefits")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.bottom, 4)
                    
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        premiumFeatureBadge(icon: "calendar.badge.clock", text: "AI Weekly Drills", color: .cyan)
                        premiumFeatureBadge(icon: "brain.head.profile", text: "AI Coach", color: .purple)
                        premiumFeatureBadge(icon: "chart.line.uptrend.xyaxis", text: "Advanced Analytics", color: .green)
                    }
                }
                
                // More included indicator
                HStack {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Plus wearable sync, tournaments, and more")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, Spacing.xs)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xs)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(8)
            }
            .padding(Spacing.md)
            .background(
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.05),
                        Color.blue.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var premiumUpgradeCard: some View {
        Button(action: {
            showPremiumSheet = true
        }) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "star.fill")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Premium")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appTextPrimary)
                        
                        Text("Train smarter with AI-powered drills")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Divider()
                    .padding(.vertical, Spacing.xs)
                
                // Top Premium Benefits
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Includes")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appTextSecondary)
                    
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                        Text("New AI-generated drills every week")
                            .font(.caption)
                            .foregroundStyle(Color.appTextPrimary)
                        Spacer()
                    }
                    
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                        Text("Drills tailored to your weak points")
                            .font(.caption)
                            .foregroundStyle(Color.appTextPrimary)
                        Spacer()
                    }
                    
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.green)
                        Text("Smarter AI coach & recovery insights")
                            .font(.caption)
                            .foregroundStyle(Color.appTextPrimary)
                        Spacer()
                    }
                    
                    // More included indicator
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Advanced analytics, wearable sync, tournaments & more")
                            .font(.caption2)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                
                // Pricing
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starting at")
                            .font(.caption2)
                            .foregroundStyle(Color.appTextSecondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("$8.99")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Text("/month")
                                .font(.caption)
                                .foregroundStyle(Color.appTextSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text("or $100/year")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding(Spacing.md)
            .background(Color.appSurface)
            .cornerRadius(CornerRadius.large)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func loadSportProfile() async {
        isLoadingProfile = true
        do {
            sportProfile = try await APIClient.shared.getSportProfile(sport: selectedSport.rawValue)
        } catch {
            // Profile may not exist yet for this sport — silently stay at defaults
            sportProfile = nil
        }
        isLoadingProfile = false
    }
    
    private func premiumFeatureBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.appTextPrimary)
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.green)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(Color.appTextPrimary)

            Text(title)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
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

// MARK: - Edit Bio Sheet

struct EditBioSheet: View {
    @Binding var bioText: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool
    
    private let maxCharacters = 150
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Bio")
                        .font(.headline)
                        .foregroundStyle(Color.appTextPrimary)
                    
                    ZStack(alignment: .topLeading) {
                        if bioText.isEmpty {
                            Text("Tell us about yourself...")
                                .foregroundStyle(Color.appTextSecondary.opacity(0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        }
                        
                        TextEditor(text: $bioText)
                            .focused($isFocused)
                            .frame(minHeight: 120)
                            .padding(4)
                            .background(Color.appCardBackground)
                            .cornerRadius(CornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .stroke(isFocused ? Color.appPrimary : Color.appTextSecondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    HStack {
                        Spacer()
                        Text("\(bioText.count)/\(maxCharacters)")
                            .font(.caption)
                            .foregroundStyle(bioText.count > maxCharacters ? Color.appError : Color.appTextSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(Spacing.lg)
            .background(Color.appBackground)
            .navigationTitle("Edit Bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appTextSecondary)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .foregroundStyle(Color.appPrimary)
                    .disabled(bioText.count > maxCharacters)
                }
            }
            .onAppear {
                isFocused = true
            }
            .onChange(of: bioText) { oldValue, newValue in
                // Prevent typing beyond max characters
                if newValue.count > maxCharacters {
                    bioText = String(newValue.prefix(maxCharacters))
                }
            }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(SessionManager.shared)
}
