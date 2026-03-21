# SportsHub Backend API

Production-ready FastAPI backend for SportsHub iOS application.

## Features

- **Authentication**: JWT-based auth with role-based access control
- **Multi-Sport System**: Separate profiles/stats per sport
- **Friend System**: Friend requests and friends-only messaging
- **Content Moderation**: AI-powered safety checks
- **Admin Panel**: Complete user and content management
- **PostgreSQL**: Production database with full schema

## Setup

### 1. Install Dependencies

```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Database Setup

Install PostgreSQL and create database:

```bash
createdb sportshub
```

### 3. Environment Configuration

Copy `.env.example` to `.env` and update values:

```bash
cp .env.example .env
```

Edit `.env` with your configuration.

### 4. Initialize Database

```bash
python3 -c "from database import init_db; init_db()"
```

This will create all tables and set up the admin account.

### 5. Start Server

```bash
uvicorn main:app --reload
```

API will be available at: http://localhost:8000

## API Documentation

Interactive API docs: http://localhost:8000/docs
Alternative docs: http://localhost:8000/redoc

## Project Structure

```
backend/
├── main.py                 # FastAPI app entry point
├── config.py              # Configuration management
├── database.py            # Database connection
├── models.py              # SQLAlchemy models
├── schemas.py             # Pydantic schemas
├── auth.py                # Authentication logic
├── dependencies.py        # FastAPI dependencies
└── routers/
    ├── auth.py           # Auth endpoints ✅
    ├── users.py          # User management ✅
    ├── sports.py         # Multi-sport system ✅
    ├── friends.py        # Friend system ✅
    ├── messages.py       # DM system ✅
    ├── challenges.py     # Competition ✅
    ├── posts.py          # Posts feed ✅
    ├── clips.py          # Video clips ✅
    ├── admin.py          # Admin endpoints ✅
    └── moderation.py     # Content moderation ✅
```

## Admin Access

Email: `aarushkhanna11@gmail.com`
Password: `$81Admin`

## Testing

```bash
pytest
```
