# AI Coach Backend Endpoint - Quick Implementation Guide

If you don't have a backend yet or need to implement the AI Coach endpoint, here's how to do it:

## Option 1: Minimal Working Backend (No AI - Just Responses)

Add this to your FastAPI backend (e.g., in `routers/ai_coach.py`):

```python
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime
from app.core.auth import get_current_user, check_premium_subscription
from app.models.user import User

router = APIRouter(prefix="/ai/coach", tags=["AI Coach"])

class CoachContext(BaseModel):
    weak_points: Optional[List[str]] = None
    goals: Optional[List[str]] = None
    available_time: Optional[int] = None
    readiness_level: Optional[str] = None
    recent_training: Optional[str] = None
    wearable_data: Optional[Dict[str, Any]] = None

class CoachMessageRequest(BaseModel):
    message: str
    sport: str
    context: Optional[CoachContext] = None

class CoachMessageResponse(BaseModel):
    response: str
    suggested_actions: List[str] = []
    tone: str = "supportive"
    follow_up_questions: List[str] = []
    timestamp: str

@router.post("/message", response_model=CoachMessageResponse)
async def send_coach_message(
    request: CoachMessageRequest,
    current_user: User = Depends(get_current_user)
):
    """
    AI Coach conversation endpoint
    Requires Premium subscription
    """
    
    # Check Premium subscription
    if not current_user.premium_subscription:
        raise HTTPException(
            status_code=403,
            detail="AI Coach is a Premium feature. Please upgrade to access."
        )
    
    # Generate contextual response based on message
    message_lower = request.message.lower()
    sport = request.sport
    
    # Build response based on content
    if "workout" in message_lower or "drill" in message_lower or "train" in message_lower:
        response = generate_workout_response(sport, request.context)
        actions = ["Browse Drills", "View Training Plans"]
        
    elif "improve" in message_lower or "better" in message_lower:
        response = generate_improvement_response(sport, request.context)
        actions = ["See Recommended Drills", "Track Progress"]
        
    elif "weak" in message_lower or "struggle" in message_lower:
        response = generate_weakness_response(sport, request.context)
        actions = ["Find Specific Drills", "Create Training Plan"]
        
    elif "ready" in message_lower or "prepared" in message_lower:
        response = generate_readiness_response(sport, request.context)
        actions = ["View Daily Readiness", "Log Training Session"]
        
    else:
        response = generate_general_response(sport, request.context)
        actions = ["Browse Drills", "View Training Plans"]
    
    return CoachMessageResponse(
        response=response,
        suggested_actions=actions,
        tone="supportive",
        follow_up_questions=get_follow_up_questions(sport),
        timestamp=datetime.utcnow().isoformat()
    )

# Response generators
def generate_workout_response(sport: str, context: Optional[CoachContext]) -> str:
    time_available = context.available_time if context and context.available_time else 30
    
    return f"""Great! Let's put together a {sport} workout for you.

For a {time_available}-minute session, I recommend:

**Warm-up (5 min)**
• Dynamic stretching
• Light cardio to increase heart rate

**Skill Work (15 min)**
• Focus on fundamental techniques
• Progressive difficulty drills

**Practice (8 min)**
• Game-situation scenarios
• Apply what you practiced

**Cool-down (2 min)**
• Static stretching
• Recovery

What skill would you like to focus on today?"""

def generate_improvement_response(sport: str, context: Optional[CoachContext]) -> str:
    weak_points = ""
    if context and context.weak_points:
        weak_points = f"I see you've mentioned struggles with {', '.join(context.weak_points[:2])}. "
    
    return f"""{weak_points}The key to improving in {sport} is consistent, focused practice.

**Here's my approach:**

1. **Identify weak points** - Understand what needs work
2. **Break it down** - Focus on one skill at a time
3. **Practice deliberately** - Quality over quantity
4. **Track progress** - See your improvement over time
5. **Stay consistent** - Even 15 minutes daily makes a difference

Which specific skill feels weakest to you right now?"""

def generate_weakness_response(sport: str, context: Optional[CoachContext]) -> str:
    return f"""I appreciate you being honest about your weak points. That self-awareness is the first step to improvement!

**For {sport}, here's my recommendation:**

• **Daily focused drills** (10-15 min)
  Work specifically on your weak area

• **Video analysis**
  Record yourself and compare to proper form

• **Progressive challenge**
  Start easy, gradually increase difficulty

• **Regular assessment**
  Track improvements weekly

The Train section has drills filtered by skill type. Start with fundamentals and build up. Would you like me to suggest specific drills for your weak point?"""

def generate_readiness_response(sport: str, context: Optional[CoachContext]) -> str:
    readiness = context.readiness_level if context and context.readiness_level else "good"
    
    return f"""Your readiness level today appears {readiness}. Here's what I recommend:

**Pre-Training Checklist:**
✓ Proper warm-up (5-10 min)
✓ Hydration (drink water now)
✓ Mental prep (visualize success)
✓ Review goals for this session

**Focus Areas:**
• Technical skills (when fresh)
• Conditioning (later in session)
• Cool-down and recovery

Ready to train? Let me know what you want to work on and I'll guide you through it!"""

def generate_general_response(sport: str, context: Optional[CoachContext]) -> str:
    goals = ""
    if context and context.goals:
        goals = f"I see you're working toward: {context.goals[0]}. "
    
    return f"""Hey! I'm your {sport} coach, and I'm here to help you reach your goals.

{goals}I can help you with:

• **Custom workout plans** - Tailored to your level and goals
• **Skill development** - Specific drills for improvement
• **Training advice** - Form tips and technique guidance
• **Progress tracking** - Monitor your growth over time
• **Motivation** - Keep you accountable and inspired

What would you like to work on today?"""

def get_follow_up_questions(sport: str) -> List[str]:
    return [
        "How much time do you have to train?",
        f"What's your current {sport} skill level?",
        "What's your main goal right now?"
    ]

@router.get("/checkin", response_model=Dict[str, Any])
async def get_proactive_checkin(
    sport: str,
    current_user: User = Depends(get_current_user)
):
    """Proactive coach check-in message"""
    
    if not current_user.premium_subscription:
        return {"has_message": False, "message": None}
    
    # Simple proactive messages
    messages = [
        "How's your training been going this week?",
        "Ready to work on your skills today?",
        "What would you like to improve most?",
        f"How are you feeling about your {sport} performance?",
        "What's your biggest training goal right now?"
    ]
    
    import random
    return {
        "has_message": True,
        "message": random.choice(messages)
    }

@router.delete("/history")
async def clear_coach_conversation(
    sport: str,
    current_user: User = Depends(get_current_user)
):
    """Clear conversation history"""
    # Implement if storing conversation history
    return {"message": "Conversation cleared"}
```

