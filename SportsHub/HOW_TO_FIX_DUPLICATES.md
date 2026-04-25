# URGENT: How to Fix Duplicate Model Errors

## The Problem

You're seeing these compilation errors:
```
❌ Invalid redeclaration of 'WearableProvider'
❌ Invalid redeclaration of 'SmartwatchConnection'
❌ Invalid redeclaration of 'BiometricData'
❌ Invalid redeclaration of 'RecoveryStatus'
❌ Invalid redeclaration of 'ConnectDeviceRequest'
```

**Translation:** These types are defined in 2+ places, and Swift won't allow that.

## Quick Diagnostic

### Step 1: Find the Duplicates

**In Xcode:**
1. Press `Cmd+Shift+F` (Find in Project)
2. Search for: `struct BiometricData`
3. You should see it in 2+ files

**In Terminal:**
```bash
cd YourProjectFolder
grep -rn "struct BiometricData" --include="*.swift"
```

This will show you EVERY file that has this definition with line numbers.

###Step 2: Identify the Files

You'll likely find definitions in:
- ✅ `WearableModels.swift` (this is CORRECT - keep this one)
- ❌ Some other file (this is the DUPLICATE - delete it)

Common places for duplicates:
- Old `SmartwatchModels.swift` or `WearableTypes.swift`
- Bottom of `SmartwatchSyncView.swift`
- Inside `APIClient.swift`
- Old `APIModels.swift` or similar

## The Fix

### Option 1: Manual Fix (Recommended)

1. **Find ALL duplicate definitions** using Xcode search or grep
2. **Delete duplicates** - Keep ONLY the ones in `WearableModels.swift`
3. **Clean build folder** - `Cmd+Shift+K` in Xcode
4. **Build** - `Cmd+B`

### Option 2: Nuclear Option (If You Can't Find Them)

If you can't find the duplicates, recreate the file:

1. **In Xcode Navigator:**
   - Right-click `WearableModels.swift`
   - Select "Delete" → "Move to Trash"

2. **Create new file:**
   - File → New → File
   - Choose "Swift File"
   - Name it `WearableModels.swift`
   - Make sure it's added to your app target (check the box)

3. **Copy content back:**
   - Paste the full content from below

4. **Clean and Build:**
   - `Cmd+Shift+K` (Clean)
   - `Cmd+B` (Build)

## Correct WearableModels.swift Content

This is what should be in `WearableModels.swift` and NOWHERE else:

