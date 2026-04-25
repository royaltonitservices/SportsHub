# Smartwatch/Fitness Tracker Sync - Implementation Guide

## ✅ What Was Fixed

The fitness tracker sync was showing a generic "We're having trouble syncing your watch right now" error instead of:
- Actually connecting to HealthKit
- Providing specific error messages based on the actual issue
- Working properly in the simulator with clear expectations
- Handling backend unavailability gracefully
- Syncing real data when available

## 🏗️ How It Works Now

### Architecture

```
┌─────────────────┐
│ SmartwatchSync  │
│     View        │
└────────┬────────┘
         │
         ├─────────► HealthKitManager (reads device data)
         │
         └─────────► APIClient (syncs to backend)
                              │
                              ├─► Real backend (production)
                              └─► Mock data (development/simulator)
```

### Connection Flow

1. **Check HealthKit Availability**
   - Is HealthKit available on this device?
   - Are we in simulator? (clear message if so)

2. **Request Permissions**
   - Prompt user for HealthKit permissions
   - Explain what permissions are needed and why

3. **Connect to Backend**
   - Register device with backend
   - Handle Premium requirement
   - Handle backend unavailability gracefully

4. **Sync Data**
   - Fetch health data from HealthKit
   - Send to backend (if available)
   - Store locally regardless
   - Load recovery insights

### States Handled

| State | Behavior |
|-------|----------|
| **Simulator** | Shows clear message, works with mock data |
| **No Permissions** | Explains how to grant in Settings |
| **Backend Down** | Works with local HealthKit data, clear dev message |
| **Endpoint Missing** | Explains endpoint not implemented yet |
| **Premium Required** | Shows upgrade prompt |
| **No Data Yet** | Suggests recording a workout first |
| **Success** | Shows connection, syncs data, displays insights |

## 📱 Features

### Data Collected

From HealthKit:
- ✅ Heart rate (avg, resting, max)
- ✅ Heart rate variability (HRV)
- ✅ Sleep duration and quality
- ✅ Steps
- ✅ Active calories
- ✅ Exercise minutes
- ✅ VO2 Max

### AI-Powered Insights

- **Recovery Score** (0-100) - How recovered you are
- **Fatigue Level** (low/medium/high) - Training load impact
- **Sleep Quality** (0-100) - Sleep effectiveness
- **Training Recommendations** - Based on recovery status

### Integration Points

The wearable data integrates with:
1. **AI Coach** - Personalized training advice based on recovery
2. **Daily Readiness** - Should you train hard today?
3. **Training Plans** - Adaptive difficulty based on fatigue
4. **Performance Tracking** - Correlate training with biometrics

## 🚀 Testing

### On Real Device

1. **Connect Apple Watch**
   - Pair watch with iPhone
   - Open Health app to verify data syncing

2. **Grant Permissions**
   - Run app
   - Tap "Connect Apple Watch"
   - Grant HealthKit permissions when prompted

3. **Record Activity**
   - Workout on Apple Watch
   - Wait for data to sync to Health app
   - Tap "Sync Now" in SportsHub

4. **Verify**
   - Check Console for logs
   - See data appear in app
   - View recovery insights

### In Simulator

1. **Understand Limitations**
   - Simulator has HealthKit but no real watch data
   - Shows clear message about simulator mode
   - Works with mock data for UI testing

2. **Connect**
   - Tap "Connect Apple Watch"
   - See simulator notice
   - Grant permissions if prompted

3. **View Mock Data**
   - See sample biometric data
   - Recovery insights still work
   - Test UI interactions

## 🔍 Console Logging

All operations are logged:

```
🔗 [Smartwatch] Starting connection process...
✅ [Smartwatch] HealthKit is available
🔐 [Smartwatch] Requesting HealthKit permissions...
✅ [Smartwatch] HealthKit authorized
🌐 [Smartwatch] Connecting to backend...
✅ [Smartwatch] Backend connection established
🔄 [Smartwatch] Starting sync...
📊 [HealthKit] Fetching today's data...
✅ [HealthKit] Heart rate: 72 bpm
✅ [HealthKit] Steps: 5234
✅ [Smartwatch] Data synced to backend
✅ [Smartwatch] Sync complete
```

## ⚙️ Backend API

### Endpoints Required

#### 1. Connect Device
```http
POST /wearables/connect
Authorization: Bearer {token}
Content-Type: application/json

{
  "device_type": "apple_watch",
  "device_name": "Apple Watch",
  "device_id": null,
  "access_token": null,
  "refresh_token": null
}
```

**Response:**
```json
{
  "id": "conn_123",
  "user_id": "user_456",
  "device_type": "apple_watch",
  "device_name": "Apple Watch",
  "provider": "apple_watch",
  "is_active": true,
  "last_sync": "2026-04-07T10:30:00Z",
  "created_at": "2026-04-07T10:00:00Z"
}
```

