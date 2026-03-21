"""
Configuration management for SportsHub API
"""
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql://user:password@localhost:5432/sportshub"

    # JWT
    secret_key: str = "your-secret-key-change-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 30

    # Admin
    admin_email: str = "aarushkhanna11@gmail.com"
    admin_password: str = "$81Admin"  # Will be hashed

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    debug: bool = True

    # OpenAI
    openai_api_key: str = "sk-proj-..."  # Set in .env
    openai_model: str = "gpt-4-turbo-preview"  # GPT-4.1 equivalent
    openai_max_tokens: int = 2000
    openai_temperature: float = 0.7

    class Config:
        env_file = ".env"


@lru_cache()
def get_settings() -> Settings:
    return Settings()
