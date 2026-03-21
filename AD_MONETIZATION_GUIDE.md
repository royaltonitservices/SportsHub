# SportsHub Ad Monetization Guide

Complete guide to monetizing SportsHub with ads while keeping it free for users.

---

## 🎯 **Best Ad Strategy for SportsHub**

### Recommended: **Unity Ads** (Best for Competitive Apps)

**Why Unity Ads**:
- ✅ **Rewarded videos** = highest revenue ($10-40 CPM)
- ✅ Perfect for competitive/gaming apps
- ✅ Users **want** to watch for rewards
- ✅ Non-intrusive, enhances experience
- ✅ FREE to join, no minimum traffic

---

## 💰 **Revenue Potential**

### Your Ad Strategy (Optimized for Engagement):
```
User Journey:
1. Opens app → No ads (good first impression)
2. Plays 3 matches → Interstitial ad ($3-7 CPM)
3. Wants extra match → Watches rewarded video ($10-40 CPM)
4. Views feed → Banner ad every 5 posts ($1-3 CPM)
5. Watches clips → Banner ad in feed
```

### Revenue Calculator:

#### **1,000 Daily Active Users**
```
Daily Ads per User: 5
- 2 rewarded videos ($20 CPM avg) = 2,000 impressions
- 2 interstitials ($5 CPM avg) = 2,000 impressions
- 1 banner ($2 CPM avg) = 1,000 impressions

Revenue:
- Rewarded: (2,000 ÷ 1,000) × $20 = $40/day
- Interstitial: (2,000 ÷ 1,000) × $5 = $10/day
- Banner: (1,000 ÷ 1,000) × $2 = $2/day

Daily Total: $52
Monthly Total: ~$1,560
Yearly Total: ~$18,720
```

#### **10,000 Daily Active Users**
```
Monthly Revenue: ~$15,600
Yearly Revenue: ~$187,200
```

#### **100,000 Daily Active Users**
```
Monthly Revenue: ~$156,000
Yearly Revenue: ~$1,872,000
```

---

## 🚀 **Setup Guide: Unity Ads**

### Step 1: Create Unity Ads Account (FREE)
```bash
1. Go to unity.com/solutions/unity-ads
2. Click "Get Started" (FREE)
3. Create Unity ID
4. Create new project: "SportsHub"
5. Enable Ads monetization
6. Note your Game ID (e.g., "5678901")
```

### Step 2: Add Unity Ads to iOS

#### Install Unity Ads SDK:
```ruby
# Add to Podfile
pod 'UnityAds'

# Then run:
pod install
```

#### Initialize in AppDelegate:
```swift
import UnityAds

func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    // Initialize Unity Ads
    UnityAds.initialize(
        "5678901",  // Your Game ID
        testMode: true,  // Set to false in production
        initializationDelegate: self
    )

    return true
}
```

#### Update AdManager.swift:
```swift
// Uncomment Unity Ads code in AdManager.swift (lines 45-60)
import UnityAds

private func setupUnityAds() {
    UnityAds.initialize(
        "5678901",  // Your Game ID
        testMode: false,
        initializationDelegate: self
    )
}

private func showUnityRewardedAd() {
    UnityAds.show(
        viewController,
        placementId: "Rewarded_iOS",
        showDelegate: self
    )
}
```

### Step 3: Implement in Your App

Already done! Just enable Unity Ads:

```swift
// PlayView.swift - Add rewarded ad for extra match
Button("Watch Ad for Free Match") {
    AdManager.shared.showRewardedAd { success in
        if success {
            // Grant extra match
            self.freeMatchesAvailable += 1
        }
    }
}

// MatchResultView.swift - Show interstitial after match
.onAppear {
    if AdManager.shared.shouldShowAdAfterMatch() {
        AdManager.shared.showInterstitialAd()
    }
}
```

### Step 4: Create Ad Placements in Unity Dashboard

```bash
1. Login to Unity Dashboard
2. Monetization → Ad Placements
3. Create placements:
   - "Rewarded_iOS" (Rewarded Video)
   - "Interstitial_iOS" (Interstitial)
   - "Banner_iOS" (Banner)
4. Enable for iOS
5. Save
```

---