#### 2. Sync Biometric Data
```http
POST /wearables/sync
Authorization: Bearer {token}
Content-Type: application/json

{
  "id": "data_789",
  "date": "2026-04-07T00:00:00Z",
  "resting_heart_rate": 58,
  "heart_rate_variability": 65,
  "sleep_duration": 450,
  "steps": 8234,
  "active_calories": 456,
  "exercise_minutes": 45
}
```

#### 3. Get Recovery Status
```http
GET /wearables/recovery
Authorization: Bearer {token}
```

**Response:**
```json
{
  "id": "recovery_999",
  "user_id": "user_456",
  "date": "2026-04-07",
  "readiness_score": 82,
  "fatigue_level": "low",
  "sleep_quality": 85,
  "hrv": 65,
  "resting_heart_rate": 58,
  "recommendation": "You're well-rested...",
  "created_at": "2026-04-07T08:00:00Z"
}
```

#### 4. Get Recent Data
```http
GET /wearables/data?days=7
Authorization: Bearer {token}
```

**Response:** Array of biometric data objects

### Backend Implementation (Python/FastAPI)

See `BACKEND_WEARABLES_GUIDE.md` for complete implementation.

Quick example:

```python
from fastapi import APIRouter, Depends
from app.core.auth import get_current_user

router = APIRouter(prefix="/wearables", tags=["Wearables"])

@router.post("/connect")
async def connect_device(
    request: ConnectDeviceRequest,
    current_user: User = Depends(get_current_user)
):
    # Check Premium (if required)
    if not current_user.premium_subscription:
        raise HTTPException(403, "Premium required")
    
    # Create connection record
    connection = create_wearable_connection(current_user.id, request)
    return connection

@router.post("/sync")
async def sync_biometric_data(
    data: BiometricData,
    current_user: User = Depends(get_current_user)
):
    # Store biometric data
    store_biometric_data(current_user.id, data)
    
    # Calculate recovery metrics
    recovery = calculate_recovery_status(current_user.id, data)
    
    return {"message": "Data synced successfully"}
```

## 🐛 Error Handling

### User-Friendly Messages

**Simulator:**
```
Running in iOS Simulator

HealthKit is available in the simulator, but won't have real 
watch data. On a real device, this connects to your Apple Watch.

You can still test the UI with simulated data.
```

**Permissions Denied:**
```
We need your permission to access health data.

Please grant access when prompted, or enable it in:
Settings → Privacy & Security → Health → SportsHub
```

**Backend Not Running (Dev):**
```
Cannot connect to backend server.

Make sure your development server is running:
cd backend && uvicorn main:app --reload --port 8000

HealthKit data is still being read locally.
```

**No Data Available:**
```
No health data found. Make sure your watch is recording 
workouts and try syncing again.
```

### Error Codes

| Error | Cause | Action |
|-------|-------|--------|
| `healthKitUnavailable` | Not available on device | Show device requirement |
| `permissionDenied` | User declined permissions | Show Settings instructions |
| `notFound` (404) | Backend endpoint missing | Dev message, work locally |
| `forbidden` (403) | Premium required | Show upgrade prompt |
| `cannotConnectToHost` | Backend down | Dev server instructions |
| `timeout` | Slow backend | Retry suggestion |

## 🎯 Integration with AI Coach

The wearable data enhances AI Coach responses:

```swift
// In CoachContext
var wearableData: WearableContext? = WearableContext(
    restingHeartRate: 58,
    hrv: 65,
    sleepHours: 7.5,
    stepsToday: 8234,
    recoveryScore: "high"
)
```

AI Coach can then say:
- "I see your HRV is 65ms and you slept well last night. You're ready for high-intensity training!"
- "Your recovery score is low today. Let's focus on technique work instead of conditioning."
- "You've only gotten 5 hours of sleep. Consider a rest day or light active recovery."

## ✅ Success Criteria

The feature works when:
- [ ] Connects successfully on real device
- [ ] Shows clear messages in simulator
- [ ] Handles permissions properly
- [ ] Works locally when backend unavailable
- [ ] Provides specific error messages
- [ ] Syncs real HealthKit data
- [ ] Shows recovery insights
- [ ] Integrates with AI Coach
- [ ] Never shows generic "try again" without context

## 📚 Files

- `SmartwatchSyncView.swift` - UI and connection logic
- `WearableModels.swift` - Data models
- `APIClient.swift` - Network layer with mock support
- `HealthKitManager.swift` - HealthKit integration
- `BACKEND_WEARABLES_GUIDE.md` - Backend implementation

## 🚀 Future Enhancements

1. **More Providers** - Fitbit, Garmin, WHOOP, Oura
2. **Advanced Metrics** - Training load, strain, adaptation
3. **Predictive AI** - Injury risk, performance forecasting
4. **Real-time Sync** - Background updates
5. **Workout Analysis** - Detailed performance breakdowns

The smartwatch sync now provides real value by actually connecting and syncing data, not just showing error messages.
