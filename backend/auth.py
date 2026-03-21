"""
JWT authentication utilities
"""
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
import bcrypt
from config import get_settings

settings = get_settings()


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a password against its hash"""
    try:
        # Truncate password to 72 bytes for bcrypt
        plain_bytes = plain_password[:72].encode('utf-8')
        hashed_bytes = hashed_password.encode('utf-8')
        return bcrypt.checkpw(plain_bytes, hashed_bytes)
    except Exception:
        return False


def get_password_hash(password: str) -> str:
    """Hash a password"""
    # Truncate password to 72 bytes for bcrypt
    password_bytes = password[:72].encode('utf-8')
    hashed = bcrypt.hashpw(password_bytes, bcrypt.gensalt())
    return hashed.decode('utf-8')


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Create a JWT access token"""
    to_encode = data.copy()

    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.access_token_expire_minutes)

    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)

    return encoded_jwt


def decode_access_token(token: str) -> Optional[dict]:
    """Decode and validate a JWT token"""
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
        return payload
    except JWTError:
        return None


def generate_verification_token() -> str:
    """Generate a random verification token"""
    import secrets
    return secrets.token_urlsafe(32)


def send_verification_email(email: str, token: str) -> bool:
    """
    Send verification email to user

    In production, this should use a proper email service (SendGrid, AWS SES, etc.)
    For now, we'll just print the verification link
    """
    verification_link = f"http://localhost:8000/auth/verify-email?token={token}"

    print(f"\n{'='*60}")
    print(f"EMAIL VERIFICATION")
    print(f"To: {email}")
    print(f"Subject: Verify your SportsHub account")
    print(f"\nClick this link to verify your email:")
    print(f"{verification_link}")
    print(f"{'='*60}\n")

    # TODO: Implement actual email sending
    # import smtplib
    # from email.mime.text import MIMEText
    # from email.mime.multipart import MIMEMultipart

    return True
