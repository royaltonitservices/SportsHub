# Quick Troubleshooting Checklist

Use this to diagnose issues with AI Coach or Smartwatch Sync.

## 🔍 Step 1: Check Console

Open Xcode Console (`Cmd+Shift+C`) and look for patterns:

### ✅ Working Correctly
```
✅ [Debug] Backend available
✅ [APIClient] Successfully received response
✅ Connection complete
```
**You're good!** Feature is working.

### ❌ Backend Not Running
```
❌ Cannot connect to host
❌ Connection failed
⚠️ Backend not available - enabling mock mode
```
**Fix:** Start backend server
```bash
cd backend && uvicorn main:app --reload --port 8000
```

### ❌ Endpoint Missing (404)
```
❌ Endpoint not found on backend!
💡 Make sure backend has endpoint implemented
```
**Fix:** Implement missing endpoint. See:
- AI Coach: `BACKEND_IMPLEMENTATION_GUIDE.md`
- Wearables: `SMARTWATCH_SYNC_GUIDE.md`

### ❌ Permissions Issue
```
❌ Authorization denied
❌ Permission denied
```
**Fix:** 
- **AI Coach:** Log out and log back in
- **Wearables:** Settings → Privacy → Health → SportsHub

### ❌ Premium Required
```
❌ Forbidden (403)
💎 Premium subscription required
```
**Fix:** Grant Premium for testing:
```swift
#if DEBUG
StoreManager.shared.debugGrantPremium()
#endif
```

---

## 📱 Step 2: Check Environment

### Running in Simulator?

**AI Coach:**
- ✅ Should work with mock mode
- ✅ Look for: `🤖 [APIClient] MOCK MODE ENABLED`
- ⚠️ Won't connect to real backend if down

**Smartwatch:**
- ✅ Should show: "Running in iOS Simulator"
- ✅ HealthKit available but no real watch data
- ✅ Mock biometric data displays

**Action:** This is expected behavior. For full testing, use real device.

### Running on Real Device?

**Check:**
- [ ] Backend server is running and accessible
- [ ] Device can reach `http://localhost:8000` (if on same network)
- [ ] For remote testing, backend URL points to correct host

---

## 🌐 Step 3: Verify Backend

### Health Check
```bash
curl http://localhost:8000/health
```
**Expected:** `{"status":"ok"}` or similar

**If fails:** Backend not running or wrong port

### API Docs
Open: `http://localhost:8000/docs`

**Check for:**
- `/ai/coach/message` (AI Coach)
- `/wearables/connect` (Smartwatch)
- `/wearables/sync` (Smartwatch)

**If missing:** Endpoints not implemented yet

### Test with curl

**AI Coach:**
```bash
curl -X POST http://localhost:8000/ai/coach/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"message":"test","sport":"basketball"}'
```

**Wearables:**
```bash
curl -X POST http://localhost:8000/wearables/connect \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"device_type":"apple_watch"}'
```

**Expected:** JSON response, not error

---

## 🔐 Step 4: Check Auth & Premium

### Logged In?
```swift
// Check in code or console
print("Logged in: \(SessionManager.shared.currentUser != nil)")
```

**If false:** Log in first

### Premium Active?
```swift
// Check in code or console
print("Premium: \(StoreManager.shared.isPremium)")
```

**If false and needed:** Grant for testing:
```swift
#if DEBUG
StoreManager.shared.debugGrantPremium()
#endif
```

---

## 📊 Step 5: Check Data (Smartwatch)

### HealthKit Permissions
**Settings → Privacy & Security → Health → SportsHub**

Should show:
- ✅ Heart Rate - Read
- ✅ Heart Rate Variability - Read
- ✅ Steps - Read
- ✅ Active Energy - Read
- ✅ Sleep Analysis - Read

**If not:** Reconnect and grant permissions

### Health Data Available?
Open **Health app** and check:
- Heart rate data today?
- Step count today?
- Sleep data from last night?

**If empty:**
- Real device: Wear watch, record workout
- Simulator: Expected - will use mock data

---

## 🐛 Common Issues & Fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Reconnecting..." | Backend endpoint missing | Implement endpoint or enable mock mode |
| "Try again later" | Generic - check console | Look at specific error in console |
| No data displays | Backend down | Check if mock mode enabled |
| Permissions denied | User declined | Show how to enable in Settings |
| Timeout | Backend slow | Optimize backend or increase timeout |
| 403 Forbidden | Premium required | Grant Premium or check subscription |
| 404 Not Found | Endpoint missing | Implement backend route |

---

## ✅ Working Checklist

### AI Coach
- [ ] Console shows successful connection
- [ ] Type a message
- [ ] Get AI response (not "reconnecting")
- [ ] Suggested action buttons appear
- [ ] Can continue conversation

### Smartwatch
- [ ] Console shows successful connection
- [ ] HealthKit authorized
- [ ] Data syncs (or clear simulator message)
- [ ] Recovery insights display
- [ ] Recent data shows up

---

## 📚 Need More Help?

### Documentation
- **Quick Start:** `QUICK_START.md`
- **AI Coach Fix:** `AI_COACH_FIX_README.md`
- **Wearables:** `SMARTWATCH_SYNC_GUIDE.md`
- **System Summary:** `SYSTEM_WIDE_FIXES_SUMMARY.md`

### Test Tools

**AI Coach Connection Test:**
```swift
#if DEBUG
NavigationLink("Test AI Coach") {
    AICoachConnectionTestView()
}
#endif
```

**Debug Configuration:**
```swift
#if DEBUG
DebugSettings.printConfiguration()
await DebugSettings.autoConfigureMockMode()
#endif
```

---

## 🎯 Expected Results

**When working properly:**

1. **Console** shows `✅` success messages
2. **AI Coach** responds within seconds with real content
3. **Smartwatch** connects, syncs data, shows insights
4. **No generic errors** like "try again later"
5. **Clear context** when something can't work (simulator, permissions, etc.)

**If you see generic errors or stuck states,** the feature is not working as intended. Use this checklist to diagnose and fix.

---

## 🚀 Quick Fixes

### Reset Everything
```swift
// Clear AI Coach conversation
viewModel.clearConversation()

// Disconnect wearable
await disconnect()

// Log out and log back in
SessionManager.shared.logout()
```

### Force Mock Mode (Testing)
```swift
#if DEBUG
// AI Coach
DebugSettings.useAICoachMockMode = true

// Wearables already auto-enable mock in simulator
#endif
```

### Check Backend Health
```swift
#if DEBUG
Task {
    let healthy = await DebugSettings.checkBackendConnection()
    print("Backend healthy: \(healthy)")
}
#endif
```

---

**The goal:** Features should **actually work** and **clearly explain** when they can't, not show generic errors or stuck states.
