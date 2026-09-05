"""
Account deletion foundation.

One entry point — `delete_user_account(db, user)` — performs a full, ordered,
single-transaction deletion of a user's account and their private/owned data.

Deletion policy (see Group B inventory):
  - Private / personal data → HARD DELETE
        AI conversations & insights, wearable/biometric data, private messages,
        training sessions/workouts/skill snapshots, goals/surveys/sport profiles,
        badges, likes, blocks, friendships, group memberships, subscription,
        upload records + their files, avatar file.
  - Public / owned social content → HARD DELETE
        the user's posts, clips, comments, highlights (and their media files,
        likes, and views). Other users' replies to a deleted comment are
        detached (parent_comment_id → NULL) rather than destroyed.
  - Competitive / shared-history data → PRESERVED, IDENTITY DETACHED
        challenges, matches, disputes, match evidence, teams they captained,
        tournaments they created are re-pointed at a singleton, non-discoverable
        "deleted user" sentinel so an opponent's match/challenge history and the
        leaderboard win/loss counts are NOT corrupted.
  - Moderation / audit / community refs → DETACHED (NULL)
        moderation reports they filed, admin-action targets, community-added
        tennis courts keep their record but lose the identity link.

The User row itself is HARD DELETED, so any previously-issued JWT stops working
immediately (get_current_user does a DB lookup and 401s when the row is gone).

Everything runs in one transaction: if any step raises, the whole thing rolls
back and the account is left fully intact. Media files are unlinked only AFTER a
successful commit (best-effort — a missing file never fails the deletion).
"""
from __future__ import annotations

import os
import secrets
from datetime import datetime
from typing import List, Optional

# Sentinel identity used to preserve shared competitive history after a user is
# deleted. account_status = BANNED keeps it out of user search (which filters on
# ACTIVE) and it is never given a SportProfile, so it cannot appear on a
# leaderboard. Its password hash is random and unusable — it can never log in.
SENTINEL_USERNAME = "__deleted_user__"
SENTINEL_EMAIL = "deleted@sportshub.invalid"
SENTINEL_DISPLAY_NAME = "Deleted User"

_UPLOADS_ROOT = "./uploads"


def _cdn_url_to_local_path(url: Optional[str]) -> Optional[str]:
    """Map a served CDN URL ("/cdn/videos/x.mov") to its on-disk path
    ("./uploads/videos/x.mov"). Returns None for anything not under /cdn/."""
    if not url:
        return None
    marker = "/cdn/"
    if url.startswith(marker):
        return os.path.join(_UPLOADS_ROOT, url[len(marker):])
    return None


def _get_or_create_sentinel(db):
    import models
    sentinel = (
        db.query(models.User)
        .filter(models.User.username == SENTINEL_USERNAME)
        .first()
    )
    if sentinel is not None:
        return sentinel
    sentinel = models.User(
        email=SENTINEL_EMAIL,
        username=SENTINEL_USERNAME,
        password_hash="!" + secrets.token_hex(32),  # unusable — never matches any password
        display_name=SENTINEL_DISPLAY_NAME,
        date_of_birth=datetime(1970, 1, 1),
        role=models.UserRole.USER,
        account_status=models.AccountStatus.BANNED,
        age_verified=True,
        email_verified=False,
        is_legacy_account=True,
    )
    db.add(sentinel)
    db.flush()  # assign PK so we can reassign FKs to it
    return sentinel


