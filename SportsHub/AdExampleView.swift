//
//  AdExampleView.swift
//  SportsHub
//
//  Examples of ad integration in SportsHub
//

import SwiftUI

struct AdExampleView: View {
    @StateObject private var adManager = AdManager.shared
    @State private var showRewardSuccess = false
    @State private var earnedReward: AdReward?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Example 1: Rewarded Ad for Extra Match
                    rewardedAdSection
                    
                    // Example 2: Banner Ad in Feed
                    bannerAdExample
                    
                    // Example 3: Interstitial After Match
                    interstitialAdInfo
                    
                    // Revenue Info
                    revenueInfoSection
                }
                .padding(Spacing.md)
            }
            .background(Color.appBackground)
            .navigationTitle("Ad Integration")
            .alert("Reward Earned!", isPresented: $showRewardSuccess) {
                Button("OK") {}
            } message: {
                if let reward = earnedReward {
                    Text("You earned: \(reward.description)")
                }
            }
        }
    }
    
    private var rewardedAdSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Rewarded Ads (Highest Revenue)")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            Text("Users watch video → get reward. $10-40 CPM!")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            
            // Example rewards
            VStack(spacing: Spacing.sm) {
                RewardedAdButton(reward: .extraMatch) {
                    watchRewardedAd(for: .extraMatch)
                }
                
                RewardedAdButton(reward: .unlockDrill) {
                    watchRewardedAd(for: .unlockDrill)
                }
                
                RewardedAdButton(reward: .detailedStats) {
                    watchRewardedAd(for: .detailedStats)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private var bannerAdExample: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Banner Ads ($1-3 CPM)")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            Text("Small ads in feed, less intrusive")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            
            // Example feed with banner
            VStack(spacing: Spacing.sm) {
                feedItemExample(title: "Alex won a match")
                BannerAdView(adProvider: .unityAds)
                feedItemExample(title: "Morgan earned Gold rank")
                feedItemExample(title: "Taylor posted a clip")
                BannerAdView(adProvider: .adMob)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private var interstitialAdInfo: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Interstitial Ads ($3-7 CPM)")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            Text("Full-screen between activities")
                .font(.subheadline)
                .foregroundStyle(Color.appTextSecondary)
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("After every 3rd match")
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("When viewing leaderboard")
                }
                
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("After watching clips")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Color.appTextSecondary)
            
            Button(action: {
                adManager.showInterstitialAd()
            }) {
                HStack {
                    Image(systemName: "rectangle.fill.on.rectangle.fill")
                    Text("Show Interstitial (Demo)")
                }
                .frame(maxWidth: .infinity)
            }
            .primaryButton()
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private var revenueInfoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Revenue Potential 💰")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                revenueRow(users: "1,000", daily: "$10", monthly: "$300")
                revenueRow(users: "10,000", daily: "$100", monthly: "$3,000")
                revenueRow(users: "100,000", daily: "$1,000", monthly: "$30,000")
            }
            
            Text("Based on 5 ads/user/day at $2 average CPM")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, Spacing.xs)
        }
        .padding(Spacing.md)
        .cardBackground()
    }
    
    private func feedItemExample(title: String) -> some View {
        HStack {
            Circle()
                .fill(Color.appPrimary.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(Color.appPrimary)
                )
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.appTextPrimary)
            
            Spacer()
        }
        .padding(Spacing.sm)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }
    
    private func revenueRow(users: String, daily: String, monthly: String) -> some View {
        HStack {
            Text("\(users) users:")
                .fontWeight(.medium)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(daily + "/day")
                    .font(.caption)
                Text(monthly + "/month")
                    .fontWeight(.bold)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Color.appTextPrimary)
        .padding(Spacing.sm)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }
    
    private func watchRewardedAd(for reward: AdReward) {
        guard adManager.canEarnReward() else {
            // Show cooldown message
            return
        }
        
        adManager.showRewardedAd { success in
            if success {
                earnedReward = reward
                showRewardSuccess = true
                adManager.trackRewardClaimed()
                
                // Grant the actual reward
                switch reward {
                case .extraMatch:
                    // TODO: Grant extra ranked match
                    break
                case .unlockDrill:
                    // TODO: Unlock premium drill
                    break
                case .detailedStats:
                    // TODO: Show detailed opponent stats
                    break
                case .skipCooldown:
                    // TODO: Reset match cooldown
                    break
                case .profileBoost:
                    // TODO: Boost profile visibility
                    break
                }
            }
        }
    }
}

#Preview {
    AdExampleView()
}
