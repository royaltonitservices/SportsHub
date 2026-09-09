"""Gate 1.4B — canonical block policy.

`BlockedUser` is the SINGLE source of truth for "has X blocked Y" across every
direct-contact and discovery surface. All routes MUST use these helpers instead of ad-hoc
checks or the legacy `Friendship.BLOCKED` status (which is being retired).

A block is DIRECTED (blocker -> blocked). Enforcement is BIDIRECTIONAL: if either party has
blocked the other, contact/discovery is denied. Unblock removes only the caller's directed
row, so a reverse block keeps enforcing.
"""
from typing import Optional

from sqlalchemy import or_, and_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import models


def directed_block(db: Session, blocker_id, blocked_id) -> Optional["models.BlockedUser"]:
    """The caller's own directed block of the target, if any."""
    return db.query(models.BlockedUser).filter(
        models.BlockedUser.blocker_id == blocker_id,
        models.BlockedUser.blocked_id == blocked_id,
    ).first()


def is_blocked(db: Session, user_id_1, user_id_2) -> bool:
    """True if EITHER user has blocked the other (bidirectional)."""
    return db.query(models.BlockedUser).filter(
        or_(
            and_(models.BlockedUser.blocker_id == user_id_1,
                 models.BlockedUser.blocked_id == user_id_2),
            and_(models.BlockedUser.blocker_id == user_id_2,
                 models.BlockedUser.blocked_id == user_id_1),
        )
    ).first() is not None


def _sever_relationship(db: Session, a, b) -> None:
    """End any friendship AND cancel any pending request between the pair (both directions)."""
    db.query(models.Friendship).filter(
        or_(
            and_(models.Friendship.user_a_id == a, models.Friendship.user_b_id == b),
            and_(models.Friendship.user_a_id == b, models.Friendship.user_b_id == a),
        )
    ).delete(synchronize_session=False)


def apply_block(db: Session, blocker_id, blocked_id) -> "models.BlockedUser":
    """Idempotently record a directed block and sever the relationship.

    - Ends accepted friendship and cancels pending requests (both directions).
    - Never creates a duplicate directed row (returns the existing one).
    Commits and returns the directed `BlockedUser`.
    """
    existing = directed_block(db, blocker_id, blocked_id)
    if existing is not None:
        _sever_relationship(db, blocker_id, blocked_id)   # self-healing / idempotent
        db.commit()
        return existing
    _sever_relationship(db, blocker_id, blocked_id)
    block = models.BlockedUser(blocker_id=blocker_id, blocked_id=blocked_id)
    db.add(block)
    try:
        db.commit()
    except IntegrityError:
        # Concurrent duplicate lost the unique-index race: no server error, no lost
        # enforcement — re-resolve to the winner's row and return it (idempotent).
        db.rollback()
        again = directed_block(db, blocker_id, blocked_id)
        if again is None:
            raise
        return again
    db.refresh(block)
    return block


def remove_block(db: Session, blocker_id, blocked_id) -> bool:
    """Remove ONLY the caller's directed block. A reverse block is untouched, and this never
    restores friendship, pending requests, or contact permission. Returns True if removed."""
    existing = directed_block(db, blocker_id, blocked_id)
    if existing is None:
        return False
    db.delete(existing)
    db.commit()
    return True