```swift
//
//  WearableModels.swift
//  SportsHub
//
//  Models for smartwatch and fitness tracker integration
//

import Foundation

// MARK: - Wearable Provider

enum WearableProvider: String, Codable, CaseIterable {
    case appleWatch = "apple_watch"
    case fitbit = "fitbit"
    case garmin = "garmin"
    case whoop = "whoop"
    case oura = "oura"
    
    var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .fitbit: return "Fitbit"
        case .garmin: return "Garmin"
        case .whoop: return "WHOOP"
        case .oura: return "Oura Ring"
        }
    }
    
    var icon: String {
        switch self {
        case .appleWatch: return "applewatch"
        case .fitbit: return "figure.run.circle"
        case .garmin: return "figure.run.circle"
        case .whoop: return "waveform.path.ecg"
        case .oura: return "circle"
        }
    }
}

// MARK: - Connection Models

struct SmartwatchConnection: Codable, Identifiable {
    let id: String
    let userId: String
    let deviceType: String
    let deviceName: String?
    let deviceId: String?
    let provider: WearableProvider?
    let isActive: Bool
    let lastSync: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceType = "device_type"
        case deviceName = "device_name"
        case deviceId = "device_id"
        case provider
        case isActive = "is_active"
        case lastSync = "last_sync"
        case createdAt = "created_at"
    }
}

struct ConnectDeviceRequest: Codable {
    let deviceType: String
    let deviceName: String?
    let deviceId: String?
    let accessToken: String?
    let refreshToken: String?
    
    enum CodingKeys: String, CodingKey {
        case deviceType = "device_type"
        case deviceName = "device_name"
        case deviceId = "device_id"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Biometric Data

struct BiometricData: Codable, Identifiable {
    let id: String
    let date: String
    
    // Heart Rate Metrics
    let restingHeartRate: Int?
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let heartRateVariability: Int?  // HRV in ms
    
    // Sleep Metrics
    let sleepDuration: Int?  // Total sleep in minutes
    let deepSleep: Int?      // Deep sleep in minutes
    let remSleep: Int?       // REM sleep in minutes
    let lightSleep: Int?     // Light sleep in minutes
    let sleepQualityScore: Double?  // 0-100
    
    // Activity Metrics
    let steps: Int?
    let activeCalories: Int?
    let totalCalories: Int?
    let exerciseMinutes: Int?
    
    // Recovery Metrics
    let recoveryScore: Double?  // 0-100
    let trainingStrain: Double?  // WHOOP-style strain
    let dayStrain: Double?
    
    // AI-Generated Insights
    let readinessScore: Double?  // 0-100
    let fatigueLevel: String?    // "low", "medium", "high"
    let performancePrediction: String?
    
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, date
        case restingHeartRate = "resting_heart_rate"
        case avgHeartRate = "avg_heart_rate"
        case maxHeartRate = "max_heart_rate"
        case heartRateVariability = "heart_rate_variability"
        case sleepDuration = "sleep_duration"
        case deepSleep = "deep_sleep"
        case remSleep = "rem_sleep"
        case lightSleep = "light_sleep"
        case sleepQualityScore = "sleep_quality_score"
        case steps
        case activeCalories = "active_calories"
        case totalCalories = "total_calories"
        case exerciseMinutes = "exercise_minutes"
        case recoveryScore = "recovery_score"
        case trainingStrain = "training_strain"
        case dayStrain = "day_strain"
        case readinessScore = "readiness_score"
        case fatigueLevel = "fatigue_level"
        case performancePrediction = "performance_prediction"
        case createdAt = "created_at"
    }
}

// MARK: - Recovery Status

struct RecoveryStatus: Codable, Identifiable {
    let id: String
    let userId: String
    let date: String
    
    let readinessScore: Double?  // 0-100
    let fatigueLevel: String     // "low", "medium", "high", "very_high"
    let sleepQuality: Double?    // 0-100
    let hrv: Int?
    let restingHeartRate: Int?
    
    let recommendation: String   // AI-generated training recommendation
    
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case readinessScore = "readiness_score"
        case fatigueLevel = "fatigue_level"
        case sleepQuality = "sleep_quality"
        case hrv
        case restingHeartRate = "resting_heart_rate"
        case recommendation
        case createdAt = "created_at"
    }
}

// Note: MessageResponse is already defined in APIModels.swift
```

## Verification

After fixing, you should be able to:

1. **Build without errors** - `Cmd+B` in Xcode
2. **No "ambiguous" or "redeclaration" errors**
3. **Types resolve correctly** - No red underlines in code

## If It Still Fails

### Check Target Membership

1. Select `WearableModels.swift` in Xcode
2. Open File Inspector (right sidebar)
3. Under "Target Membership", make sure your app target is checked

### Check for Hidden Duplicates

Sometimes old files are in the project but not visible. Check:

1. **Project Navigator** - Look for any `*Models.swift` files
2. **Derived Data** - Clean: `Cmd+Shift+K`
3. **Restart Xcode** - Sometimes helps with index issues

### Last Resort

If nothing works:

1. Create a NEW Swift file called `WearableModels2.swift`
2. Paste the content above
3. Delete the old `WearableModels.swift`
4. Rename `WearableModels2.swift` to `WearableModels.swift`

This forces Xcode to completely forget about the old file.

## Why This Happened

When I created `WearableModels.swift`, these types might have already existed elsewhere in your project (perhaps you had started implementing them before). Swift doesn't allow duplicate type definitions in the same module.

The fix is simple: **One definition only, one location only.**

---

**Bottom line:** Find where these 5 types are defined besides `WearableModels.swift`, and delete those duplicate definitions. The project will then compile successfully.
