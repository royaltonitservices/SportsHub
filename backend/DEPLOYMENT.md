# SportsHub Backend Deployment Guide

## Complete Backend Implementation Status

### ✅ Created Files:
1. `requirements.txt` - All Python dependencies
2. `config.py` - Configuration management
3. `database.py` - Database connection and session management
4. `models.py` - Complete SQLAlchemy models for all features
5. `main.py` - FastAPI application entry point
6. `.env.example` - Environment configuration template
7. `README.md` - Project documentation

### 📋 Database Models Implemented:

**Core Models:**
- `User` - User accounts with role-based access
- `SportProfile` - Sport-specific stats (multi-sport system)
- `Friendship` - Friend graph with request/accept flow
- `Message` - Direct messaging (friends-only)
- `Challenge` - Competition system
- `Post` - Community posts with sport tags
- `Clip` - Video content with sport tags
- `ModerationFlag` - Content reports
- `AdminAction` - Admin audit trail

### 🚀 Quick Start

#### 1. Install PostgreSQL

**macOS:**
```bash
brew install postgresql@15
brew services start postgresql@15
```

**Linux:**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
```

**Windows:**
Download from https://www.postgresql.org/download/windows/

#### 2. Create Database

```bash
# Login to PostgreSQL
psql postgres

# Create database and user
CREATE DATABASE sportshub;
CREATE USER sportshub_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE sportshub TO sportshub_user;
\q
```

#### 3. Setup Backend

```bash
cd backend

# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # macOS/Linux
# OR
venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt

# Create .env file
cp .env.example .env

# Edit .env with your database credentials
nano .env  # or use any text editor
```

#### 4. Configure Environment

Edit `.env`:

```env
DATABASE_URL=postgresql://sportshub_user:your_password@localhost:5432/sportshub
SECRET_KEY=generate-a-secure-random-key-here
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
ADMIN_EMAIL=aarushkhanna11@gmail.com
ADMIN_PASSWORD=$81Admin
API_HOST=0.0.0.0
API_PORT=8000
DEBUG=True
```

**Generate SECRET_KEY:**
```python
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

#### 5. Initialize Database

```bash
# Run Python to create tables
python -c "from database import init_db; init_db()"
```

#### 6. Start Server

```bash
python main.py
```

Or using uvicorn directly:
```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### 📡 API Endpoints

Once running, access:
- **API**: http://localhost:8000
- **Interactive Docs**: http://localhost:8000/docs
- **Alternative Docs**: http://localhost:8000/redoc

### 🔐 Admin Account

The admin account will be created on first run with:
- **Email**: aarushkhanna11@gmail.com
- **Password**: $81Admin

### 📱 iOS App Configuration

Update iOS app to point to backend:

1. If running locally:
   ```swift
   private let baseURL = "http://localhost:8000"
   ```

2. If deployed:
   ```swift
   private let baseURL = "https://api.sportshub.app"
   ```

### 🔧 Next Steps to Complete Backend

The foundation is built. To complete the backend, you need to create router files:

**Required Routers:**
1. `routers/auth.py` - Authentication (login, signup, token)
2. `routers/users.py` - User management
3. `routers/sports.py` - Sport profiles and switching
4. `routers/friends.py` - Friend requests and management
5. `routers/messages.py` - Direct messaging
6. `routers/challenges.py` - Challenge system
7. `routers/posts.py` - Posts feed
8. `routers/clips.py` - Clips feed
9. `routers/admin.py` - Admin user management
10. `routers/moderation.py` - Content moderation

**Supporting Files:**
- `auth.py` - JWT token creation and validation
- `dependencies.py` - FastAPI dependencies (get_current_user, etc.)
- `schemas.py` - Pydantic schemas for request/response
- `services/ai_moderation.py` - Content safety checks

### 🏗️ Production Deployment

**Recommended Stack:**
- **Hosting**: Railway.app, Render.com, or DigitalOcean
- **Database**: Managed PostgreSQL (same platforms)
- **Environment**: Use production .env values
- **HTTPS**: Automatically provided by hosting platforms

**Railway.app (Easiest):**
```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Initialize project
railway init

# Link database
railway add --database postgresql

# Deploy
railway up
```

### 📊 Database Migrations (Optional)

For production, use Alembic:

```bash
# Initialize Alembic
alembic init alembic

# Create migration
alembic revision --autogenerate -m "Initial migration"

# Apply migration
alembic upgrade head
```

### 🧪 Testing

Create `test_api.py`:

```python
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert "SportsHub API" in response.json()["message"]

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
```

Run tests:
```bash
pytest
```

### 🔒 Security Checklist

Before production:
- [ ] Change `SECRET_KEY` to secure random value
- [ ] Set `DEBUG=False`
- [ ] Configure CORS for specific origins only
- [ ] Use HTTPS
- [ ] Set up rate limiting
- [ ] Enable database backups
- [ ] Set up monitoring (Sentry, etc.)
- [ ] Hash admin password properly

### 📞 Support

For issues or questions:
1. Check logs: `tail -f app.log`
2. Verify database connection
3. Check environment variables
4. Review API docs at `/docs`

---

**Current Status:** ✅ Backend foundation ready
**Next:** Implement router endpoints and connect iOS app
