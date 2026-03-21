# SportsHub - Quick Start Guide

Get SportsHub running in 5 minutes.

## ⚡ Fastest Setup (Docker)

### 1. Start Backend
```bash
cd SportsHub
docker-compose up -d
```

This starts:
- PostgreSQL database (port 5432)
- Backend API (port 8000)
- Redis cache (port 6379)

### 2. Initialize Database
```bash
docker-compose exec backend python -c "from database import Base, engine; Base.metadata.create_all(bind=engine)"
```

### 3. Verify Backend
```bash
# Check API is running
curl http://localhost:8000/health

# Open API docs
open http://localhost:8000/docs
```

### 4. Start iOS App
```bash
# Open Xcode project
open SportsHub/SportsHub.xcodeproj

# Update API URL in APIClient.swift (if needed)
# Line 14: static let baseURL = "http://localhost:8000"

# Build and Run (Cmd+R)
```

## ✅ You're Done!

The app should now be running on the simulator, connected to your local backend.

## 🧪 Test It Out

### 1. Create an Account
- Open the app
- Tap "Create Account"
- Fill in details
- Sign up

### 2. Create Sport Profile
- Navigate to "Play" tab
- Select a sport (Basketball/Football/Soccer/Tennis)
- Profile auto-created on first view

### 3. Find a Match
- Tap "Find Match"
- Browse available opponents
- Tap + to challenge someone

### 4. View Leaderboard
- Tap "View All" in Leaderboard section
- See top 100 rankings
- Your rank appears when you have matches

## 🔐 Admin Access

To access admin features:

**Email**: `aarushkhanna11@gmail.com`
**Password**: `$81Admin`

## 📱 Main Features to Try

### Play Tab
- Create sport profiles
- Find matches
- View leaderboard
- Accept challenges

### Posts Tab
- Create posts
- Like/comment on posts
- View social feed

### Profile Tab
- View your stats
- Manage settings
- See earned badges (after matches)

### Home Tab
- Activity feed
- Friend updates
- Recent matches

## 🛠️ Troubleshooting

### Backend won't start
```bash
# Check if ports are in use
lsof -i :8000  # Backend port
lsof -i :5432  # PostgreSQL port

# View logs
docker-compose logs backend
```

### iOS can't connect to backend
1. Check backend is running: `curl http://localhost:8000/health`
2. Verify API URL in `APIClient.swift`
3. If using real device, use computer's IP instead of localhost

### Database issues
```bash
# Reset database
docker-compose down -v
docker-compose up -d
# Re-run database initialization
```

## 📊 Sample Data

To add mock data for testing:

```bash
# SSH into backend container
docker-compose exec backend bash

# Run Python shell
python

# Create mock users (example)
from database import SessionLocal
from models import User
from passlib.context import CryptContext

db = SessionLocal()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

user = User(
    email="test@example.com",
    username="testuser",
    full_name="Test User",
    hashed_password=pwd_context.hash("password123")
)
db.add(user)
db.commit()
```

## 🎯 Next Steps

Once you're comfortable with the basics:

1. **Read [API_GUIDE.md](API_GUIDE.md)** - Complete API reference
2. **Read [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** - Deploy to production
3. **Read [PROJECT_COMPLETE.md](PROJECT_COMPLETE.md)** - Full feature list

## 🚀 Development Workflow

### Backend Development
```bash
# View logs
docker-compose logs -f backend

# Restart after code changes
docker-compose restart backend

# Access database
docker-compose exec db psql -U postgres -d sportshub
```

### iOS Development
```bash
# Build
Cmd+B

# Run
Cmd+R

# Clean build
Cmd+Shift+K
```

## 📖 API Examples

### Login
```bash
curl -X POST http://localhost:8000/auth/login \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=aarushkhanna11@gmail.com&password=$81Admin"
```

### Get Sport Profile
```bash
TOKEN="<your-jwt-token>"
curl http://localhost:8000/sports/profile/basketball \
  -H "Authorization: Bearer $TOKEN"
```

### Find Opponents
```bash
curl -X POST http://localhost:8000/matchmaking/find-opponents \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"sport": "basketball", "match_type": "ranked"}'
```

### Get Leaderboard
```bash
curl http://localhost:8000/sports/leaderboard/basketball?limit=10 \
  -H "Authorization: Bearer $TOKEN"
```

## 🔧 Configuration

### Environment Variables (.env)
```bash
DATABASE_URL=postgresql://postgres:postgres@db:5432/sportshub
SECRET_KEY=your-secret-key-change-in-production
ADMIN_EMAIL=aarushkhanna11@gmail.com
ADMIN_PASSWORD_HASH=<bcrypt-hash>
```

### iOS API Configuration
```swift
// APIClient.swift
struct APIConfig {
    static let baseURL = "http://localhost:8000"  // Development
    // static let baseURL = "https://api.sportshub.com"  // Production
}
```

## 💡 Tips

1. **Keep backend running** - Leave `docker-compose up -d` running during development
2. **Check logs often** - `docker-compose logs -f backend` helps debug issues
3. **Use API docs** - http://localhost:8000/docs is interactive and helpful
4. **Test admin features** - Use admin account to see moderation tools
5. **Try all sports** - Each sport has separate profiles and leaderboards

## 📞 Need Help?

- **API not responding**: Check `docker-compose ps`
- **Database errors**: Check `docker-compose logs db`
- **iOS build fails**: Clean build folder (Cmd+Shift+K)
- **Can't login**: Verify backend is running and credentials are correct

## 🎉 You're Ready!

Your SportsHub instance is now running. Start exploring the features and building your competitive sports community!

---

**Happy Coding!** 🏀⚽🎾🏈