## 📊 **Alternative: Google AdMob**

### Setup AdMob (Easier but Lower Revenue)

#### Step 1: Create AdMob Account
```bash
1. Go to admob.google.com
2. Sign in with Google account
3. Create app: "SportsHub"
4. Platform: iOS
5. Note App ID: ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY
```

#### Step 2: Install SDK
```ruby
# Podfile
pod 'Google-Mobile-Ads-SDK'

# Install
pod install
```

#### Step 3: Initialize
```swift
import GoogleMobileAds

func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    GADMobileAds.sharedInstance().start(completionHandler: nil)
    return true
}
```

#### Step 4: Update Info.plist
```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>

<key>SKAdNetworkItems</key>
<array>
    <dict>
        <key>SKAdNetworkIdentifier</key>
        <string>cstr6suwn9.skadnetwork</string>
    </dict>
</array>
```

---

## 🎮 **Ad Placement Strategy**

### 1. **Rewarded Videos** (Highest Revenue)

**Where to Place**:
```swift
✅ Extra ranked match (most used!)
✅ Unlock premium drill
✅ View opponent's detailed stats
✅ Skip rematch cooldown
✅ Profile boost (24h visibility)
✅ Unlock badge early
```

**Best Practices**:
- Limit to 3-5 per day per user
- Make rewards valuable
- Show before match starts
- Clear "Watch Ad" button

### 2. **Interstitial Ads** (Medium Revenue)

**Where to Place**:
```swift
✅ After every 3rd match
✅ When viewing leaderboard
✅ After watching 3 clips
✅ When switching sports
✅ After posting content
```

**Best Practices**:
- Don't interrupt gameplay
- Show at natural breaks
- Max 1 per 5 minutes
- Closeable after 5 seconds

### 3. **Banner Ads** (Lowest Revenue, Least Intrusive)

**Where to Place**:
```swift
✅ Bottom of feed (every 5 posts)
✅ Bottom of leaderboard
✅ Profile page (non-obtrusive)
✅ Search results
```

**Best Practices**:
- Bottom of screen only
- Don't cover navigation
- Max 1 per screen
- Match app design

---

## 💡 **Rewarded Ad Ideas for SportsHub**

### 1. **Extra Matches**
```swift
"Out of ranked matches for today?
 Watch a short video for 1 free match!"

Revenue: $20 CPM × high demand = 💰💰💰
```

### 2. **Unlock Premium Drills**
```swift
"Want advanced basketball drills?
 Watch ad to unlock for 24 hours!"

Revenue: $15 CPM × engaged users = 💰💰
```

### 3. **Opponent Intel**
```swift
"See opponent's match history & weaknesses?
 Watch ad for detailed stats!"

Revenue: $25 CPM × competitive users = 💰💰💰
```

### 4. **Skip Cooldowns**
```swift
"Rematch available in 30 minutes.
 Watch ad to play immediately!"

Revenue: $30 CPM × impatient users = 💰💰💰
```

### 5. **Profile Boost**
```swift
"Boost your profile to top of matchmaking
 for 24 hours! Watch ad to activate."

Revenue: $20 CPM × social users = 💰💰
```

---

## 📈 **Optimization Tips**

### 1. **Frequency Capping**
```swift
// Limit ads per user per day
let maxRewardedAdsPerDay = 5
let maxInterstitialsPerDay = 10
let minTimeBetweenAds = 180 // 3 minutes
```

### 2. **User Segmentation**
```swift
// New users (0-7 days): Show fewer ads
if userDaysSinceSignup <= 7 {
    showAdFrequency = .low
}

// Active users (7+ days): Normal ads
else if userDaysSinceSignup > 7 {
    showAdFrequency = .medium
}

// Power users (daily players): More rewarded ads
if userPlaysDaily {
    showAdFrequency = .highRewarded
}
```

### 3. **A/B Testing**
```swift
// Test different strategies
Group A: Interstitial every 3 matches
Group B: Interstitial every 5 matches

// Measure:
- User retention
- Session length
- Revenue per user
```

### 4. **Premium Option** (No Ads)
```swift
// Offer ad-free version
$2.99/month → Remove all ads
$19.99/year → Remove all ads + bonus features

// Expected conversion: 2-5% of users
// Example: 10,000 users × 3% × $2.99 = $897/month extra
```

