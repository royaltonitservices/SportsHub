"""
Account Repair Script - Restore TWO separate accounts
USAGE: python repair_accounts.py

This script:
1. Restores Account 1 (Premium): aarushkhanna11@gmail.com with password $81Premium
2. Fixes Account 2 (Admin): aarushkhanna@icloud.com with password $81Admin
"""
from sqlalchemy.orm import Session
from database import SessionLocal
import models
import models_premium
from auth import get_password_hash
from datetime import datetime, timedelta
import uuid as uuid_pkg

# Account configurations
ACCOUNT_1_EMAIL = "aarushkhanna11@gmail.com"
ACCOUNT_1_PASSWORD = "$81Premium"
ACCOUNT_1_USERNAME = "aarushpremium"  # Different from existing akhooper
ACCOUNT_1_ROLE = models.UserRole.USER

ACCOUNT_2_EMAIL = "aarushkhanna@icloud.com"
ACCOUNT_2_PASSWORD = "$81Admin"
ACCOUNT_2_ROLE = models.UserRole.ADMIN


def repair_accounts():
    """
    Repair both accounts:
    - Recreate Account 1 if missing
    - Fix Account 2 password if wrong
    """
    db: Session = SessionLocal()

    try:
        print("="*70)
        print("ACCOUNT REPAIR SCRIPT")
        print("="*70)
        print()

        # ===================================================================
        # STEP 1: Check and restore Account 1 (Premium)
        # ===================================================================
        print("STEP 1: Checking Account 1 (Premium User)")
        print("-"*70)

        account1 = db.query(models.User).filter(
            models.User.email == ACCOUNT_1_EMAIL
        ).first()

        if account1:
            print(f"✓ Account 1 already exists: {account1.email}")
            print(f"  Username: {account1.username}")
            print(f"  Role: {account1.role.value}")
        else:
            print(f"❌ Account 1 missing - Creating now...")

            # Create Account 1 from scratch
            new_user = models.User(
                email=ACCOUNT_1_EMAIL,
                username=ACCOUNT_1_USERNAME,
                password_hash=get_password_hash(ACCOUNT_1_PASSWORD),
                display_name=ACCOUNT_1_USERNAME,
                date_of_birth=datetime(1995, 1, 1),  # Default DOB
                age_verified=True,
                email_verified=True,
                avatar_seed=ACCOUNT_1_USERNAME,
                account_status=models.AccountStatus.ACTIVE,
                role=ACCOUNT_1_ROLE
            )

            db.add(new_user)
            db.flush()  # Get the ID without committing

            print(f"✓ Created user account:")
            print(f"  Email: {new_user.email}")
            print(f"  Username: {new_user.username}")
            print(f"  User ID: {new_user.id}")
            print(f"  Role: {new_user.role.value}")

            # Create sport profiles for all sports
            for sport in models.Sport:
                sport_profile = models.SportProfile(
                    user_id=new_user.id,
                    sport=sport
                )
                db.add(sport_profile)

            print(f"✓ Created sport profiles for all 4 sports")

            # Create premium subscription
            premium_sub = models_premium.Subscription(
                user_id=new_user.id,
                tier=models_premium.SubscriptionTier.PREMIUM,
                status=models_premium.SubscriptionStatus.ACTIVE,
                price_per_month=8.99,
                started_at=datetime.utcnow(),
                expires_at=datetime.utcnow() + timedelta(days=365),
                platform="manual_grant"
            )
            db.add(premium_sub)

            print(f"✓ Created premium subscription (expires in 1 year)")

            print(f"\n✓✓✓ Account 1 CREATED successfully")
            print(f"  Login: {ACCOUNT_1_EMAIL} / {ACCOUNT_1_PASSWORD}")

        print()

        # ===================================================================
        # STEP 2: Fix Account 2 (Admin) password
        # ===================================================================
        print("STEP 2: Checking Account 2 (Admin User)")
        print("-"*70)

        account2 = db.query(models.User).filter(
            models.User.email == ACCOUNT_2_EMAIL
        ).first()

        if not account2:
            print(f"❌ ERROR: Account 2 not found!")
            print(f"   Expected: {ACCOUNT_2_EMAIL}")
            return False

        print(f"✓ Account 2 found: {account2.email}")
        print(f"  Username: {account2.username}")
        print(f"  Role: {account2.role.value}")

        # Check current password
        from auth import verify_password

        current_pwd_correct = verify_password(ACCOUNT_2_PASSWORD, account2.password_hash)

        if current_pwd_correct:
            print(f"✓ Password already correct: {ACCOUNT_2_PASSWORD}")
        else:
            print(f"❌ Password incorrect - Updating now...")

            old_hash = account2.password_hash[:20]
            account2.password_hash = get_password_hash(ACCOUNT_2_PASSWORD)
            new_hash = account2.password_hash[:20]

            print(f"  Old hash: {old_hash}...")
            print(f"  New hash: {new_hash}...")

            # Verify new password works
            verify_result = verify_password(ACCOUNT_2_PASSWORD, account2.password_hash)

            if verify_result:
                print(f"✓✓✓ Password updated and verified")
                print(f"  Login: {ACCOUNT_2_EMAIL} / {ACCOUNT_2_PASSWORD}")
            else:
                print(f"❌ ERROR: Password verification failed!")
                db.rollback()
                return False

        print()

        # ===================================================================
        # COMMIT ALL CHANGES
        # ===================================================================
        db.commit()

        print("="*70)
        print("REPAIR COMPLETE - SUMMARY")
        print("="*70)

        # Verify both accounts
        all_aarush_accounts = db.query(models.User).filter(
            models.User.email.like('%aarushkhanna%')
        ).all()

        print(f"\nTotal accounts for user: {len(all_aarush_accounts)}")
        print()

        for idx, user in enumerate(all_aarush_accounts, 1):
            print(f"Account #{idx}:")
            print(f"  Email: {user.email}")
            print(f"  Username: {user.username}")
            print(f"  Role: {user.role.value}")
            print(f"  Status: {user.account_status.value}")

            # Test login credentials
            if user.email == ACCOUNT_1_EMAIL:
                pwd_works = verify_password(ACCOUNT_1_PASSWORD, user.password_hash)
                print(f"  Password '{ACCOUNT_1_PASSWORD}': {'✓ WORKS' if pwd_works else '✗ BROKEN'}")
            elif user.email == ACCOUNT_2_EMAIL:
                pwd_works = verify_password(ACCOUNT_2_PASSWORD, user.password_hash)
                print(f"  Password '{ACCOUNT_2_PASSWORD}': {'✓ WORKS' if pwd_works else '✗ BROKEN'}")

            print()

        print("="*70)
        print("✓✓✓ BOTH ACCOUNTS READY FOR LOGIN")
        print("="*70)

        return True

    except Exception as e:
        db.rollback()
        print(f"\n❌ ERROR: Repair failed")
        print(f"   {type(e).__name__}: {str(e)}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        db.close()


if __name__ == "__main__":
    success = repair_accounts()

    if success:
        print("\n" + "="*70)
        print("LOGIN CREDENTIALS")
        print("="*70)
        print()
        print("PREMIUM USER:")
        print(f"  Email: {ACCOUNT_1_EMAIL}")
        print(f"  Password: {ACCOUNT_1_PASSWORD}")
        print(f"  Role: Premium (user)")
        print()
        print("ADMIN USER:")
        print(f"  Email: {ACCOUNT_2_EMAIL}")
        print(f"  Password: {ACCOUNT_2_PASSWORD}")
        print(f"  Role: Admin")
        print()
        print("="*70)
    else:
        print("\n❌ REPAIR FAILED - See errors above")
