"""
seed_dev_data.py — LOCAL/DEV ONLY. Do NOT run against production.

Populates realistic test data for manual validation of SportsHub core flows.

Data created:
  Basketball seed (1–8):
    Users       : 3 seed users (sam_hooper, maya_baller, jj_courtking)
    Profiles    : Non-provisional basketball sport profiles (varied ELO)
    Friendships : 2 accepted + 1 pending for test user (ak_hooper)
    Challenges  : 3 completed + 1 active
    Posts       : 3 basketball posts from seed users
    Clips       : 2 clip records (no video files — records only)
    Messages    : 4-message conversation between test user and sam_hooper
    Badges      : 1 earned badge for test user

  Four-sport expansion seed (9–15):
    Users       : 6 seed users (rj_routes, dale_receiver, sasha_striker,
                  leo_dribbler, kai_ace, priya_baseline)
    Profiles    : Football/Soccer/Tennis profiles for new users
                  + test user's Football/Soccer/Tennis profiles (leaderboard visible)
    Friendships : 3 accepted (test user ↔ rj_routes/sasha_striker/kai_ace)
    Challenges  : 3 completed + 3 active (one per sport)
    Posts       : 6 sport-specific posts (2 per sport)
    Clips       : 3 clip records (no video files — records only)

Seed users password: SportsHub123!
Test user (ak_hooper): use existing password.

Usage:
  cd backend
  python seed_dev_data.py            # Add seed data (idempotent)
  python seed_dev_data.py --dry-run  # Preview without writing
  python seed_dev_data.py --reset    # Remove seed data then re-seed (DESTRUCTIVE)
"""

import sys
import os
import argparse
import sqlite3
import uuid as uuid_mod
from datetime import datetime, timedelta

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
os.chdir(SCRIPT_DIR)

from config import get_settings
DATABASE_URL = get_settings().database_url


def get_sqlite_path(url: str) -> str:
    if url.startswith("sqlite:///"):
        return url[len("sqlite:///"):]
    raise ValueError(f"Not a SQLite URL: {url}")


# ---------------------------------------------------------------------------
# Stable IDs — unchanged across reruns so --reset can target them precisely
# ---------------------------------------------------------------------------

TEST_USER_ID = "8d859ee4-9ede-4b74-aeaf-77e844234628"   # aarushkhanna11@gmail.com / ak_hooper

SAM_ID  = "aaaa0001-0000-0000-0000-000000000001"         # sam_hooper
MAYA_ID = "aaaa0001-0000-0000-0000-000000000002"         # maya_baller
JJ_ID   = "aaaa0001-0000-0000-0000-000000000003"         # jj_courtking

FRIENDSHIP_TEST_SAM_ID  = "bbbb0001-0000-0000-0000-000000000001"
FRIENDSHIP_TEST_MAYA_ID = "bbbb0001-0000-0000-0000-000000000002"
FRIENDSHIP_JJ_TEST_ID   = "bbbb0001-0000-0000-0000-000000000003"

CHALLENGE_1_ID = "cccc0001-0000-0000-0000-000000000001"  # test vs sam, completed, test won
CHALLENGE_2_ID = "cccc0001-0000-0000-0000-000000000002"  # test vs maya, completed, maya won
CHALLENGE_3_ID = "cccc0001-0000-0000-0000-000000000003"  # sam vs jj, completed, sam won
CHALLENGE_4_ID = "cccc0001-0000-0000-0000-000000000004"  # test vs jj, active (ACCEPTED)

POST_IDS = [
    "dddd0001-0000-0000-0000-000000000001",
    "dddd0001-0000-0000-0000-000000000002",
    "dddd0001-0000-0000-0000-000000000003",
]

CLIP_1_ID = "eeee0001-0000-0000-0000-000000000001"
CLIP_2_ID = "eeee0001-0000-0000-0000-000000000002"

MSG_IDS = [
    "ffff0001-0000-0000-0000-000000000001",
    "ffff0001-0000-0000-0000-000000000002",
    "ffff0001-0000-0000-0000-000000000003",
    "ffff0001-0000-0000-0000-000000000004",
]

BADGE_ID = "9999a001-0000-0000-0000-000000000001"

# ---------------------------------------------------------------------------
# Four-Sport Expansion IDs — Football, Soccer, Tennis
# Prefix aaaa0002 / bbbb0002 / cccc0002 / dddd0002 / eeee0002 to avoid collision
# ---------------------------------------------------------------------------

