-- Add CoachContext table for persistent coaching memory (SQLite compatible)
-- PRIORITY FIX 2: This enables AI Coach to remember athletes

CREATE TABLE IF NOT EXISTS coach_context (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    sport TEXT NOT NULL,
    
    -- Weak points and goals (JSON arrays as TEXT)
    weak_points TEXT DEFAULT '[]',
    goals TEXT DEFAULT '[]',
    
    -- Training preferences
    preferred_training_duration INTEGER,
    preferred_training_time TEXT,
    training_frequency TEXT,
    
    -- Recent recommendations to avoid repetition
    recent_recommendations TEXT DEFAULT '[]',
    
    -- Context from conversations
    mentioned_skills TEXT DEFAULT '[]',
    training_focus TEXT,
    notes TEXT,
    
    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    last_interaction TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_coach_context_user_sport ON coach_context(user_id, sport);
