# AI Coach Connection Fix

## Problem
The AI Coach was immediately falling back to "reconnecting" messages instead of connecting to the backend and providing real responses.

## Root Cause
- Backend endpoint `/ai/coach/message` was not being reached successfully
- Error handling was too aggressive, showing fallbacks on first failure
- No visibility into what was actually failing (connection, endpoint missing, etc.)
- No development mode for testing without a backend

## Solution Implemented

### 1. Enhanced Logging
Added comprehensive logging throughout the connection flow:
- Request building and sending
- Response receiving and parsing
- Error types and descriptions
- Connection health checks

**Look for these logs in Xcode console:**
```
🤖 [AI Coach] Sending message to backend...
🤖 [APIClient] Building coach message request...
🤖 [APIClient] Request body: {...}
🤖 [APIClient] Sending POST to /ai/coach/message...
✅ [APIClient] Successfully received coach response
✅ [AI Coach] Message added to conversation
```

### 2. Debug Settings
Created `DebugSettings.swift` with automatic backend detection:
- Auto-detects if backend is running
- Can enable mock mode for development
- Provides clear feedback about configuration

### 3. Mock Mode for Development
Added intelligent mock responses that simulate real AI Coach behavior:
- Contextual responses based on user questions
- Appropriate suggested actions
- Supports all sports
- Only active in DEBUG mode when needed

### 4. Better Error Handling
- Catches specific error types (404, timeout, connection failure)
- Provides actionable error messages
- Only uses fallback after genuine connection failures
- Resets failure counter to prevent stuck states

## How to Fix "Reconnecting" Issue

### Step 1: Check What's Actually Failing

Run the app and open the Xcode Console (`Cmd+Shift+C`). Look for log messages:

#### If you see:
```
❌ [APIClient] APIError in sendCoachMessage: notFound
❌ [APIClient] Endpoint /ai/coach/message not found on backend!
```
**Problem:** Backend doesn't have the endpoint implemented yet.

#### If you see:
```
❌ [APIClient] APIError in sendCoachMessage: cannotConnectToHost
```
**Problem:** Backend server is not running.

#### If you see:
```
❌ [APIClient] APIError in sendCoachMessage: timeout
```
**Problem:** Backend is too slow or hung.

### Step 2: Start Your Backend Server

Make sure your FastAPI backend is running:

```bash
cd backend
uvicorn main:app --reload --port 8000
```

Verify it's working by visiting: http://localhost:8000/docs

### Step 3: Verify the AI Coach Endpoint Exists

Check your backend code has this endpoint:

```python
@app.post("/ai/coach/message")
async def send_coach_message(
    request: CoachMessageRequest,
    current_user: User = Depends(get_current_user)
):
    # Your AI Coach logic here
    return {
        "response": "AI coach response...",
        "suggested_actions": ["Action 1", "Action 2"],
        "tone": "supportive",
        "follow_up_questions": [],
        "timestamp": datetime.now().isoformat()
    }
```

### Step 4: Test the Connection

The app will automatically check backend health on launch. Watch the console:

```
🔍 [Debug] Checking backend connection to http://localhost:8000...
✅ [Debug] Backend responded with status: 200
✅ [Debug] Backend available - using real API
```

### Step 5: Enable Mock Mode (Optional)

If you need to test the UI without a backend:

1. Open `DebugSettings.swift`
2. The app will auto-enable mock mode if backend is unreachable
3. Or manually enable it:
```swift
DebugSettings.useAICoachMockMode = true
```

## Backend Implementation Guide

If you don't have the AI Coach endpoint yet, here's a minimal implementation:

```python
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime

router = APIRouter(prefix="/ai/coach", tags=["AI Coach"])

class CoachMessageRequest(BaseModel):
    message: str
    sport: str
    context: Optional[Dict[str, Any]] = None

class CoachMessageResponse(BaseModel):
    response: str
    suggested_actions: List[str] = []
    tone: str = "supportive"
    follow_up_questions: List[str] = []
    timestamp: str

@router.post("/message")
async def send_coach_message(
    request: CoachMessageRequest,
    current_user: User = Depends(get_current_user_premium)  # Premium only
):
    # Basic example - replace with your AI logic
    response_text = f"Great question about {request.sport}! "
    
    if "workout" in request.message.lower():
        response_text += "I recommend starting with a warm-up, then focusing on fundamental drills. What's your current skill level?"
        actions = ["View Recommended Drills", "Start Quick Workout"]
    elif "improve" in request.message.lower():
        response_text += "To improve, consistent practice is key. Let's identify your weak points and create a focused training plan."
        actions = ["Take Skill Assessment", "Create Training Plan"]
    else:
        response_text += "I'm here to help with your training! What specific aspect would you like to work on?"
        actions = ["View Training Options", "Ask About Drills"]
    
    return CoachMessageResponse(
        response=response_text,
        suggested_actions=actions,
        tone="supportive",
        follow_up_questions=["How much time do you have?", "What's your goal?"],
        timestamp=datetime.now().isoformat()
    )
```

## Testing Checklist

- [ ] Backend server is running on http://localhost:8000
- [ ] `/health` endpoint responds (check at http://localhost:8000/health)
- [ ] `/ai/coach/message` endpoint exists (check API docs)
- [ ] Premium subscription is active (check StoreManager.shared.isPremium)
- [ ] Console shows successful connection logs
- [ ] AI Coach responds with real messages (not fallback text)
- [ ] Suggested action buttons appear
- [ ] Conversation continues without getting stuck

## Common Issues

### Issue: "While I work on reconnecting..."
**Cause:** Backend endpoint failing or not found
**Fix:** Check console logs, verify backend is running, implement endpoint

### Issue: Coach responds but messages are generic
**Cause:** Backend returning mock/placeholder responses
**Fix:** Implement real AI logic or LLM integration in backend

### Issue: "No internet connection"
**Cause:** APIClient.baseURL pointing to wrong address
**Fix:** Verify `APIConfig.baseURL` matches your backend (default: http://localhost:8000)

### Issue: Mock mode stuck on
**Cause:** UserDefaults retaining the setting
**Fix:** 
```swift
DebugSettings.useAICoachMockMode = false
```

## Production Deployment

Before deploying to production:

1. **Update base URL** in `APIConfig.swift`:
```swift
static let baseURL = "https://your-production-api.com"
```

2. **Disable mock mode** (automatic in Release builds)

3. **Test Premium subscription check** works correctly

4. **Verify backend has proper error handling** and rate limiting

5. **Monitor backend response times** (should be < 2 seconds)

## Next Steps

Once basic connectivity is working:

1. **Implement real AI logic** - Integrate with OpenAI, Anthropic, or your LLM
2. **Add conversation history** - Store and retrieve past conversations
3. **Enhance context** - Use training data, wearables, goals
4. **Add streaming responses** - Show AI typing in real-time
5. **Implement rate limiting** - Prevent abuse
6. **Add analytics** - Track usage and quality metrics

## Support

If you're still having connection issues:

1. Check Xcode Console for detailed error logs
2. Verify backend is running and accessible
3. Test endpoint directly with curl or Postman:
```bash
curl -X POST http://localhost:8000/ai/coach/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{"message": "test", "sport": "basketball"}'
```
4. Enable mock mode to test UI independently
5. Check firewall/network settings

The AI Coach should now connect reliably and provide real responses when the backend is properly implemented and running.