RJ_ID    = "aaaa0002-0000-0000-0000-000000000001"   # rj_routes       (football)
DALE_ID  = "aaaa0002-0000-0000-0000-000000000002"   # dale_receiver   (football)
SASHA_ID = "aaaa0002-0000-0000-0000-000000000003"   # sasha_striker   (soccer)
LEO_ID   = "aaaa0002-0000-0000-0000-000000000004"   # leo_dribbler    (soccer)
KAI_ID   = "aaaa0002-0000-0000-0000-000000000005"   # kai_ace         (tennis)
PRIYA_ID = "aaaa0002-0000-0000-0000-000000000006"   # priya_baseline  (tennis)

FRIENDSHIP_TEST_RJ_ID    = "bbbb0002-0000-0000-0000-000000000001"
FRIENDSHIP_TEST_SASHA_ID = "bbbb0002-0000-0000-0000-000000000002"
FRIENDSHIP_TEST_KAI_ID   = "bbbb0002-0000-0000-0000-000000000003"

CHALLENGE_F1_ID = "cccc0002-0000-0000-0000-000000000001"  # rj vs dale,  FOOTBALL, completed
CHALLENGE_F2_ID = "cccc0002-0000-0000-0000-000000000002"  # rj vs test,  FOOTBALL, active
CHALLENGE_F3_ID = "cccc0002-0000-0000-0000-000000000007"  # test vs rj,  FOOTBALL, completed (test won)
CHALLENGE_S1_ID = "cccc0002-0000-0000-0000-000000000003"  # sasha vs leo, SOCCER, completed
CHALLENGE_S2_ID = "cccc0002-0000-0000-0000-000000000004"  # sasha vs test, SOCCER, active
CHALLENGE_S3_ID = "cccc0002-0000-0000-0000-000000000008"  # test vs sasha, SOCCER, completed (sasha won)
CHALLENGE_T1_ID = "cccc0002-0000-0000-0000-000000000005"  # kai vs priya, TENNIS, completed
CHALLENGE_T2_ID = "cccc0002-0000-0000-0000-000000000006"  # kai vs test,  TENNIS, active
CHALLENGE_T3_ID = "cccc0002-0000-0000-0000-000000000009"  # test vs priya, TENNIS, completed (test won)

POST_F_IDS = [
    "dddd0002-0000-0000-0000-000000000001",
    "dddd0002-0000-0000-0000-000000000002",
]
POST_S_IDS = [
    "dddd0002-0000-0000-0000-000000000003",
    "dddd0002-0000-0000-0000-000000000004",
]
POST_T_IDS = [
    "dddd0002-0000-0000-0000-000000000005",
    "dddd0002-0000-0000-0000-000000000006",
]

CLIP_F_ID = "eeee0002-0000-0000-0000-000000000001"
CLIP_S_ID = "eeee0002-0000-0000-0000-000000000002"
CLIP_T_ID = "eeee0002-0000-0000-0000-000000000003"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_pw_hash(password: str = "SportsHub123!") -> str:
    import bcrypt
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def ts(offset_days: int = 0) -> str:
    """UTC timestamp string offset by N days from now."""
    dt = datetime.utcnow() + timedelta(days=offset_days)
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def row_exists(cur: sqlite3.Cursor, table: str, row_id: str) -> bool:
    cur.execute(f"SELECT 1 FROM {table} WHERE id = ?", (row_id,))
    return cur.fetchone() is not None


def username_exists(cur: sqlite3.Cursor, username: str) -> bool:
    cur.execute("SELECT 1 FROM users WHERE username = ?", (username,))
    return cur.fetchone() is not None


def profile_exists(cur: sqlite3.Cursor, user_id: str, sport: str) -> bool:
    cur.execute("SELECT 1 FROM sport_profiles WHERE user_id = ? AND sport = ?", (user_id, sport))
    return cur.fetchone() is not None


# ---------------------------------------------------------------------------
# Reset helpers
# ---------------------------------------------------------------------------

