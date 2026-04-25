"""
Configuration management for SportsHub API
"""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql://user:password@localhost:5432/sportshub"

    # JWT — REQUIRED in production. Set SECRET_KEY in your .env file.
    # Default is only acceptable for local development; never deploy with this value.
    secret_key: str = "dev-only-change-before-deploying"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30

    # Admin — set ADMIN_EMAIL and ADMIN_PASSWORD in .env; do not commit real credentials
    admin_email: str = "admin@example.com"
    admin_password: str = "change-me-in-env"  # Will be hashed on first use

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    debug: bool = True

    # OpenAI — set OPENAI_API_KEY in .env
    openai_api_key: str = ""  # Required: set in .env
    openai_model: str = "gpt-4-turbo-preview"  # GPT-4.1 equivalent
    openai_max_tokens: int = 2000
    openai_temperature: float = 0.7

    class Config:
        env_file = ".env"


@lru_cache()
def get_settings() -> Settings:
    return Settings()
