//
//  AdManager.swift
//  SportsHub
//
//  Ad monetization with Unity Ads and AdMob support
//

import Foundation
import SwiftUI
import Combine

@MainActor
class AdManager: ObservableObject {
    static let shared = AdManager()
    
    @Published var isAdLoaded = false
    @Published var rewardedAdAvailable = false
    
    // Ad configuration
    private let adProvider: AdProvider
    private var rewardCompletion: ((Bool) -> Void)?
    
    // Check if user has premium subscription
    private var isPremium: Bool {
        StoreManager.shared.isPremium
    }
    
    enum AdProvider {
        case unityAds    // Best for competitive/gaming apps
        case adMob       // Easiest to setup
        case meta        // Good for social features
        case none        // No ads (premium users)
    }
    
    private init(provider: AdProvider = .unityAds) {
        self.adProvider = provider
        setupAds()
    }
    
    // MARK: - Setup
    
    private func setupAds() {
        switch adProvider {
        case .unityAds:
            setupUnityAds()
        case .adMob:
            setupAdMob()
        case .meta:
            setupMetaAds()
        case .none:
            break
        }
    }
    
    // MARK: - Unity Ads Setup
    
    private func setupUnityAds() {
        // TODO: Add Unity Ads SDK
        // pod 'UnityAds'
        
        // Example initialization:
        // UnityAds.initialize("5678901", testMode: true) { success in
        //     if success {
        //         self.loadRewardedAd()
        //     }
        // }
        
        print("[AdManager] Unity Ads would initialize here")
        // For demo, simulate ad loaded
        isAdLoaded = true
        rewardedAdAvailable = true
    }
    
    // MARK: - AdMob Setup
    
    private func setupAdMob() {
        // TODO: Add Google Mobile Ads SDK
        // pod 'Google-Mobile-Ads-SDK'
        
        // Example initialization:
        // GADMobileAds.sharedInstance().start { status in
        //     self.loadBannerAd()
        //     self.loadInterstitialAd()
        // }
        
        print("[AdManager] AdMob would initialize here")
        isAdLoaded = true
    }
    
    // MARK: - Meta Audience Network Setup
    
    private func setupMetaAds() {
        // TODO: Add Meta Audience Network SDK
        // pod 'FBAudienceNetwork'
        
        print("[AdManager] Meta Ads would initialize here")
        isAdLoaded = true
    }
    
    // MARK: - Show Ads
    
    func showRewardedAd(completion: @escaping (Bool) -> Void) {
        // Show rewarded video ad and grant reward on completion.
        //
        // Use cases in SportsHub:
        // - Watch ad → Get extra ranked match
        // - Watch ad → Unlock premium drill
        // - Watch ad → See opponent's detailed stats
        // - Watch ad → Skip wait time for rematch
        
        // Premium users automatically get the reward without watching ads
        if isPremium {
            completion(true)
            return
        }
        
        rewardCompletion = completion
        
        switch adProvider {
        case .unityAds:
            showUnityRewardedAd()
        case .adMob:
            showAdMobRewardedAd()
        case .meta:
            showMetaRewardedAd()
        case .none:
            completion(false)
        }
    }
    
    func showInterstitialAd() {
        // Show full-screen ad between activities.
        //
        // Use cases:
        // - After completing a match
        // - After viewing leaderboard
        // - Between training sessions
        
        // Premium users don't see any ads
        if isPremium {
            return
        }
        
        switch adProvider {
        case .unityAds:
            showUnityInterstitial()
        case .adMob:
            showAdMobInterstitial()
        case .meta:
            showMetaInterstitial()
        case .none:
            break
        }
    }
    
    // MARK: - Unity Ads Implementation
    
    private func showUnityRewardedAd() {
        // Production code:
        // UnityAds.show(
        //     "Rewarded_iOS",
        //     placementId: "rewardedVideo",
        //     showDelegate: self
        // )
        
        // Demo: Simulate watching ad
        print("[Unity Ads] Showing rewarded video...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("[Unity Ads] User watched ad, granting reward")
            self.rewardCompletion?(true)
            self.rewardCompletion = nil
        }
    }
    
