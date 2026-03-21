# SportsHub Deployment Guide

Complete guide for deploying SportsHub backend and iOS app.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Local Development Setup](#local-development-setup)
3. [Docker Deployment](#docker-deployment)
4. [Production Deployment](#production-deployment)
5. [iOS App Deployment](#ios-app-deployment)
6. [Environment Variables](#environment-variables)
7. [Database Migrations](#database-migrations)
8. [Monitoring & Logs](#monitoring--logs)

---

## Prerequisites

### Backend
- Docker & Docker Compose (recommended)
- OR Python 3.11+
- PostgreSQL 15+
- Redis 7+ (optional, for caching)

### iOS App
- macOS with Xcode 15+
- Apple Developer Account (for App Store deployment)
- iOS 17.0+ target devices

---

## Local Development Setup

### Backend (Without Docker)

1. **Create Virtual Environment**
```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. **Install Dependencies**
```bash
pip install -r requirements.txt
```

3. **Setup Environment**
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. **Setup Database**
```bash
# Make sure PostgreSQL is running
createdb sportshub

# Run setup script
chmod +x setup.sh
./setup.sh
```

5. **Run Server**
```bash
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Server will be available at: http://localhost:8000
API docs: http://localhost:8000/docs

### iOS App

1. **Open Project**
```bash
cd SportsHub
open SportsHub.xcodeproj
```

2. **Configure API Base URL**
- Open `APIClient.swift`
- Update `APIConfig.baseURL` to your backend URL:
  - Local: `http://localhost:8000`
  - Production: `https://api.sportshub.com`

3. **Build & Run**
- Select target device/simulator
- Press Cmd+R to build and run

---

## Docker Deployment

### Quick Start

1. **Clone Repository**
```bash
git clone <repository-url>
cd SportsHub
```

2. **Configure Environment**
```bash
cp backend/.env.example backend/.env
# Edit backend/.env with your settings
```

3. **Start All Services**
```bash
docker-compose up -d
```

This starts:
- PostgreSQL database (port 5432)
- Backend API (port 8000)
- Redis cache (port 6379)

4. **Initialize Database**
```bash
docker-compose exec backend python -c "from database import Base, engine; Base.metadata.create_all(bind=engine)"
```

5. **Check Status**
```bash
docker-compose ps
docker-compose logs backend
```

### Docker Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f backend

# Restart backend
docker-compose restart backend

# Access backend shell
docker-compose exec backend bash

# Access database
docker-compose exec db psql -U postgres -d sportshub

# Stop and remove all data
docker-compose down -v
```

---

## Production Deployment

### Option 1: Cloud Platform (Recommended)

#### Render.com Deployment

1. **Create Account** at render.com

2. **Create PostgreSQL Database**
- New → PostgreSQL
- Name: `sportshub-db`
- Plan: Starter ($7/month)
- Note the Internal Database URL

3. **Create Web Service**
- New → Web Service
- Connect GitHub repository
- Settings:
  - Name: `sportshub-api`
  - Environment: Python 3
  - Build Command: `pip install -r backend/requirements.txt`
  - Start Command: `uvicorn backend.main:app --host 0.0.0.0 --port $PORT`
  - Plan: Starter ($7/month)

4. **Set Environment Variables**
```
DATABASE_URL=<internal-database-url>
SECRET_KEY=<generate-random-secret>
ADMIN_EMAIL=aarushkhanna11@gmail.com
ADMIN_PASSWORD_HASH=<bcrypt-hash-of-admin-password>
```

5. **Deploy**
- Click "Create Web Service"
- Wait for deployment to complete
- Note the service URL

#### Digital Ocean App Platform

1. **Create App**
```bash
doctl apps create --spec app.yaml
```

2. **app.yaml Example**
```yaml
name: sportshub
services:
  - name: backend
    source:
      repo_url: <your-repo>
      branch: main
    build_command: pip install -r backend/requirements.txt
    run_command: uvicorn backend.main:app --host 0.0.0.0 --port 8080
    environment_slug: python
    instance_count: 1
    instance_size_slug: basic-xs
    http_port: 8080
    routes:
      - path: /
databases:
  - name: db
    engine: PG
    version: "15"
```

### Option 2: VPS Deployment

#### AWS EC2 / DigitalOcean Droplet

1. **Setup Server**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

2. **Clone & Deploy**
```bash
git clone <repository-url>
cd SportsHub
cp backend/.env.example backend/.env
# Edit .env with production values

docker-compose up -d
```

3. **Setup Nginx Reverse Proxy**
```nginx
server {
    listen 80;
    server_name api.sportshub.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

4. **Setup SSL with Let's Encrypt**
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d api.sportshub.com
```

---

## iOS App Deployment

### TestFlight (Beta Testing)

1. **Archive Build**
- Xcode → Product → Archive
- Wait for archive to complete

2. **Upload to App Store Connect**
- Window → Organizer
- Select archive → Distribute App
- Choose "App Store Connect"
- Upload

3. **Configure TestFlight**
- App Store Connect → My Apps → SportsHub
- TestFlight → Internal Testing
- Add testers
- Submit for review (if needed)

### App Store Release

1. **Prepare App Listing**
- App Store Connect → My Apps → SportsHub
- Fill in:
  - App Description
  - Keywords
  - Screenshots (6.5", 5.5" displays)
  - App Preview videos (optional)
  - Privacy Policy URL

2. **Submit for Review**
- Select build from TestFlight
- Add App Store version information
- Submit for review
- Wait 1-3 days for approval

---

## Environment Variables

### Backend (.env)

```bash
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/sportshub

# Security
SECRET_KEY=your-secret-key-min-32-characters
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# Admin Account
ADMIN_EMAIL=aarushkhanna11@gmail.com
ADMIN_PASSWORD_HASH=<bcrypt-hash>

# Optional: External Services
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=
# S3_BUCKET_NAME=
# REDIS_URL=redis://localhost:6379
```

### Generate Secret Key
```python
import secrets
print(secrets.token_urlsafe(32))
```

### Generate Password Hash
```python
from passlib.context import CryptContext
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
print(pwd_context.hash("$81Admin"))
```

---

## Database Migrations

### Initial Setup
```bash
# With Docker
docker-compose exec backend python -c "from database import Base, engine; Base.metadata.create_all(bind=engine)"

# Without Docker
python -c "from database import Base, engine; Base.metadata.create_all(bind=engine)"
```

### Backup Database
```bash
# Docker
docker-compose exec db pg_dump -U postgres sportshub > backup.sql

# Restore
docker-compose exec -T db psql -U postgres sportshub < backup.sql
```

### Future: Alembic Migrations
```bash
# Install alembic
pip install alembic

# Initialize
alembic init migrations

# Create migration
alembic revision --autogenerate -m "description"

# Apply migrations
alembic upgrade head
```

---

## Monitoring & Logs

### View Logs
```bash
# Backend logs
docker-compose logs -f backend

# Database logs
docker-compose logs -f db

# All services
docker-compose logs -f
```

### Health Checks
```bash
# API health
curl http://localhost:8000/health

# Database connection
docker-compose exec db pg_isready
```

### Performance Monitoring

Consider adding:
- **Sentry** - Error tracking
- **Datadog** - APM & monitoring
- **Prometheus + Grafana** - Metrics
- **ELK Stack** - Log aggregation

---

## Troubleshooting

### Backend won't start
```bash
# Check logs
docker-compose logs backend

# Common issues:
# 1. Database not ready - wait a few seconds
# 2. Port 8000 in use - change in docker-compose.yml
# 3. Environment variables missing - check .env
```

### Database connection errors
```bash
# Verify database is running
docker-compose ps db

# Check connection
docker-compose exec db psql -U postgres -d sportshub
```

### iOS app can't connect
1. Check API base URL in `APIClient.swift`
2. If using localhost, use device's IP address
3. Ensure backend is accessible from device
4. Check App Transport Security settings (allow HTTP for development)

---

## Security Checklist

- [ ] Change default SECRET_KEY
- [ ] Use strong admin password
- [ ] Enable HTTPS in production
- [ ] Set up firewall rules
- [ ] Enable database backups
- [ ] Implement rate limiting
- [ ] Add CORS restrictions
- [ ] Review security headers
- [ ] Keep dependencies updated
- [ ] Monitor for vulnerabilities

---

## Support

For issues or questions:
- Check API documentation: `/docs`
- Review backend logs
- Create GitHub issue

---

**Last Updated**: March 2026
