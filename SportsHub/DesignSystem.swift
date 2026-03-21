//
//  DesignSystem.swift
//  SportsHub
//
//  Created by Aarush Khanna on 3/6/26.
//

import SwiftUI

// MARK: - Colors

extension Color {
    static let appBackground = Color(hex: 0x0A0A0A)
    static let appSurface = Color(hex: 0x1A1A1A)
    static let appSurfaceElevated = Color(hex: 0x2A2A2A)
    static let appPrimary = Color(hex: 0xFF6B35)
    static let appAccent = Color(hex: 0xFF8C42)  // Lighter orange
    static let appSecondary = Color(hex: 0xA0A0A0)
    static let appTextPrimary = Color.white
    static let appTextSecondary = Color(hex: 0xA0A0A0)
    static let appBorder = Color(hex: 0x333333)
    static let appCardBackground = Color(hex: 0x1A1A1A)
    static let appSuccess = Color(hex: 0x4CAF50)
    static let appError = Color(hex: 0xF44336)
    
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    // Aliases for compatibility
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
}

// MARK: - Reusable Components

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

struct PrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.appPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

struct SecondaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(Color.appPrimary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .stroke(Color.appPrimary, lineWidth: 2)
            )
    }
}

extension View {
    func cardBackground() -> some View {
        modifier(CardBackground())
    }
    
    func primaryButton() -> some View {
        modifier(PrimaryButton())
    }
    
    func secondaryButton() -> some View {
        modifier(SecondaryButton())
    }
}

// MARK: - Avatar View

struct AvatarView: View {
    let name: String
    let size: CGFloat
    
    private var gradient: LinearGradient {
        let colors = [
            [Color(hex: 0xFF6B35), Color(hex: 0xFF8C42)],
            [Color(hex: 0x4CAF50), Color(hex: 0x66BB6A)],
            [Color(hex: 0x2196F3), Color(hex: 0x42A5F5)],
            [Color(hex: 0x9C27B0), Color(hex: 0xAB47BC)],
            [Color(hex: 0xFF5722), Color(hex: 0xFF7043)],
            [Color(hex: 0x00BCD4), Color(hex: 0x26C6DA)],
            [Color(hex: 0xFFC107), Color(hex: 0xFFD54F)]
        ]
        
        let index = abs(name.hashValue) % colors.count
        return LinearGradient(
            colors: colors[index],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1))
        } else {
            return String(name.prefix(2))
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(gradient)
            
            Text(initials.uppercased())
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