    private func showUnityInterstitial() {
        // UnityAds.show("Interstitial_iOS")
        print("[Unity Ads] Showing interstitial ad...")
    }
    
    // MARK: - AdMob Implementation
    
    private func showAdMobRewardedAd() {
        // Production code:
        // if let ad = rewardedAd {
        //     ad.present(fromRootViewController: viewController) {
        //         let reward = ad.adReward
        //         self.rewardCompletion?(true)
        //     }
        // }
        
        print("[AdMob] Showing rewarded ad...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.rewardCompletion?(true)
            self.rewardCompletion = nil
        }
    }
    
    private func showAdMobInterstitial() {
        // interstitialAd?.present(fromRootViewController: viewController)
        print("[AdMob] Showing interstitial ad...")
    }
    
    // MARK: - Meta Ads Implementation
    
    private func showMetaRewardedAd() {
        // Production code:
        // rewardedVideoAd?.show(fromRootViewController: viewController)
        
        print("[Meta] Showing rewarded ad...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.rewardCompletion?(true)
            self.rewardCompletion = nil
        }
    }
    
    private func showMetaInterstitial() {
        print("[Meta] Showing interstitial ad...")
    }
    
    // MARK: - Ad Placement Helpers
    
    func shouldShowAdAfterMatch() -> Bool {
        // Premium users never see ads
        if isPremium {
            return false
        }
        
        // Show interstitial ad after every 3rd match.
        // Track match count and show ad every 3 matches
        let matchCount = UserDefaults.standard.integer(forKey: "matchCount")
        return matchCount % 3 == 0
    }
    
    func canEarnReward() -> Bool {
        // Check if user can watch rewarded ad.
        // Limit to prevent abuse.
        let lastRewardTime = UserDefaults.standard.double(forKey: "lastRewardTime")
        let currentTime = Date().timeIntervalSince1970
        
        // Allow one rewarded ad every 30 minutes
        return (currentTime - lastRewardTime) > 1800
    }
    
    func trackRewardClaimed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastRewardTime")
    }
}

// MARK: - Ad Rewards

enum AdReward {
    case extraMatch        // Free ranked match
    case unlockDrill       // Premium training drill
    case detailedStats     // Opponent detailed stats
    case skipCooldown      // Skip rematch cooldown
    case profileBoost      // Highlight profile for 24h
    
    var description: String {
        switch self {
        case .extraMatch:
            return "1 Free Ranked Match"
        case .unlockDrill:
            return "Unlock Premium Drill"
        case .detailedStats:
            return "View Opponent Stats"
        case .skipCooldown:
            return "Play Again Immediately"
        case .profileBoost:
            return "24h Profile Boost"
        }
    }
    
    var iconName: String {
        switch self {
        case .extraMatch:
            return "trophy.fill"
        case .unlockDrill:
            return "figure.strengthtraining.traditional"
        case .detailedStats:
            return "chart.bar.fill"
        case .skipCooldown:
            return "clock.arrow.circlepath"
        case .profileBoost:
            return "star.fill"
        }
    }
}

// MARK: - Rewarded Ad Button

struct RewardedAdButton: View {
    let reward: AdReward
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "play.tv.fill")
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch Ad")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: reward.iconName)
                            .font(.caption)
                        Text(reward.description)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(Spacing.md)
            .background(
                LinearGradient(
                    colors: [Color.purple, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
        }
    }
}

// MARK: - Banner Ad View

struct BannerAdView: View {
    let adProvider: AdManager.AdProvider
    
    var body: some View {
        // Placeholder for banner ad
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(height: 50)
            .overlay(
                HStack {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                    Text("Ad")
                        .font(.caption)
                }
                .foregroundStyle(Color.gray)
            )
    }
}