## Option 2: With OpenAI Integration

If you want real AI responses, add OpenAI:

```python
import openai
from app.core.config import settings

openai.api_key = settings.OPENAI_API_KEY

async def generate_ai_response(message: str, sport: str, context: Optional[CoachContext]) -> str:
    """Generate AI response using OpenAI"""
    
    # Build context prompt
    system_prompt = f"""You are an expert {sport} coach. You're supportive, knowledgeable, 
    and help athletes improve through specific, actionable advice. Keep responses concise 
    (2-3 paragraphs max). Focus on technique, drills, and motivation."""
    
    # Add user context if available
    context_info = ""
    if context:
        if context.weak_points:
            context_info += f"Weak points: {', '.join(context.weak_points)}. "
        if context.goals:
            context_info += f"Goals: {', '.join(context.goals)}. "
        if context.recent_training:
            context_info += f"Recent training: {context.recent_training}. "
    
    user_prompt = f"{context_info}\n\nUser question: {message}"
    
    try:
        response = await openai.ChatCompletion.acreate(
            model="gpt-4",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            max_tokens=500,
            temperature=0.7
        )
        
        return response.choices[0].message.content
        
    except Exception as e:
        print(f"OpenAI error: {e}")
        # Fallback to rule-based response
        return generate_general_response(sport, context)
```

Then update the main endpoint:

```python
@router.post("/message", response_model=CoachMessageResponse)
async def send_coach_message(
    request: CoachMessageRequest,
    current_user: User = Depends(get_current_user)
):
    if not current_user.premium_subscription:
        raise HTTPException(status_code=403, detail="Premium required")
    
    # Use AI response
    ai_response = await generate_ai_response(
        request.message,
        request.sport,
        request.context
    )
    
    # Generate contextual actions
    actions = generate_action_suggestions(request.message)
    
    return CoachMessageResponse(
        response=ai_response,
        suggested_actions=actions,
        tone="supportive",
        follow_up_questions=get_follow_up_questions(request.sport),
        timestamp=datetime.utcnow().isoformat()
    )

def generate_action_suggestions(message: str) -> List[str]:
    """Generate suggested actions based on message"""
    message_lower = message.lower()
    
    if "drill" in message_lower or "practice" in message_lower:
        return ["Browse Drills", "Start Quick Workout"]
    elif "weak" in message_lower or "improve" in message_lower:
        return ["See Recommended Drills", "Track Progress"]
    elif "plan" in message_lower or "program" in message_lower:
        return ["View Training Plans", "Create Custom Plan"]
    else:
        return ["Browse Drills", "View Training Plans"]
```

## Adding to Your Main App

In your `main.py`:

```python
from routers import ai_coach

app = FastAPI()

# Include AI Coach router
app.include_router(ai_coach.router)
```

## Testing the Endpoint

Test with curl:

```bash
curl -X POST http://localhost:8000/ai/coach/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "message": "What should I work on today?",
    "sport": "basketball",
    "context": {
      "available_time": 30,
      "weak_points": ["shooting"],
      "goals": ["improve accuracy"]
    }
  }'
```

Expected response:
```json
{
  "response": "Let's focus on your shooting...",
  "suggested_actions": ["Browse Drills", "View Training Plans"],
  "tone": "supportive",
  "follow_up_questions": ["How much time do you have to train?"],
  "timestamp": "2026-04-07T10:30:00"
}
```

## Environment Variables

Add to your `.env`:

```env
# Optional - for OpenAI integration
OPENAI_API_KEY=sk-...
```

## Dependencies

Add to `requirements.txt`:

```
openai>=1.0.0  # Only if using OpenAI
```

Now your backend should be ready! The iOS app will connect and receive real responses instead of fallback messages.
