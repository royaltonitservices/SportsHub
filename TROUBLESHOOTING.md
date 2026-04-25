# AI Coach Connection Troubleshooting

## Quick Diagnosis

Run the app and check the Xcode Console (`Cmd+Shift+C`). Look for these patterns:

### ✅ Success Pattern
```
🔍 [Debug] Checking backend connection to http://localhost:8000...
✅ [Debug] Backend responded with status: 200
✅ [Debug] Backend available - using real API
🤖 [AI Coach] Sending message to backend...
🤖 [APIClient] Building coach message request...
🤖 [APIClient] Sending POST to /ai/coach/message...
✅ [APIClient] Successfully received coach response
✅ [AI Coach] Message added to conversation, total messages: 2
```

### ❌ Backend Not Running
```
🔍 [Debug] Checking backend connection to http://localhost:8000...
❌ [Debug] Backend connection failed: Could not connect to the server
⚠️ [Debug] Backend not available - enabling mock mode
🤖 [APIClient] MOCK MODE ENABLED - Returning simulated response
```

**Fix:** Start your backend server
```bash
cd backend
uvicorn main:app --reload --port 8000
```

### ❌ Endpoint Not Found (404)
```
🤖 [APIClient] Sending POST to /ai/coach/message...
❌ [APIClient] APIError in sendCoachMessage: notFound
❌ [APIClient] Endpoint /ai/coach/message not found on backend!
💡 [APIClient] Hint: Make sure the backend server is running and has the AI Coach endpoint implemented
```

**Fix:** Implement the backend endpoint
- See `BACKEND_IMPLEMENTATION_GUIDE.md`
- Or check your backend code has the route registered

### ❌ Timeout
```
🤖 [APIClient] Sending POST to /ai/coach/message...
❌ [APIClient] APIError in sendCoachMessage: timeout
```

**Fix:** 
- Backend is too slow
- Check if backend is doing expensive AI processing
- Consider adding response streaming
- Increase timeout (in `APIConfig.swift`)

### ❌ Unauthorized (401)
```
❌ [APIClient] APIError in sendCoachMessage: unauthorized
```

**Fix:**
- Auth token is invalid or expired
- Log out and log back in
- Check Premium subscription is active

### ❌ Forbidden (403)
```
❌ [APIClient] APIError in sendCoachMessage: forbidden
HTTP/1.1 403 Forbidden
{"detail": "AI Coach is a Premium feature"}
```

**Fix:**
- User doesn't have Premium subscription
- Check `StoreManager.shared.isPremium` returns true
- Grant Premium in debug mode:
```swift
StoreManager.shared.debugGrantPremium()
```

## Step-by-Step Debugging

### 1. Verify Backend is Running

Terminal:
```bash
curl http://localhost:8000/health
```

Expected: `{"status": "ok"}` or similar

If you get connection refused:
- Backend is not running
- Start with: `uvicorn main:app --reload --port 8000`

### 2. Check Endpoint Exists

Browser: http://localhost:8000/docs

Look for `/ai/coach/message` in the API documentation

If missing:
- Endpoint not implemented
- Router not included in main app
- Check `BACKEND_IMPLEMENTATION_GUIDE.md`

### 3. Test with curl

```bash
# First, login to get token
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=your_email@example.com&password=your_password"

# Copy the access_token from response

# Test AI Coach endpoint
curl -X POST http://localhost:8000/ai/coach/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -d '{
    "message": "test",
    "sport": "basketball"
  }'
```

Expected response:
```json
{
  "response": "...",
  "suggested_actions": [...],
  "tone": "supportive",
  "follow_up_questions": [...],
  "timestamp": "..."
}
```

### 4. Check Premium Status

In your app, add a temporary debug print:

```swift
// In AICoachChatView.swift, in sendMessage():
print("🔐 Premium status: \(storeManager.isPremium)")
```

If false:
- Grant Premium manually in Settings
- Or use debug mode:
```swift
#if DEBUG
StoreManager.shared.debugGrantPremium()
#endif
```

### 5. Enable Mock Mode for Testing

If you want to test UI without backend:

```swift
// In DebugSettings.swift or on app launch
#if DEBUG
DebugSettings.useAICoachMockMode = true
#endif
```

Or let it auto-enable when backend is unreachable.

## Common Fixes

### Fix 1: Reset Everything
```swift
// Clear conversation
DebugSettings.useAICoachMockMode = false
// Log out and log back in
// Restart backend server
```

### Fix 2: Verify Base URL

In `APIConfig.swift`:
```swift
static let baseURL = "http://localhost:8000"  // For local testing
```

Make sure this matches where your backend is running.

For iOS Simulator connecting to Mac:
- ✅ `http://localhost:8000`
- ✅ `http://127.0.0.1:8000`

For iPhone device connecting to Mac:
- ❌ `http://localhost:8000` (won't work)
- ✅ `http://YOUR_MAC_IP:8000` (e.g., `http://192.168.1.100:8000`)

### Fix 3: Check Request/Response Models

Models must match between iOS and backend.

iOS (`APIClient.swift`):
```swift
struct CoachMessageResponse: Codable {
    let response: String
    let suggestedActions: [String]
    let tone: String
    let followUpQuestions: [String]
    let timestamp: String
    
    enum CodingKeys: String, CodingKey {
        case response
        case suggestedActions = "suggested_actions"
        case tone
        case followUpQuestions = "follow_up_questions"
        case timestamp
    }
}
```

Backend (Python):
```python
class CoachMessageResponse(BaseModel):
    response: str
    suggested_actions: List[str] = []
    tone: str = "supportive"
    follow_up_questions: List[str] = []
    timestamp: str
```

Field names must match after camelCase ↔ snake_case conversion.

### Fix 4: Check Timeout

If backend is slow (AI processing):

In `APIConfig.swift`:
```swift
static let timeout: TimeInterval = 60.0  // Increase from 30 to 60 seconds
```

### Fix 5: Network Debugging

Enable network debugging in Xcode:
1. Edit Scheme (Cmd+Shift+,)
2. Run → Arguments
3. Add Environment Variable:
   - Name: `CFNETWORK_DIAGNOSTICS`
   - Value: `3`

This will show detailed network logs.

## Testing Checklist

Use this to verify everything is working:

- [ ] Backend server running (`curl http://localhost:8000/health`)
- [ ] Endpoint exists (`http://localhost:8000/docs`)
- [ ] Can login and get auth token
- [ ] Premium subscription active
- [ ] iOS app shows debug logs in Console
- [ ] Backend connection check succeeds
- [ ] AI Coach sends message
- [ ] Backend responds within timeout
- [ ] Response is parsed correctly
- [ ] Message appears in chat
- [ ] Suggested actions show up
- [ ] Can continue conversation
- [ ] No "reconnecting" fallback messages

## Still Not Working?

### Enable Full Debug Logging

Add this to your backend:

```python
import logging
logging.basicConfig(level=logging.DEBUG)

@router.post("/message")
async def send_coach_message(...):
    logging.debug(f"Received coach message: {request.message}")
    logging.debug(f"Sport: {request.sport}")
    logging.debug(f"Context: {request.context}")
    
    # ... your code ...
    
    logging.debug(f"Sending response: {response.response[:100]}...")
    return response
```

### Check Firewall

macOS:
```bash
# Check if port 8000 is open
lsof -i :8000
```

Should show Python/uvicorn process.

### Use Network Inspector

Mac: Charles Proxy or Proxyman
- See exact HTTP requests/responses
- Verify request body and headers
- Check response structure

### Contact Support

If still stuck, provide:
1. Full Xcode Console logs
2. Backend server logs
3. curl test results
4. iOS version and device
5. Backend framework/version

## Success Criteria

You'll know it's working when:
1. ✅ No "reconnecting" messages
2. ✅ AI responds within 2-5 seconds
3. ✅ Responses are contextual and relevant
4. ✅ Suggested actions appear
5. ✅ Conversation continues smoothly
6. ✅ Console shows success logs

The AI Coach should feel like a real, responsive conversation — not a series of fallback messages.
