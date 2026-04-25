"""
SportsHub FastAPI Application
Main entry point for the backend API
"""
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from database import engine, Base, init_db
from config import get_settings
import models  # Import to register models
import models_premium  # Import premium models (subscriptions, smartwatch, tournaments)
import os

# Create FastAPI app
app = FastAPI(
    title="SportsHub API",
    description="Multi-sport competitive platform with social features",
    version="1.0.0"
)

settings = get_settings()

# CORS middleware
# In debug mode (local development) allow all origins.
# In production, restrict to specific origins via the ALLOWED_ORIGINS env var.
allowed_origins = ["*"] if settings.debug else os.environ.get("ALLOWED_ORIGINS", "").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount static file directories for CDN-served content
# Videos are stored at ./uploads/videos and served at /cdn/videos/
os.makedirs("./uploads/videos", exist_ok=True)
os.makedirs("./uploads/thumbnails", exist_ok=True)
os.makedirs("./uploads/evidence", exist_ok=True)
os.makedirs("./uploads/avatars", exist_ok=True)
os.makedirs("./uploads/highlights", exist_ok=True)
app.mount("/cdn/videos", StaticFiles(directory="./uploads/videos"), name="videos")
app.mount("/cdn/thumbnails", StaticFiles(directory="./uploads/thumbnails"), name="thumbnails")
app.mount("/cdn/avatars", StaticFiles(directory="./uploads/avatars"), name="avatars")
app.mount("/cdn/highlights", StaticFiles(directory="./uploads/highlights"), name="highlights")
app.mount("/cdn/evidence", StaticFiles(directory="./uploads/evidence"), name="evidence")

# Initialize database on startup
@app.on_event("startup")
async def startup_event():
    init_db()

@app.get("/")
async def root():
    return {
        "message": "SportsHub API",
        "version": "1.0.0",
        "docs": "/docs",
        "status": "operational"
    }

@app.get("/health")
async def health_check():
    return {"status": "healthy"}

# Import routers
from routers import (
    auth, users, sports, friends, messages, challenges, posts, clips,
    admin, moderation, matchmaking, disputes, blocking, comments, search, badges, activity, oauth, websocket,
    goals, smartwatch, tournaments, teams, ai_coach, placement, leaderboards, highlights, ai_conversation, evidence,
    tennis_courts, training, verification, onboarding_survey, skill_progression, telemetry
)

# Include routers
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(sports.router)
app.include_router(friends.router)
app.include_router(messages.router)
app.include_router(challenges.router)
app.include_router(posts.router)
app.include_router(clips.router)
app.include_router(admin.router)
app.include_router(moderation.router)
app.include_router(matchmaking.router)
app.include_router(disputes.router)
app.include_router(blocking.router)
app.include_router(comments.router)
app.include_router(search.router)
app.include_router(badges.router)
app.include_router(activity.router)
app.include_router(teams.router)
app.include_router(oauth.router)
app.include_router(websocket.router)
app.include_router(goals.router)
app.include_router(smartwatch.router)
app.include_router(tournaments.router)
app.include_router(ai_coach.router)
app.include_router(placement.router)
app.include_router(leaderboards.router)
app.include_router(highlights.router)
app.include_router(ai_conversation.router)
app.include_router(evidence.router)
app.include_router(tennis_courts.router)
app.include_router(training.router)
app.include_router(verification.router)
app.include_router(onboarding_survey.router)
app.include_router(skill_progression.router)
app.include_router(telemetry.router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug
    )
