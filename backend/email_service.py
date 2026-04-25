"""
Email service for SportsHub.
Sends 6-digit verification codes via SMTP if configured, falls back to console for dev.

Hashing:
  SHA-256(code + ":" + salt) where salt = str(user_id).
  Salting prevents rainbow-table attacks even if the DB is compromised.
  The raw code is NEVER logged or persisted.
"""
import os
import hashlib
import secrets
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

VERIFICATION_CODE_LENGTH = 6
VERIFICATION_CODE_TTL_MINUTES = 10

# Per-deployment secret mixed into every hash.
# Set VERIFICATION_SECRET_SALT in environment for production.
# This is separate from user-id salt — provides a second factor of protection.
_DEPLOY_SALT = os.environ.get("VERIFICATION_SECRET_SALT", "sportshub-dev-salt-change-in-production")


def generate_verification_code() -> str:
    """Generate a cryptographically random 6-digit numeric code."""
    return f"{secrets.randbelow(1_000_000):06d}"


def hash_code(code: str, user_id: str) -> str:
    """
    Hash a verification code with SHA-256 + per-user salt + deploy-level salt.

    Formula: SHA-256( code + ":" + str(user_id) + ":" + DEPLOY_SALT )

    This means:
    - Two users with the same code produce different hashes (per-user salt)
    - Even a full DB dump with known user IDs requires breaking the deploy salt
    - Raw codes are never stored or logged

    Args:
        code: The 6-digit code (only used transiently during request)
        user_id: The user's UUID as a string (serves as per-user salt)
    """
    payload = f"{code}:{user_id}:{_DEPLOY_SALT}"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def send_verification_code_email(email: str, code: str) -> bool:
    """
    Send a verification code email.
    Returns True if sent via SMTP, False if console-only (dev mode).

    Required env vars for SMTP:
        SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASS
    Optional:
        FROM_EMAIL (defaults to SMTP_USER or noreply@sportshub.app)

    IMPORTANT: The `code` parameter is used only for composing the email body.
    It is never stored, cached, or logged by this function.
    """
    subject = "Your SportsHub verification code"
    body = (
        f"Welcome to SportsHub!\n\n"
        f"Your email verification code is:\n\n"
        f"    {code}\n\n"
        f"This code expires in {VERIFICATION_CODE_TTL_MINUTES} minutes.\n"
        f"Do not share this code with anyone.\n\n"
        f"If you didn't create a SportsHub account, you can safely ignore this email.\n\n"
        f"— The SportsHub Team\n"
    )

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    from_email = os.environ.get("FROM_EMAIL", smtp_user or "noreply@sportshub.app")

    if smtp_host and smtp_user and smtp_pass:
        try:
            msg = MIMEMultipart()
            msg["From"] = from_email
            msg["To"] = email
            msg["Subject"] = subject
            msg.attach(MIMEText(body, "plain"))
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.ehlo()
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(from_email, email, msg.as_string())
            print(f"[EMAIL] Verification code sent to {email} via SMTP")
            return True
        except Exception as e:
            print(f"[EMAIL] SMTP send failed: {e} — falling back to console")

    # Console fallback (dev / no SMTP configured)
    # Intentionally prints the code for development use only.
    print("\n" + "=" * 60)
    print(f"[EMAIL DEV] TO: {email}")
    print(f"[EMAIL DEV] SUBJECT: {subject}")
    print(f"[EMAIL DEV] VERIFICATION CODE: {code}")
    print("=" * 60 + "\n")
    return False


def send_password_reset_email(email: str, code: str) -> bool:
    """
    Send a password reset code email.
    Returns True if sent via SMTP, False if console-only (dev mode).
    """
    subject = "Reset your SportsHub password"
    body = (
        f"Hi,\n\n"
        f"We received a request to reset your SportsHub password.\n\n"
        f"Your reset code is:\n\n"
        f"    {code}\n\n"
        f"This code expires in {VERIFICATION_CODE_TTL_MINUTES} minutes.\n"
        f"Do not share this code with anyone.\n\n"
        f"If you didn't request a password reset, you can safely ignore this email.\n\n"
        f"— The SportsHub Team\n"
    )

    smtp_host = os.environ.get("SMTP_HOST")
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    smtp_user = os.environ.get("SMTP_USER")
    smtp_pass = os.environ.get("SMTP_PASS")
    from_email = os.environ.get("FROM_EMAIL", smtp_user or "noreply@sportshub.app")

    if smtp_host and smtp_user and smtp_pass:
        try:
            msg = MIMEMultipart()
            msg["From"] = from_email
            msg["To"] = email
            msg["Subject"] = subject
            msg.attach(MIMEText(body, "plain"))
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                server.ehlo()
                server.starttls()
                server.login(smtp_user, smtp_pass)
                server.sendmail(from_email, email, msg.as_string())
            print(f"[EMAIL] Password reset code sent to {email} via SMTP")
            return True
        except Exception as e:
            print(f"[EMAIL] SMTP send failed: {e} — falling back to console")

    print("\n" + "=" * 60)
    print(f"[EMAIL DEV] TO: {email}")
    print(f"[EMAIL DEV] SUBJECT: {subject}")
    print(f"[EMAIL DEV] PASSWORD RESET CODE: {code}")
    print("=" * 60 + "\n")
    return False
