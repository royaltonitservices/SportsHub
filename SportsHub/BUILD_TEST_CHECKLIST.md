# Build & Test Checklist

## ✅ Step 1: Clean Build (30 seconds)

In Xcode:
1. Press `Cmd+Shift+K` (Clean Build Folder)
2. Wait for "Clean Finished"

## ✅ Step 2: Build Project (1 minute)

In Xcode:
1. Press `Cmd+B` (Build)
2. Watch the build progress

**Expected:** ✅ Build Succeeded

**If errors:** See `FINAL_STATUS.md` → "If You Still See Errors"

## ✅ Step 3: Run App (Simulator or Device)

1. Press `Cmd+R` (Run)
2. App should launch successfully

## ✅ Step 4: Test AI Coach (2 minutes)

1. **Open Console:** `Cmd+Shift+C`
2. **Navigate:** Train tab → AI Coach Chat Card → Tap to open
3. **Type:** "What should I work on today?"
4. **Watch Console:** Look for:
   ```
   🤖 [AI Coach] Sending message...
   ✅ [APIClient] Successfully received response
   ```
5. **Check Response:** Should get real content (not "reconnecting")

**If backend down:** Should show mock mode message clearly

## ✅ Step 5: Test Smartwatch Sync (2 minutes)

1. **Console still open:** `Cmd+Shift+C`
2. **Navigate:** Settings/Profile → Wearable Sync
3. **Tap:** "Connect Apple Watch"
4. **Watch Console:** Look for:
   ```
   🔗 [Smartwatch] Starting connection...
   ✅ [Smartwatch] HealthKit is available
   ```
5. **Grant Permission:** If prompted
6. **Check Display:** Should show connection status

**In simulator:** Should see clear "Running in simulator" message

## ✅ Step 6: Verify Logs (1 minute)

**Console should show:**
- ✅ Emoji-tagged messages (🤖, 🔗, ✅, ❌)
- ✅ Clear operation steps
- ✅ Success or specific error messages
- ✅ No generic "try again" errors

## ✅ Step 7: Check Features Work (3 minutes)

### AI Coach:
- [ ] Opens without crashes
- [ ] Can type messages
- [ ] Gets responses (real or mock with context)
- [ ] Suggested action buttons appear
- [ ] Can continue conversation
- [ ] Never shows just "reconnecting"

### Smartwatch:
- [ ] Opens without crashes
- [ ] Shows authorization status
- [ ] Can tap "Connect Apple Watch"
- [ ] HealthKit permission request works
- [ ] Shows connection status
- [ ] Simulator shows appropriate message
- [ ] Mock data displays (simulator)
- [ ] Real data syncs (device with watch)

## 🎯 Success Criteria

**You're done when:**
- ✅ Project builds successfully
- ✅ App runs without crashes
- ✅ AI Coach responds appropriately
- ✅ Smartwatch connects properly
- ✅ Console shows clear logs
- ✅ No generic error loops

## ❌ If Something Fails

### Build Fails
→ See `COMPILATION_FIXED.md`
→ Check for duplicate model definitions

### AI Coach Shows "Reconnecting"
→ See `TROUBLESHOOTING_CHECKLIST.md`
→ Check backend is running
→ Verify mock mode enabled if needed

### Smartwatch Shows Generic Error
→ See `SMARTWATCH_SYNC_GUIDE.md`
→ Check HealthKit permissions
→ Verify simulator vs device expectations

### Console Errors
→ Read the specific error message
→ Look for emoji-tagged hints (💡)
→ Follow suggestions in error message

## 📚 Documentation

- `FINAL_STATUS.md` - Complete status and next steps
- `QUICK_START.md` - AI Coach 5-minute setup
- `SYSTEM_WIDE_FIXES_SUMMARY.md` - What was fixed
- `TROUBLESHOOTING_CHECKLIST.md` - Diagnostic guide

## 🚀 After Verification

Once everything works:
1. Implement backend endpoints (if needed)
2. Test on real device with Apple Watch
3. Review integration with other features
4. Deploy to TestFlight/production

---

**Expected time:** 10 minutes total to verify everything works