def delete_user_account(db, user) -> None:
    """Delete `user` and all of their private/owned data in a single transaction.

    Preserves shared competitive history by re-pointing it at a sentinel.
    Raises on failure (caller should not commit); on success the transaction is
    committed here and orphaned media files are unlinked best-effort.
    """
    import models
    import models_premium as mp

    user_id = user.id
    files_to_unlink: List[str] = []

    try:
        sentinel = _get_or_create_sentinel(db)
        sentinel_id = sentinel.id

        # ── Phase A: preserve competitive/shared history, detach identity ───────
        # NOT-NULL user FKs are re-pointed at the sentinel so opponent history and
        # leaderboard win/loss counts survive intact.
        db.query(models.Match).filter(models.Match.player1_id == user_id)\
            .update({models.Match.player1_id: sentinel_id}, synchronize_session=False)
        db.query(models.Match).filter(models.Match.player2_id == user_id)\
            .update({models.Match.player2_id: sentinel_id}, synchronize_session=False)
        db.query(models.Match).filter(models.Match.winner_id == user_id)\
            .update({models.Match.winner_id: sentinel_id}, synchronize_session=False)

        db.query(models.Challenge).filter(models.Challenge.challenger_id == user_id)\
            .update({models.Challenge.challenger_id: sentinel_id}, synchronize_session=False)
        db.query(models.Challenge).filter(models.Challenge.opponent_id == user_id)\
            .update({models.Challenge.opponent_id: sentinel_id}, synchronize_session=False)
        db.query(models.Challenge).filter(models.Challenge.winner_id == user_id)\
            .update({models.Challenge.winner_id: sentinel_id}, synchronize_session=False)

        db.query(models.Dispute).filter(models.Dispute.initiator_id == user_id)\
            .update({models.Dispute.initiator_id: sentinel_id}, synchronize_session=False)
        db.query(models.Dispute).filter(models.Dispute.resolved_by == user_id)\
            .update({models.Dispute.resolved_by: None}, synchronize_session=False)

        # Match evidence is part of a shared (possibly disputed) match record —
        # preserve it, detach identity, and deliberately keep its files.
        db.query(models.MatchEvidence).filter(models.MatchEvidence.submitter_id == user_id)\
            .update({models.MatchEvidence.submitter_id: sentinel_id}, synchronize_session=False)
        db.query(models.MatchEvidence).filter(models.MatchEvidence.reviewed_by == user_id)\
            .update({models.MatchEvidence.reviewed_by: None}, synchronize_session=False)

        # Teams/tournaments survive for their other members/participants.
        db.query(models.Team).filter(models.Team.captain_id == user_id)\
            .update({models.Team.captain_id: sentinel_id}, synchronize_session=False)
        db.query(mp.Tournament).filter(mp.Tournament.creator_id == user_id)\
            .update({mp.Tournament.creator_id: sentinel_id}, synchronize_session=False)

        # ── Phase B: detach moderation / audit / community references ───────────
        db.query(models.ModerationFlag).filter(models.ModerationFlag.reporter_id == user_id)\
            .update({models.ModerationFlag.reporter_id: None}, synchronize_session=False)
        db.query(models.AdminAction).filter(models.AdminAction.target_user_id == user_id)\
            .update({models.AdminAction.target_user_id: None}, synchronize_session=False)
        db.query(models.TennisCourt).filter(models.TennisCourt.added_by == user_id)\
            .update({models.TennisCourt.added_by: None}, synchronize_session=False)

        # ── Phase C: hard delete owned social content (+ collect media files) ───
        # Clips owned by the user.
        clips = db.query(models.Clip).filter(models.Clip.author_id == user_id).all()
        clip_ids = [c.id for c in clips]
        for c in clips:
            files_to_unlink.append(_cdn_url_to_local_path(c.video_url))
            files_to_unlink.append(_cdn_url_to_local_path(c.thumbnail_url))
        if clip_ids:
            db.query(models.ClipLike).filter(models.ClipLike.clip_id.in_(clip_ids))\
                .delete(synchronize_session=False)
        db.query(models.ClipLike).filter(models.ClipLike.user_id == user_id)\
            .delete(synchronize_session=False)
        if clip_ids:
            db.query(models.Clip).filter(models.Clip.id.in_(clip_ids))\
                .delete(synchronize_session=False)

        # Posts owned by the user, plus every comment on those posts and comments
        # the user authored anywhere. Other users' replies to a removed comment are
        # detached (parent_comment_id → NULL) so their content isn't destroyed.
        post_id_list = [row[0] for row in
                        db.query(models.Post.id).filter(models.Post.author_id == user_id).all()]

        from sqlalchemy import or_
        _comment_cond = models.Comment.author_id == user_id
        if post_id_list:
            _comment_cond = or_(_comment_cond, models.Comment.post_id.in_(post_id_list))
        deleted_comment_ids = [
            row[0] for row in db.query(models.Comment.id).filter(_comment_cond).all()
        ]
        if deleted_comment_ids:
            db.query(models.Comment).filter(
                models.Comment.parent_comment_id.in_(deleted_comment_ids),
                ~models.Comment.id.in_(deleted_comment_ids),
            ).update({models.Comment.parent_comment_id: None}, synchronize_session=False)
            db.query(models.Comment).filter(models.Comment.id.in_(deleted_comment_ids))\
                .delete(synchronize_session=False)
        if post_id_list:
            db.query(models.PostLike).filter(models.PostLike.post_id.in_(post_id_list))\
                .delete(synchronize_session=False)
            db.query(models.Post).filter(models.Post.id.in_(post_id_list))\
                .delete(synchronize_session=False)
        db.query(models.PostLike).filter(models.PostLike.user_id == user_id)\
            .delete(synchronize_session=False)

        # Highlights owned by the user (+ their media files and view rows).
        highlights = db.query(models.Highlight).filter(models.Highlight.user_id == user_id).all()
        highlight_ids = [h.id for h in highlights]
        for h in highlights:
            files_to_unlink.append(_cdn_url_to_local_path(h.media_url))
            files_to_unlink.append(_cdn_url_to_local_path(h.thumbnail_url))
        if highlight_ids:
            db.query(models.HighlightView).filter(models.HighlightView.highlight_id.in_(highlight_ids))\
                .delete(synchronize_session=False)
            db.query(models.Highlight).filter(models.Highlight.id.in_(highlight_ids))\
                .delete(synchronize_session=False)
        db.query(models.HighlightView).filter(models.HighlightView.viewer_id == user_id)\
            .delete(synchronize_session=False)

        # ── Phase C (cont.): hard delete private/personal data ──────────────────
        db.query(models.Message).filter(
            (models.Message.sender_id == user_id) | (models.Message.receiver_id == user_id)
        ).delete(synchronize_session=False)

        # Group chats the user created: remove members + messages, then the group.
        group_ids = [row[0] for row in
                     db.query(models.GroupChat.id).filter(models.GroupChat.creator_id == user_id).all()]
        if group_ids:
            db.query(models.Message).filter(models.Message.group_id.in_(group_ids))\
                .delete(synchronize_session=False)
            db.query(models.GroupChatMember).filter(models.GroupChatMember.group_id.in_(group_ids))\
                .delete(synchronize_session=False)
            db.query(models.GroupChat).filter(models.GroupChat.id.in_(group_ids))\
                .delete(synchronize_session=False)
        db.query(models.GroupChatMember).filter(models.GroupChatMember.user_id == user_id)\
            .delete(synchronize_session=False)

        db.query(models.Friendship).filter(
            (models.Friendship.user_a_id == user_id)
            | (models.Friendship.user_b_id == user_id)
            | (models.Friendship.initiated_by == user_id)
        ).delete(synchronize_session=False)
        db.query(models.BlockedUser).filter(
            (models.BlockedUser.blocker_id == user_id) | (models.BlockedUser.blocked_id == user_id)
        ).delete(synchronize_session=False)

        db.query(models.TeamMember).filter(models.TeamMember.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(mp.TournamentParticipant).filter(mp.TournamentParticipant.user_id == user_id)\
            .delete(synchronize_session=False)

        db.query(models.UserBadge).filter(models.UserBadge.user_id == user_id)\
            .delete(synchronize_session=False)
        # External auth identities (Sign in with Apple, etc.) — explicit delete so no
        # stale (provider, subject) row survives, independent of DB FK-cascade support.
        db.query(models.AuthIdentity).filter(models.AuthIdentity.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(models.SportProfile).filter(models.SportProfile.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(models.OnboardingSurvey).filter(models.OnboardingSurvey.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(models.CoachContext).filter(models.CoachContext.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(models.CoachConversationMessage).filter(models.CoachConversationMessage.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(models.SkillSnapshot).filter(models.SkillSnapshot.user_id == user_id)\
            .delete(synchronize_session=False)

        # Training sessions (+ their drill children) and saved workouts.
        session_ids = [row[0] for row in
                       db.query(models.TrainingSession.id).filter(models.TrainingSession.user_id == user_id).all()]
        if session_ids:
            db.query(models.TrainingSessionDrill).filter(
                models.TrainingSessionDrill.session_id.in_(session_ids)
            ).delete(synchronize_session=False)
            db.query(models.TrainingSession).filter(models.TrainingSession.id.in_(session_ids))\
                .delete(synchronize_session=False)
        db.query(models.SavedWorkout).filter(models.SavedWorkout.user_id == user_id)\
            .delete(synchronize_session=False)

        # Premium/private records.
        db.query(mp.SportGoals).filter(mp.SportGoals.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(mp.SmartwatchConnection).filter(mp.SmartwatchConnection.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(mp.BiometricData).filter(mp.BiometricData.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(mp.AICoachInsight).filter(mp.AICoachInsight.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(mp.PerformancePrediction).filter(mp.PerformancePrediction.user_id == user_id)\
            .delete(synchronize_session=False)
        db.query(mp.Subscription).filter(mp.Subscription.user_id == user_id)\
            .delete(synchronize_session=False)

        # Server-issued upload records + their files.
        uploads = db.query(models.UploadRecord).filter(models.UploadRecord.owner_id == user_id).all()
        for u in uploads:
            if u.storage_path:
                files_to_unlink.append(os.path.join(_UPLOADS_ROOT, u.storage_path))
        db.query(models.UploadRecord).filter(models.UploadRecord.owner_id == user_id)\
            .delete(synchronize_session=False)

        # Avatar file.
        files_to_unlink.append(_cdn_url_to_local_path(getattr(user, "avatar_url", None)))

        # ── Phase D: delete the user row itself ─────────────────────────────────
        db.query(models.User).filter(models.User.id == user_id)\
            .delete(synchronize_session=False)

        db.commit()
    except Exception:
        db.rollback()
        raise

    # ── Phase E: best-effort media cleanup (never fails the deletion) ───────────
    for path in files_to_unlink:
        if not path:
            continue
        try:
            if os.path.isfile(path):
                os.remove(path)
        except OSError:
            pass