---

## 🎯 **Implementation Checklist**

### Week 1: Setup
- [ ] Create Unity Ads account
- [ ] Add Unity Ads SDK to project
- [ ] Create ad placements in dashboard
- [ ] Initialize SDK in app
- [ ] Test ads in development

### Week 2: Integration
- [ ] Add rewarded ad for extra matches
- [ ] Add interstitial after 3 matches
- [ ] Add banner in feed
- [ ] Implement frequency capping
- [ ] Add analytics tracking

### Week 3: Testing
- [ ] Test all ad types
- [ ] Verify rewards are granted
- [ ] Check ad frequency
- [ ] Test on real devices
- [ ] Monitor fill rates

### Week 4: Optimize
- [ ] Review analytics
- [ ] Adjust ad frequency
- [ ] A/B test placements
- [ ] Add more rewarded options
- [ ] Monitor revenue

---

## 💸 **Payment & Earnings**

### Unity Ads Payments
- **Minimum**: $100
- **Frequency**: Monthly (NET 60 days)
- **Methods**: PayPal, Wire Transfer
- **Reporting**: Real-time dashboard

### Expected Timeline to First Payment
```
Month 1:
- 100 users → ~$50 (below minimum)

Month 2:
- 500 users → ~$250 (first payment! 🎉)

Month 3:
- 1,000 users → ~$1,500

Month 6:
- 5,000 users → ~$7,500

Year 1:
- 10,000 users → ~$15,000/month
```

---

## 🚫 **What NOT to Do**

### ❌ **Bad Ad Practices**:
1. Showing ads during gameplay
2. Forcing ads before letting user play
3. Too many interstitials (max 1 per 5 min)
4. Fake "close" buttons
5. Ads on first app open
6. Auto-playing video ads with sound

### ✅ **Good Ad Practices**:
1. Rewarded ads with clear value
2. Natural ad breaks
3. Respectful frequency
4. Clear close buttons
5. Silent banner ads
6. User choice for rewarded ads

---

## 📊 **Analytics to Track**

### Key Metrics:
```swift
1. Ad Impressions per User
   Target: 5-10/day

2. Ad Fill Rate
   Target: >90%

3. eCPM (effective CPM)
   Target: >$5

4. User Retention
   Day 1: >40%
   Day 7: >20%
   Day 30: >10%

5. Revenue per DAU
   Target: >$0.50

6. Rewarded Ad Completion Rate
   Target: >80%
```

---

## 🎁 **Bonus: Premium Subscription**

### Hybrid Model (Ads + Premium)
```swift
FREE Version:
- All features available
- Watch ads for bonuses
- Revenue: ~$1.50/user/month

PREMIUM Version ($4.99/month):
- No ads
- 2x daily matches
- Exclusive badge
- Profile boost
- Revenue: $4.99/user/month

Expected:
- 95% free users → $1.50 each
- 5% premium users → $4.99 each

10,000 users:
- 9,500 free × $1.50 = $14,250
- 500 premium × $4.99 = $2,495
Total: $16,745/month 🎉
```

---

## 🏁 **Getting Started (30 Minutes)**

### Quick Setup:
```bash
1. Go to unity.com/solutions/unity-ads (5 min)
2. Create account, note Game ID (5 min)
3. Add to Podfile: pod 'UnityAds' (2 min)
4. Run pod install (2 min)
5. Add initialization code (5 min)
6. Uncomment AdManager.swift Unity code (5 min)
7. Test rewarded ad (5 min)
8. Deploy! (1 min)

Total time: 30 minutes
Total cost: $0
Potential revenue: $1,500+/month at 1,000 users
```

---

## 📞 **Support**

- **Unity Ads Support**: https://support.unity.com/
- **AdMob Support**: https://support.google.com/admob
- **iOS Ads Best Practices**: https://developer.apple.com/app-store/

---

**Your code is ready! Just add the SDK and start earning.** 🚀💰

Revenue potential: $1,500+/month with 1,000 daily users
Setup time: 30 minutes
Cost: $0

Good luck! 🎉