def reset_seed_data(cur: sqlite3.Cursor) -> None:
    print("  Removing existing seed data...")
    # Basketball seed
    cur.execute("DELETE FROM user_badges WHERE id = ?", (BADGE_ID,))
    for mid in MSG_IDS:
        cur.execute("DELETE FROM messages WHERE id = ?", (mid,))
    cur.execute("DELETE FROM clips WHERE id IN (?, ?)", (CLIP_1_ID, CLIP_2_ID))
    for pid in POST_IDS:
        cur.execute("DELETE FROM posts WHERE id = ?", (pid,))
    cur.execute("DELETE FROM challenges WHERE id IN (?, ?, ?, ?)",
                (CHALLENGE_1_ID, CHALLENGE_2_ID, CHALLENGE_3_ID, CHALLENGE_4_ID))
    cur.execute("DELETE FROM friendships WHERE id IN (?, ?, ?)",
                (FRIENDSHIP_TEST_SAM_ID, FRIENDSHIP_TEST_MAYA_ID, FRIENDSHIP_JJ_TEST_ID))
    cur.execute("DELETE FROM sport_profiles WHERE user_id IN (?, ?, ?)", (SAM_ID, MAYA_ID, JJ_ID))
    cur.execute("DELETE FROM users          WHERE id IN (?, ?, ?)",      (SAM_ID, MAYA_ID, JJ_ID))
    # Football/Soccer/Tennis seed
    clip_ids_multi = (CLIP_F_ID, CLIP_S_ID, CLIP_T_ID)
    cur.execute("DELETE FROM clips WHERE id IN (?, ?, ?)", clip_ids_multi)
    for pid in POST_F_IDS + POST_S_IDS + POST_T_IDS:
        cur.execute("DELETE FROM posts WHERE id = ?", (pid,))
    cur.execute("DELETE FROM challenges WHERE id IN (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (CHALLENGE_F1_ID, CHALLENGE_F2_ID, CHALLENGE_F3_ID,
                 CHALLENGE_S1_ID, CHALLENGE_S2_ID, CHALLENGE_S3_ID,
                 CHALLENGE_T1_ID, CHALLENGE_T2_ID, CHALLENGE_T3_ID))
    cur.execute("DELETE FROM friendships WHERE id IN (?, ?, ?)",
                (FRIENDSHIP_TEST_RJ_ID, FRIENDSHIP_TEST_SASHA_ID, FRIENDSHIP_TEST_KAI_ID))
    multi_user_ids = (RJ_ID, DALE_ID, SASHA_ID, LEO_ID, KAI_ID, PRIYA_ID)
    cur.execute("DELETE FROM sport_profiles WHERE user_id IN (?, ?, ?, ?, ?, ?)", multi_user_ids)
    cur.execute("DELETE FROM users          WHERE id IN (?, ?, ?, ?, ?, ?)",      multi_user_ids)
    # Remove test user's non-basketball profiles added by this script
    cur.execute("DELETE FROM sport_profiles WHERE user_id = ? AND sport IN ('FOOTBALL','SOCCER','TENNIS')",
                (TEST_USER_ID,))
    print("  Done.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_seed(dry_run: bool = False, reset: bool = False) -> None:
    print("=" * 60)
    print("SportsHub — Dev Seed Data  (LOCAL / DEV ONLY)")
    if dry_run:
        print("Mode: DRY RUN — no data will be written")
    elif reset:
        print("Mode: RESET + RESEED — existing seed data will be removed")
    else:
        print("Mode: IDEMPOTENT ADD — skips rows that already exist")
    print("=" * 60)

    db_path = get_sqlite_path(DATABASE_URL)
    if not os.path.exists(db_path):
        print(f"\nDatabase not found: {db_path}")
        print("Start the backend once to create the DB, then run this script.")
        return

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    # Verify test user exists before proceeding
    cur.execute("SELECT username FROM users WHERE id = ?", (TEST_USER_ID,))
    row = cur.fetchone()
    if not row:
        print(f"\nERROR: Test user {TEST_USER_ID} not found.")
        print("Log in as aarushkhanna11@gmail.com first (creates the account), then re-run.")
        conn.close()
        return
    print(f"\n  Test user confirmed: {row[0]} ({TEST_USER_ID[:8]}...)")

    if reset and not dry_run:
        reset_seed_data(cur)
        conn.commit()

    added = []
    skipped = []

    def add(label: str, dry_run: bool) -> None:
        added.append(label)
        print(f"  ADD   {label}")

    def skip(label: str) -> None:
        skipped.append(label)
        print(f"  SKIP  {label} — already exists")

    # -----------------------------------------------------------------------
    # 1. Users
    # -----------------------------------------------------------------------
    print("\n[1/8] Users")
    pw_hash = make_pw_hash()
    seed_users = [
        (SAM_ID,  "sam_hooper",   "Sam Hooper",   "sam.hooper@sportshub.dev"),
        (MAYA_ID, "maya_baller",  "Maya Baller",  "maya.baller@sportshub.dev"),
        (JJ_ID,   "jj_courtking", "JJ Courtking", "jj.courtking@sportshub.dev"),
    ]
    for uid, uname, dname, email in seed_users:
        if username_exists(cur, uname):
            skip(uname)
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO users
                        (id, email, username, password_hash, display_name,
                         date_of_birth, avatar_seed, role, account_status,
                         age_verified, is_legacy_account, created_at)
                    VALUES (?, ?, ?, ?, ?, '2003-06-15 00:00:00', ?, 'USER', 'ACTIVE', 1, 1, ?)
                """, (uid, email, uname, pw_hash, dname, uname, ts()))
            add(f"user {uname}", dry_run)

    # -----------------------------------------------------------------------
    # 2. Sport Profiles (basketball, non-provisional)
    # -----------------------------------------------------------------------
    print("\n[2/8] Sport Profiles")

    # Promote test user's existing basketball profile
    cur.execute(
        "SELECT id FROM sport_profiles WHERE user_id = ? AND sport = 'BASKETBALL'",
        (TEST_USER_ID,)
    )
    if cur.fetchone():
        if not dry_run:
            cur.execute("""
                UPDATE sport_profiles
                SET rating=1542, games_played=8, wins=5, losses=3,
                    is_provisional=0, rank_tier='silver', matches_completed=8,
                    trust_score=96.0, trust_tier='trusted'
                WHERE user_id = ? AND sport = 'BASKETBALL'
            """, (TEST_USER_ID,))
        print("  UPDATE ak_hooper BASKETBALL → rating=1542, non-provisional")
    else:
        print("  WARN   ak_hooper basketball profile not found — skipping update")

    seed_profiles = [
        # (user_id, sport, rating, games_played, wins, losses, rank_tier)
        (SAM_ID,  "BASKETBALL", 1618, 12, 8, 4, "gold"),
        (MAYA_ID, "BASKETBALL", 1480,  6, 3, 3, "silver"),
        (JJ_ID,   "BASKETBALL", 1395, 10, 4, 6, "bronze"),
    ]
    for uid, sport, rating, gp, wins, losses, tier in seed_profiles:
        if profile_exists(cur, uid, sport):
            skip(f"sport_profile {uid[:8]}... {sport}")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO sport_profiles
                        (id, user_id, sport, rating, games_played, ranked_games_played,
                         wins, losses, is_provisional, rank_tier, matches_completed,
                         trust_score, trust_tier)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 95.0, 'trusted')
                """, (str(uuid_mod.uuid4()), uid, sport, rating, gp, gp, wins, losses, tier, gp))
            add(f"sport_profile {uid[:8]}... {sport} rating={rating}", dry_run)

    # -----------------------------------------------------------------------
    # 3. Friendships
    # -----------------------------------------------------------------------
    print("\n[3/8] Friendships")
    friendships = [
        # (id, user_a, user_b, initiated_by, status, created_offset, accepted_offset)
        (FRIENDSHIP_TEST_SAM_ID,  TEST_USER_ID, SAM_ID,       TEST_USER_ID, "ACCEPTED", -10, -8),
        (FRIENDSHIP_TEST_MAYA_ID, TEST_USER_ID, MAYA_ID,      TEST_USER_ID, "ACCEPTED", -15, -12),
        (FRIENDSHIP_JJ_TEST_ID,   JJ_ID,        TEST_USER_ID, JJ_ID,        "PENDING",  -1,  None),
    ]
    for fid, ua, ub, init_by, status, c_off, a_off in friendships:
        if row_exists(cur, "friendships", fid):
            skip(f"friendship {fid[:8]}...")
        else:
            accepted_at = ts(a_off) if a_off is not None else None
            if not dry_run:
                cur.execute("""
                    INSERT INTO friendships
                        (id, user_a_id, user_b_id, initiated_by, status, created_at, accepted_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (fid, ua, ub, init_by, status, ts(c_off), accepted_at))
            add(f"friendship {ua[:8]}...↔{ub[:8]}... [{status}]", dry_run)

    # -----------------------------------------------------------------------
    # 4. Challenges
    #    Completed challenges within the last 7 days drive the activity feed.
    #    All completed challenges drive /activity/recent-matches (PerformanceGraphs).
    # -----------------------------------------------------------------------
    print("\n[4/8] Challenges")
    challenges = [
        # id, sport, match_type, challenger, opponent, status, winner,
        # rb_c (rating before challenger), ra_c (after), rb_o, ra_o,
        # created_offset, accepted_offset, completed_offset
        (
            CHALLENGE_1_ID, "BASKETBALL", "RANKED",
            TEST_USER_ID, SAM_ID, "COMPLETED", TEST_USER_ID,
            1500, 1542, 1618, 1600,
            -4, -4, -3
        ),
        (
            CHALLENGE_2_ID, "BASKETBALL", "RANKED",
            TEST_USER_ID, MAYA_ID, "COMPLETED", MAYA_ID,
            1542, 1520, 1460, 1480,
            -6, -6, -5
        ),
        (
            CHALLENGE_3_ID, "BASKETBALL", "RANKED",
            SAM_ID, JJ_ID, "COMPLETED", SAM_ID,
            1600, 1618, 1415, 1395,
            -3, -3, -2
        ),
        # Active challenge — no winner, no completed_at
        (
            CHALLENGE_4_ID, "BASKETBALL", "RANKED",
            TEST_USER_ID, JJ_ID, "ACCEPTED", None,
            1520, None, 1395, None,
            -1, -1, None
        ),
    ]
    for row_data in challenges:
        (cid, sport, mtype, chall, opp, status, winner,
         rb_c, ra_c, rb_o, ra_o,
         cr_off, ac_off, co_off) = row_data

        if row_exists(cur, "challenges", cid):
            skip(f"challenge {cid[:8]}... [{status}]")
        else:
            completed_at = ts(co_off) if co_off is not None else None
            if not dry_run:
                cur.execute("""
                    INSERT INTO challenges
                        (id, sport, match_type, challenger_id, opponent_id,
                         status, winner_id, impact_weight,
                         challenger_confirmed, opponent_confirmed,
                         challenger_rating_before, challenger_rating_after,
                         opponent_rating_before,   opponent_rating_after,
                         created_at, accepted_at, completed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 1.0, 0, 0, ?, ?, ?, ?, ?, ?, ?)
                """, (cid, sport, mtype, chall, opp, status, winner,
                      rb_c, ra_c, rb_o, ra_o,
                      ts(cr_off), ts(ac_off), completed_at))
            add(f"challenge {cid[:8]}... {chall[:8]}... vs {opp[:8]}... [{status}]", dry_run)

    # -----------------------------------------------------------------------
    # 5. Posts
    # -----------------------------------------------------------------------
    print("\n[5/8] Posts")
    posts = [
        (
            POST_IDS[0], SAM_ID, "BASKETBALL",
            "Just hit a 38-point game in pickup. New personal best — "
            "fingers crossed the improvement sticks for the rated matches.",
            -4
        ),
        (
            POST_IDS[1], MAYA_ID, "BASKETBALL",
            "Anyone else find that 1-on-1 half court improves your pull-up jumper "
            "way more than full court drills? Asking for a friend.",
            -2
        ),
        (
            POST_IDS[2], JJ_ID, "BASKETBALL",
            "First week grinding ratings on SportsHub. Lost two, won two. "
            "1395 and climbing.",
            -1
        ),
    ]
    for pid, author, sport, content, c_off in posts:
        if row_exists(cur, "posts", pid):
            skip(f"post {pid[:8]}...")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO posts
                        (id, author_id, sport, content,
                         safety_checked, moderation_status,
                         likes_count, comments_count, created_at)
                    VALUES (?, ?, ?, ?, 1, 'approved', 0, 0, ?)
                """, (pid, author, sport, content, ts(c_off)))
            add(f"post {pid[:8]}... by {author[:8]}...", dry_run)

    # -----------------------------------------------------------------------
    # 6. Clips  (records only — no video files on disk)
    #    video_url left NULL. ClipsView will show the card but video won't play.
    #    This is honest: the record exists, the file does not.
    # -----------------------------------------------------------------------
    print("\n[6/8] Clips (records only — no video file)")
    clips = [
        (CLIP_1_ID, SAM_ID,  "basketball", "Crossover highlight reel",  "Dev seed — no video file."),
        (CLIP_2_ID, MAYA_ID, "basketball", "Post move breakdown",        "Dev seed — no video file."),
    ]
    for cid, author, sport, title, desc in clips:
        if row_exists(cur, "clips", cid):
            skip(f"clip {cid[:8]}...")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO clips
                        (id, author_id, sport, title, description,
                         video_url, thumbnail_url, duration,
                         views_count, likes_count, safety_checked, created_at)
                    VALUES (?, ?, ?, ?, ?, NULL, NULL, 0, 0, 0, 1, ?)
                """, (cid, author, sport, title, desc, ts(-3)))
            add(f"clip {cid[:8]}... '{title}' (no video_url)", dry_run)

    # -----------------------------------------------------------------------
    # 7. Messages  (1 conversation: test_user ↔ sam_hooper)
    # -----------------------------------------------------------------------
    print("\n[7/8] Messages")
    messages = [
        (MSG_IDS[0], TEST_USER_ID, SAM_ID,       "Hey Sam, good game yesterday!", ts(-3)),
        (MSG_IDS[1], SAM_ID,       TEST_USER_ID, "Thanks man, your defense was tough. Rematch?", ts(-3)),
        (MSG_IDS[2], TEST_USER_ID, SAM_ID,       "100%, I'll challenge you again this week.", ts(-2)),
        (MSG_IDS[3], SAM_ID,       TEST_USER_ID, "Let's go. I'll be ready.", ts(-2)),
    ]
    for mid, sender, receiver, content, sent_at in messages:
        if row_exists(cur, "messages", mid):
            skip(f"message {mid[:8]}...")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO messages
                        (id, sender_id, receiver_id, content,
                         safety_checked, moderation_status,
                         deleted_by_sender, deleted_by_receiver, sent_at)
                    VALUES (?, ?, ?, ?, 1, 'approved', 0, 0, ?)
                """, (mid, sender, receiver, content, sent_at))
            add(f"message {mid[:8]}... from {sender[:8]}...", dry_run)

    # -----------------------------------------------------------------------
    # 8. Badges
    # -----------------------------------------------------------------------
    print("\n[8/8] Badges")
    if row_exists(cur, "user_badges", BADGE_ID):
        skip(f"badge first_win for test user")
    else:
        if not dry_run:
            cur.execute("""
                INSERT INTO user_badges
                    (id, user_id, badge_id, sport, progress, earned_at)
                VALUES (?, ?, 'first_win', 'BASKETBALL', 100, ?)
            """, (BADGE_ID, TEST_USER_ID, ts(-3)))
        add("badge first_win for test user (ak_hooper)", dry_run)

    # -----------------------------------------------------------------------
    # 9. Football + Soccer + Tennis Users
    # -----------------------------------------------------------------------
    print("\n[9/15] Multi-Sport Users (Football / Soccer / Tennis)")
    multi_users = [
        (RJ_ID,    "rj_routes",       "RJ Routes",       "rj.routes@sportshub.dev"),
        (DALE_ID,  "dale_receiver",   "Dale Receiver",   "dale.receiver@sportshub.dev"),
        (SASHA_ID, "sasha_striker",   "Sasha Striker",   "sasha.striker@sportshub.dev"),
        (LEO_ID,   "leo_dribbler",    "Leo Dribbler",    "leo.dribbler@sportshub.dev"),
        (KAI_ID,   "kai_ace",         "Kai Ace",         "kai.ace@sportshub.dev"),
        (PRIYA_ID, "priya_baseline",  "Priya Baseline",  "priya.baseline@sportshub.dev"),
    ]
    for uid, uname, dname, email in multi_users:
        if username_exists(cur, uname):
            skip(uname)
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO users
                        (id, email, username, password_hash, display_name,
                         date_of_birth, avatar_seed, role, account_status,
                         age_verified, is_legacy_account, created_at)
                    VALUES (?, ?, ?, ?, ?, '2002-09-20 00:00:00', ?, 'USER', 'ACTIVE', 1, 1, ?)
                """, (uid, email, uname, pw_hash, dname, uname, ts()))
            add(f"user {uname}", dry_run)

    # -----------------------------------------------------------------------
    # 10. Multi-Sport Profiles for new seed users
    # -----------------------------------------------------------------------
    print("\n[10/15] Multi-Sport Profiles (new seed users)")
    multi_profiles = [
        # (user_id, sport, rating, gp, wins, losses, rank_tier)
        (RJ_ID,    "FOOTBALL", 1580, 8, 5, 3, "gold"),
        (DALE_ID,  "FOOTBALL", 1420, 6, 2, 4, "silver"),
        (SASHA_ID, "SOCCER",   1560, 7, 4, 3, "gold"),
        (LEO_ID,   "SOCCER",   1450, 5, 2, 3, "silver"),
        (KAI_ID,   "TENNIS",   1600, 9, 6, 3, "gold"),
        (PRIYA_ID, "TENNIS",   1440, 6, 3, 3, "silver"),
    ]
    for uid, sport, rating, gp, wins, losses, tier in multi_profiles:
        if profile_exists(cur, uid, sport):
            skip(f"sport_profile {uid[:8]}... {sport}")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO sport_profiles
                        (id, user_id, sport, rating, games_played, ranked_games_played,
                         wins, losses, is_provisional, rank_tier, matches_completed,
                         trust_score, trust_tier)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 94.0, 'trusted')
                """, (str(uuid_mod.uuid4()), uid, sport, rating, gp, gp, wins, losses, tier, gp))
            add(f"sport_profile {uid[:8]}... {sport} rating={rating}", dry_run)

    # -----------------------------------------------------------------------
    # 11. Test user's Football / Soccer / Tennis profiles
    #     ranked_games_played >= 5 → visible on leaderboard
    # -----------------------------------------------------------------------
    print("\n[11/15] Test User Multi-Sport Profiles")
    test_multi_profiles = [
        ("FOOTBALL", 1500, 5, 3, 2, "silver"),
        ("SOCCER",   1500, 5, 2, 3, "silver"),
        ("TENNIS",   1500, 5, 2, 3, "silver"),
    ]
    for sport, rating, gp, wins, losses, tier in test_multi_profiles:
        if profile_exists(cur, TEST_USER_ID, sport):
            skip(f"test user {sport} profile")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO sport_profiles
                        (id, user_id, sport, rating, games_played, ranked_games_played,
                         wins, losses, is_provisional, rank_tier, matches_completed,
                         trust_score, trust_tier)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, 96.0, 'trusted')
                """, (str(uuid_mod.uuid4()), TEST_USER_ID, sport, rating, gp, gp, wins, losses, tier, gp))
            add(f"test user {sport} profile rating={rating}", dry_run)

    # -----------------------------------------------------------------------
    # 12. Multi-Sport Friendships (test user ↔ one user per sport)
    # -----------------------------------------------------------------------
    print("\n[12/15] Multi-Sport Friendships")
    multi_friendships = [
        (FRIENDSHIP_TEST_RJ_ID,    TEST_USER_ID, RJ_ID,    TEST_USER_ID, "ACCEPTED", -7, -6),
        (FRIENDSHIP_TEST_SASHA_ID, TEST_USER_ID, SASHA_ID, TEST_USER_ID, "ACCEPTED", -6, -5),
        (FRIENDSHIP_TEST_KAI_ID,   TEST_USER_ID, KAI_ID,   TEST_USER_ID, "ACCEPTED", -5, -4),
    ]
    for fid, ua, ub, init_by, status, c_off, a_off in multi_friendships:
        if row_exists(cur, "friendships", fid):
            skip(f"friendship {fid[:8]}...")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO friendships
                        (id, user_a_id, user_b_id, initiated_by, status, created_at, accepted_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (fid, ua, ub, init_by, status, ts(c_off), ts(a_off)))
            add(f"friendship {ua[:8]}...↔{ub[:8]}... [{status}]", dry_run)

    # -----------------------------------------------------------------------
    # 13. Multi-Sport Challenges
    # -----------------------------------------------------------------------
    print("\n[13/15] Multi-Sport Challenges")
    multi_challenges = [
        # Football
        (
            CHALLENGE_F1_ID, "FOOTBALL", "RANKED",
            RJ_ID, DALE_ID, "COMPLETED", RJ_ID,
            1560, 1580, 1440, 1420,
            -6, -6, -5
        ),
        (
            CHALLENGE_F2_ID, "FOOTBALL", "RANKED",
            RJ_ID, TEST_USER_ID, "ACCEPTED", None,
            1580, None, 1500, None,
            -1, -1, None
        ),
        # Soccer
        (
            CHALLENGE_S1_ID, "SOCCER", "RANKED",
            SASHA_ID, LEO_ID, "COMPLETED", SASHA_ID,
            1540, 1560, 1470, 1450,
            -5, -5, -4
        ),
        (
            CHALLENGE_S2_ID, "SOCCER", "RANKED",
            SASHA_ID, TEST_USER_ID, "ACCEPTED", None,
            1560, None, 1500, None,
            -1, -1, None
        ),
        # Tennis
        (
            CHALLENGE_T1_ID, "TENNIS", "RANKED",
            KAI_ID, PRIYA_ID, "COMPLETED", KAI_ID,
            1580, 1600, 1460, 1440,
            -4, -4, -3
        ),
        (
            CHALLENGE_T2_ID, "TENNIS", "RANKED",
            KAI_ID, TEST_USER_ID, "ACCEPTED", None,
            1600, None, 1500, None,
            -1, -1, None
        ),
        # Completed challenges involving test user (drives recent-matches per sport)
        (
            CHALLENGE_F3_ID, "FOOTBALL", "RANKED",
            TEST_USER_ID, RJ_ID, "COMPLETED", TEST_USER_ID,
            1480, 1500, 1600, 1580,
            -8, -8, -7
        ),
        (
            CHALLENGE_S3_ID, "SOCCER", "RANKED",
            TEST_USER_ID, SASHA_ID, "COMPLETED", SASHA_ID,
            1520, 1500, 1540, 1560,
            -7, -7, -6
        ),
        (
            CHALLENGE_T3_ID, "TENNIS", "RANKED",
            TEST_USER_ID, PRIYA_ID, "COMPLETED", TEST_USER_ID,
            1480, 1500, 1460, 1440,
            -6, -6, -5
        ),
    ]
    for row_data in multi_challenges:
        (cid, sport, mtype, chall, opp, status, winner,
         rb_c, ra_c, rb_o, ra_o,
         cr_off, ac_off, co_off) = row_data

        if row_exists(cur, "challenges", cid):
            skip(f"challenge {cid[:8]}... [{status}]")
        else:
            completed_at = ts(co_off) if co_off is not None else None
            if not dry_run:
                cur.execute("""
                    INSERT INTO challenges
                        (id, sport, match_type, challenger_id, opponent_id,
                         status, winner_id, impact_weight,
                         challenger_confirmed, opponent_confirmed,
                         challenger_rating_before, challenger_rating_after,
                         opponent_rating_before,   opponent_rating_after,
                         created_at, accepted_at, completed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 1.0, 0, 0, ?, ?, ?, ?, ?, ?, ?)
                """, (cid, sport, mtype, chall, opp, status, winner,
                      rb_c, ra_c, rb_o, ra_o,
                      ts(cr_off), ts(ac_off), completed_at))
            add(f"challenge {cid[:8]}... {sport} {chall[:8]}... vs {opp[:8]}... [{status}]", dry_run)

    # -----------------------------------------------------------------------
    # 14. Multi-Sport Posts
    # -----------------------------------------------------------------------
    print("\n[14/15] Multi-Sport Posts")
    multi_posts = [
        (
            POST_F_IDS[0], RJ_ID, "FOOTBALL",
            "Route breaks felt sharper today after focusing on my plant foot. "
            "Small adjustment, big difference.",
            -4
        ),
        (
            POST_F_IDS[1], DALE_ID, "FOOTBALL",
            "Catching with my hands instead of letting the ball hit my chest — "
            "finally clicking after weeks of drills.",
            -2
        ),
        (
            POST_S_IDS[0], SASHA_ID, "SOCCER",
            "Weak-foot passing is rough but I completed more reps today "
            "than any session this month. Progress is progress.",
            -3
        ),
        (
            POST_S_IDS[1], LEO_ID, "SOCCER",
            "First touch felt cleaner once I slowed down and stopped rushing the trap. "
            "Patience is the drill.",
            -1
        ),
        (
            POST_T_IDS[0], KAI_ID, "TENNIS",
            "Second serve felt more reliable after slowing down my toss. "
            "Consistency > pace every time.",
            -2
        ),
        (
            POST_T_IDS[1], PRIYA_ID, "TENNIS",
            "Footwork made the biggest difference in today's rally drill — "
            "moving early instead of reacting late.",
            -1
        ),
    ]
    for pid, author, sport, content, c_off in multi_posts:
        if row_exists(cur, "posts", pid):
            skip(f"post {pid[:8]}...")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO posts
                        (id, author_id, sport, content,
                         safety_checked, moderation_status,
                         likes_count, comments_count, created_at)
                    VALUES (?, ?, ?, ?, 1, 'approved', 0, 0, ?)
                """, (pid, author, sport, content, ts(c_off)))
            add(f"post {pid[:8]}... {sport} by {author[:8]}...", dry_run)

    # -----------------------------------------------------------------------
    # 15. Multi-Sport Clips  (records only — no video files on disk)
    # -----------------------------------------------------------------------
    print("\n[15/15] Multi-Sport Clips (records only — no video file)")
    multi_clips = [
        (CLIP_F_ID, RJ_ID,    "football", "Route running reel",         "Dev seed — no video file."),
        (CLIP_S_ID, SASHA_ID, "soccer",   "Striker finishing drills",   "Dev seed — no video file."),
        (CLIP_T_ID, KAI_ID,   "tennis",   "Serve technique breakdown",  "Dev seed — no video file."),
    ]
    for cid, author, sport, title, desc in multi_clips:
        if row_exists(cur, "clips", cid):
            skip(f"clip {cid[:8]}...")
        else:
            if not dry_run:
                cur.execute("""
                    INSERT INTO clips
                        (id, author_id, sport, title, description,
                         video_url, thumbnail_url, duration,
                         views_count, likes_count, safety_checked, created_at)
                    VALUES (?, ?, ?, ?, ?, NULL, NULL, 0, 0, 0, 1, ?)
                """, (cid, author, sport, title, desc, ts(-2)))
            add(f"clip {cid[:8]}... {sport} '{title}' (no video_url)", dry_run)

    # -----------------------------------------------------------------------
    # Commit
    # -----------------------------------------------------------------------
    if not dry_run:
        conn.commit()
    conn.close()

    print("\n" + "=" * 60)
    print(f"Added:   {len(added)} row(s)")
    print(f"Skipped: {len(skipped)} row(s)")
    print("=" * 60)
    if not dry_run and added:
        print("\nTest user:   aarushkhanna11@gmail.com  (existing password)")
        print("Basketball:  sam.hooper@sportshub.dev")
        print("             maya.baller@sportshub.dev")
        print("             jj.courtking@sportshub.dev")
        print("Football:    rj.routes@sportshub.dev")
        print("             dale.receiver@sportshub.dev")
        print("Soccer:      sasha.striker@sportshub.dev")
        print("             leo.dribbler@sportshub.dev")
        print("Tennis:      kai.ace@sportshub.dev")
        print("             priya.baseline@sportshub.dev")
        print("All seed user password: SportsHub123!")
    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SportsHub local/dev seed data")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview changes without writing to DB")
    parser.add_argument("--reset", action="store_true",
                        help="Remove all seed data before seeding (DESTRUCTIVE)")
    args = parser.parse_args()
    run_seed(dry_run=args.dry_run, reset=args.reset)
