"""
Configuration management for SportsHub API
"""
from pydantic_settings import BaseSettings
from pydantic import Field
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

    # Deployment environment. Empty by default (fail-closed for the dev seed script).
    # Only "development" / "demo" permit synthetic seed data + the sample-data disclosure.
    # "production" (or unset/unknown) must never seed a fake community or show the banner.
    app_env: str = Field(default="", validation_alias="APP_ENV")

    # When true, the client shows a "Sample community data" disclosure on community
    # surfaces. Config-driven ONLY — never inferred from seed usernames/IDs. Must be
    # false in production. Defaults false; enable explicitly in dev/demo environments.
    sample_data_environment: bool = Field(default=False, validation_alias="SAMPLE_DATA_ENVIRONMENT")

    # Email verification policy for signup.
    #   "auto"     — dev/beta: create the account already verified & ACTIVE, no SMTP needed.
    #   "required" — production: account starts PENDING_VERIFICATION and must verify by code.
    # SAFETY: even if left "auto", bypass is IGNORED in a non-debug (production) build —
    # see routers/auth.py signup(), which requires debug=True for the bypass to take effect.
    email_verification_mode: str = Field(default="auto", validation_alias="EMAIL_VERIFICATION_MODE")

    # OpenAI — set OPENAI_API_KEY in .env
    openai_api_key: str = ""  # Required: set in .env

    # Centralized AI model selection (Section 9). Model IDs live ONLY here — do not
    # scatter them through the code. Override per-environment via the env vars below.
    #   default   — routine chat, questions, arithmetic, writing, planning, normal coaching
    #   escalation— bounded hard cases: semantic repair, high-severity safety, complex turns
    #   checkin   — cheap proactive check-in path
    ai_default_model: str = Field(default="gpt-5.4-mini", validation_alias="SPORTSHUB_AI_DEFAULT_MODEL")
    ai_escalation_model: str = Field(default="gpt-5.5", validation_alias="SPORTSHUB_AI_ESCALATION_MODEL")
    ai_checkin_model: str = Field(default="gpt-5.4-mini", validation_alias="SPORTSHUB_AI_CHECKIN_MODEL")

    # Legacy field retained for backward compatibility with any external reference;
    # the orchestrator now routes through the provider's select_model() instead.
    openai_model: str = "gpt-5.4-mini"
    openai_max_tokens: int = 2000
    openai_temperature: float = 0.7

    # AI Coach usage policy — the ONLY quota: Premium users get this many
    # user-visible AI Coach messages per UTC calendar day. No burst/window/
    # concurrency/free-tier quotas.
    ai_daily_message_limit: int = Field(default=200, validation_alias="SPORTSHUB_AI_DAILY_MESSAGE_LIMIT")

    class Config:
        env_file = ".env"


@lru_cache()
def get_settings() -> Settings:
    return Settings()
