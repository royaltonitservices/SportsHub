#!/bin/bash

# SportsHub Backend Quick Setup Script

echo "🏀 SportsHub Backend Setup"
echo "=========================="
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 not found. Please install Python 3.9+"
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"

# Check PostgreSQL
if ! command -v psql &> /dev/null; then
    echo "⚠️  PostgreSQL not found. Please install PostgreSQL 15+"
    echo "   macOS: brew install postgresql@15"
    echo "   Linux: sudo apt install postgresql"
    exit 1
fi

echo "✅ PostgreSQL found"

# Create virtual environment
echo ""
echo "📦 Creating virtual environment..."
python3 -m venv venv

# Activate virtual environment
echo "📦 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📦 Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Check if .env exists
if [ ! -f .env ]; then
    echo ""
    echo "⚙️  Creating .env file from template..."
    cp .env.example .env
    echo "⚠️  Please edit .env with your configuration:"
    echo "   - Set DATABASE_URL"
    echo "   - Generate SECRET_KEY: python3 -c 'import secrets; print(secrets.token_urlsafe(32))'"
    echo ""
    echo "Then run this command to initialize the database:"
    echo "   source venv/bin/activate && python3 -c 'from database import init_db; init_db()'"
    echo ""
    echo "And start the server with:"
    echo "   source venv/bin/activate && python3 main.py"
else
    echo "✅ .env file exists"

    # Ask if user wants to initialize database
    echo ""
    read -p "Initialize database now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗄️  Initializing database..."
        python3 -c "from database import init_db; init_db()"
        echo "✅ Database initialized"

        # Ask if user wants to start server
        echo ""
        read -p "Start server now? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "🚀 Starting server..."
            echo "   API: http://localhost:8000"
            echo "   Docs: http://localhost:8000/docs"
            echo ""
            python3 main.py
        else
            echo ""
            echo "To start the server later, run:"
            echo "   source venv/bin/activate && python3 main.py"
        fi
    else
        echo ""
        echo "To initialize database later, run:"
        echo "   source venv/bin/activate && python3 -c 'from database import init_db; init_db()'"
    fi
fi

echo ""
echo "✅ Setup complete!"
