// Premium Subscription View
// $8.99/month Premium tier with payment integration

import SwiftUI
import StoreKit
import Combine

struct PremiumSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeManager = StoreManager.shared
    @State private var selectedPlan: PremiumPlan = .monthly
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum PremiumPlan {
        case monthly
        case yearly
        
        var price: String {
            switch self {
            case .monthly: return "$8.99"
            case .yearly: return "$100.00"
            }
        }
        
        var savings: String? {
            switch self {
            case .monthly: return nil
            case .yearly: return "Save 7%"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    // Header
                    headerSection
                    
                    // Feature List
                    featuresSection
                    
                    // Plan Selection
                    planSelectionSection
                    
                    // Subscribe Button
                    subscribeButton
                    
                    // Terms
                    termsSection
                }
                .padding()
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.2), .blue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "star.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Unlock Premium")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Take your game to the next level with AI-powered insights")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Features
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Premium Features")
                .font(.headline)
            
            FeatureRow(
                icon: "brain.head.profile",
                title: "AI Performance Coach",
                description: "Personalized insights and training plans",
                color: .purple
            )
            
            FeatureRow(
                icon: "calendar.badge.clock",
                title: "AI Weekly Drills",
                description: "Fresh, personalized drills every week",
                color: .cyan
            )
            
            FeatureRow(
                icon: "figure.run.circle.fill",
                title: "Wearable Sync",
                description: "Connect fitness trackers for recovery insights",
                color: .blue
            )
            
            FeatureRow(
                icon: "trophy.fill",
                title: "Tournaments",
                description: "Create and compete in tournaments",
                color: .orange
            )
            
            FeatureRow(
                icon: "chart.line.uptrend.xyaxis",
                title: "Advanced Analytics",
                description: "Performance predictions and trends",
                color: .green
            )
            
            FeatureRow(
                icon: "target",
                title: "Goals System",
                description: "Sport-specific improvement tracking",
                color: .red
            )
            
            FeatureRow(
                icon: "sparkles",
                title: "Placement Matches",
                description: "Calibrated ELO rating system",
                color: .yellow
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
    
    // MARK: - Plan Selection
    
    private var planSelectionSection: some View {
        VStack(spacing: Spacing.md) {
            Text("Choose Your Plan")
                .font(.headline)
            
            // Monthly Plan
            PlanCard(
                title: "Monthly",
                price: "$8.99",
                period: "/month",
                savings: nil,
                isSelected: selectedPlan == .monthly
            ) {
                selectedPlan = .monthly
            }
            
            // Yearly Plan
            PlanCard(
                title: "Yearly",
                price: "$100.00",
                period: "/year",
                savings: "Save 7%",
                isSelected: selectedPlan == .yearly
            ) {
                selectedPlan = .yearly
            }
        }
    }
    
    // MARK: - Subscribe Button
    
    private var subscribeButton: some View {
        Button(action: {
            Task {
                await subscribe()
            }
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "star.fill")
                    Text("Start Premium")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
        .disabled(isLoading)
    }
    
    // MARK: - Terms
    
    private var termsSection: some View {
        VStack(spacing: Spacing.sm) {
            Text("• Cancel anytime")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("• Auto-renewal can be turned off at any time")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("• Payment will be charged to iTunes Account")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }
    
    // MARK: - Subscribe Action
    
    private func subscribe() async {
        isLoading = true
        defer { isLoading = false }
        
        // Request StoreKit purchase
        let productID = selectedPlan == .monthly ? "com.sportshub.premium.monthly" : "com.sportshub.premium.yearly"
        
        let success = await storeManager.purchase(productID: productID)
        
        if success {
            // Subscription successful
            dismiss()
        } else {
            errorMessage = "Failed to subscribe. Please try again."
            showError = true
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Plan Card

struct PlanCard: View {
    let title: String
    let price: String
    let period: String
    let savings: String?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Text(period)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let savings = savings {
                        Text(savings)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .gray)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Store Manager

@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    
    // Backend subscription status (server-side Premium grants)
    @Published var backendHasPremium: Bool = false
    @Published var backendSubscriptionTier: String = "free"
    
    private var updateListenerTask: Task<Void, Error>?
    
    init() {
        updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    func loadProducts() async {
        do {
            products = try await Product.products(for: [
                "com.sportshub.premium.monthly",
                "com.sportshub.premium.yearly"
            ])
        } catch {
            print("Failed to load products: \(error)")
        }
    }
    
    func purchase(productID: String) async -> Bool {
        guard let product = products.first(where: { $0.id == productID }) else {
            return false
        }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await updatePurchasedProducts()
                    return true
                case .unverified:
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            print("Purchase failed: \(error)")
            return false
        }
    }
    
    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchasedProductIDs.insert(transaction.productID)
            }
        }
    }
    
    private func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    purchasedProductIDs.insert(transaction.productID)
                } else {
                    purchasedProductIDs.remove(transaction.productID)
                }
            }
        }
    }
    
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self.updatePurchasedProducts()
                }
            }
        }
    }
    
    /// Sync Premium status from backend subscription system
    /// Call this on login and app launch to ensure backend Premium grants are recognized
    func syncBackendSubscription() async {
        do {
            let status = try await APIClient.shared.getSubscriptionStatus()
            backendHasPremium = status.hasPremium
            backendSubscriptionTier = status.tier
            
            if APIConfig.enableDebugLogging {
                print("✓ Backend subscription synced: tier=\(status.tier), premium=\(status.hasPremium)")
            }
        } catch {
            // Non-fatal error - just log it
            // StoreKit purchases still work even if backend sync fails
            if APIConfig.enableDebugLogging {
                print("⚠️ Failed to sync backend subscription: \(error)")
            }
        }
    }
    
    /// Check if user has Premium access from ANY source
    /// This includes both StoreKit purchases AND backend-granted subscriptions
    var isPremium: Bool {
        // Premium if:
        // 1. User purchased via StoreKit, OR
        // 2. User has backend Premium subscription (e.g., admin grant, manual grant)
        !purchasedProductIDs.isEmpty || backendHasPremium
    }
}

// MARK: - Premium Badge View

struct PremiumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption)
            Text("Premium")
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [.purple, .blue],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
}
