"""
Database migration script to upgrade existing user to ADMIN role
USAGE: python upgrade_to_admin.py
"""
from sqlalchemy.orm import Session
from database import SessionLocal, engine
import models
import models_premium  # Import premium models for relationships

# Target user configuration
OLD_EMAIL = "aarushkhanna11@gmail.com"  # Current email in database
NEW_EMAIL = "aarushkhanna@icloud.com"   # New email to set

def upgrade_user_to_admin():
    """
    Upgrade existing user to ADMIN role and update email.

    Rules:
    - Do not create a new account
    - Do not create duplicate users
    - Preserve all existing user data (profile, stats, friends, matches, posts, settings)
    - Only change the role to ADMIN and email
    - Do not change the password
    """
    db: Session = SessionLocal()

    try:
        # Find the existing user by old email
        user = db.query(models.User).filter(models.User.email == OLD_EMAIL).first()

        if not user:
            print(f"❌ ERROR: No user found with email: {OLD_EMAIL}")
            print(f"   Please create an account with this email first.")
            return False

        # Store original values for logging
        original_role = user.role
        original_email = user.email

        # Update email and upgrade to ADMIN (preserving all other data)
        user.email = NEW_EMAIL
        user.role = models.UserRole.ADMIN

        db.commit()
        db.refresh(user)

        print(f"✓ SUCCESS: User upgraded to ADMIN")
        print(f"  Previous Email: {original_email}")
        print(f"  New Email: {user.email}")
        print(f"  Username: {user.username}")
        print(f"  User ID: {user.id}")
        print(f"  Previous Role: {original_role.value}")
        print(f"  New Role: {user.role.value}")
        print(f"  Account Status: {user.account_status.value}")
        print(f"\n✓ Admin permissions granted:")
        print(f"  • User management")
        print(f"  • Content moderation")
        print(f"  • Challenge review")
        print(f"  • Match dispute review")
        print(f"  • System health monitoring")
        print(f"\n✓ All existing data preserved:")
        print(f"  • Profile, stats, friends, matches, posts, settings - INTACT")
        print(f"  • Password - UNCHANGED")

        return True

    except Exception as e:
        db.rollback()
        print(f"❌ ERROR: Failed to upgrade user")
        print(f"   {str(e)}")
        return False

    finally:
        db.close()


if __name__ == "__main__":
    print("="*60)
    print("ADMIN ROLE UPGRADE SCRIPT")
    print("="*60)
    print(f"Current email: {OLD_EMAIL}")
    print(f"New email: {NEW_EMAIL}")
    print(f"Action: Update email and upgrade to ADMIN role")
    print("="*60)
    print()

    success = upgrade_user_to_admin()

    print()
    print("="*60)
    if success:
        print("UPGRADE COMPLETE")
    else:
        print("UPGRADE FAILED")
    print("="*60)
