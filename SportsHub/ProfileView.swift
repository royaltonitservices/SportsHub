//
//  ProfileView.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSport: Sport = .basketball
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var customProfilePicture: Image?
    @State private var showEditBio = false
    @State private var bioText = ""
    
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
                            HStack(spacing: Spacing.lg) {
                                StatCard(title: "Games", value: "0")
                                StatCard(title: "Wins", value: "0")
                                StatCard(title: "Rating", value: "1500")
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
            .onChange(of: selectedImage) { newImage in
                if let newImage = newImage {
                    customProfilePicture = Image(uiImage: newImage)
                    // TODO: Upload to backend
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
            .onChange(of: bioText) { newValue in
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
