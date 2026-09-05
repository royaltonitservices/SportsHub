"""
Gate 1.2 development-only schema transition (NOT a production migration framework —
Alembic arrives in Gate 2.1A). Idempotent and fail-closed.

Brings an EXISTING dev SQLite database to the Gate 1.2 identity schema:
  1. PREFLIGHT: abort BEFORE any change if duplicate normalized emails exist
     (never deletes or merges users — a human must resolve conflicts).
  2. Create the `auth_identities` table (UNIQUE(provider, subject)) if missing.
  3. BACKFILL: rewrite any legacy stored email that isn't already trim+lower
     canonical, so pre-validator rows match normalized lookups. Safe only after
     preflight proved no two rows collide once normalized.
  4. Add a UNIQUE index on users.email if missing (safe — preflight proved no dups).
  5. Relax users.password_hash NOT NULL -> nullable via a guarded, transactional
     table rebuild that copies all rows (only when still NOT NULL).

A FRESH database created by Base.metadata.create_all() already has all of the above;
this script only transitions a pre-existing dev DB. Run:  python migrate_gate12_identity.py
"""
import sys
from sqlalchemy import inspect, text, event
from database import engine, Base
import models  # noqa: F401 — registers all tables (User, AuthIdentity, ...) on Base
from identity import normalize_email  # the ONE canonicalization authority


def enable_sqlite_transactional_ddl(eng) -> None:
    """Make pysqlite honor transactions AROUND DDL so a mid-transition failure rolls
    back fully.

    By default SQLAlchemy's pysqlite driver implicitly COMMITs any open transaction
    before a DDL statement (CREATE/ALTER/DROP), which would leave a half-applied
    schema if a later step fails — so `engine.begin()` alone is NOT atomic here. This
    is SQLAlchemy's documented recipe: disable the driver's implicit BEGIN/COMMIT and
    emit BEGIN ourselves so CREATE/RENAME/DROP participate in the transaction and roll
    back on error. Idempotent per engine; new connections pick it up (call before use,
    or dispose the pool after registering).
    """
    if getattr(eng, "_gate12_txn_ddl", False):
        return

    @event.listens_for(eng, "connect")
    def _no_implicit_commit(dbapi_conn, _record):  # noqa: ARG001
        dbapi_conn.isolation_level = None

    @event.listens_for(eng, "begin")
    def _explicit_begin(conn):
        conn.exec_driver_sql("BEGIN")

    eng._gate12_txn_ddl = True


def _preflight_duplicate_emails(conn) -> None:
    rows = conn.execute(text(
        "SELECT lower(trim(email)) e, COUNT(*) c FROM users GROUP BY e HAVING c > 1"
    )).fetchall()
    if rows:
        print("ABORT (preflight): duplicate normalized emails exist — resolve manually first:")
        for e, c in rows:
            print(f"  {e!r}: {c} rows")
        print("No schema changes were made. This script never deletes or merges users.")
        sys.exit(1)
    print("Preflight OK: 0 duplicate normalized emails.")


def _canonicalize_existing_emails(conn) -> int:
    """Rewrite any stored email not already in trim+lower canonical form.

    Legacy rows written before the model's email @validates ran (or copied via the
    raw INSERT...SELECT rebuild, which bypasses the ORM) can hold non-canonical
    values like 'Bob@Example.COM'. Every lookup now normalizes, so such a row would
    never match and its owner could not sign in. This rewrites them in place.

    Safe ONLY after `_preflight_duplicate_emails` proved no two rows share a
    normalized form — so no UPDATE here can collide on the unique email constraint.
    Returns the number of rows changed (0 on a clean/idempotent re-run).
    """
    rows = conn.execute(text("SELECT id, email FROM users")).fetchall()
    changed = 0
    for uid, email in rows:
        canon = normalize_email(email)
        if canon is not None and canon != email:
            conn.execute(
                text("UPDATE users SET email = :e WHERE id = :i"),
                {"e": canon, "i": uid},
            )
            changed += 1
    print(f"users.email: canonicalized {changed} legacy row(s).")
    return changed


def _ensure_auth_identities(conn) -> None:
    insp = inspect(conn)
    if "auth_identities" in insp.get_table_names():
        print("auth_identities: already present.")
        return
    models.AuthIdentity.__table__.create(bind=conn, checkfirst=True)
    print("auth_identities: created (UNIQUE(provider, subject)).")


def _ensure_unique_email_index(conn) -> None:
    insp = inspect(conn)
    idx_names = {ix["name"] for ix in insp.get_indexes("users")}
    already_unique = any(ix["unique"] and ix["column_names"] == ["email"] for ix in insp.get_indexes("users"))
    if already_unique:
        print("users.email: unique index already present.")
        return
    conn.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email ON users(email)"))
    print("users.email: UNIQUE index created.")


def _relax_password_hash_nullable(conn) -> None:
    """Rebuild users so password_hash is nullable. Must run inside a transaction
    owned by the caller (e.g. `with engine.begin() as conn:`) so a failure rolls the
    whole rebuild back — never leaving a partial schema."""
    cols = {c["name"]: c for c in inspect(conn).get_columns("users")}
    if cols["password_hash"]["nullable"]:
        print("users.password_hash: already nullable.")
        return
    # SQLite cannot ALTER a column's NOT NULL — rebuild from the model schema
    # (authoritative: nullable password_hash + unique email) and copy every row.
    print("users.password_hash: NOT NULL -> nullable (guarded table rebuild)...")
    common = [name for name in cols.keys()
              if name in {c.name for c in models.User.__table__.columns}]
    collist = ", ".join(common)
    conn.execute(text("ALTER TABLE users RENAME TO users_old"))
    # RENAME carries the old named indexes to users_old; drop them so the model's
    # CREATE TABLE (which re-declares ix_users_email + the unique autoindex) does not
    # collide in SQLite's global index namespace.
    moved = conn.execute(text(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='users_old' "
        "AND name NOT LIKE 'sqlite_autoindex%'"
    )).fetchall()
    for (idxname,) in moved:
        conn.execute(text(f'DROP INDEX IF EXISTS "{idxname}"'))
    models.User.__table__.create(bind=conn)  # new schema (nullable pw, unique email)
    conn.execute(text(f"INSERT INTO users ({collist}) SELECT {collist} FROM users_old"))
    conn.execute(text("DROP TABLE users_old"))
    print("  rebuild complete; rows preserved.")


def main() -> None:
    # Enable transactional DDL FIRST so the single transaction below is genuinely
    # atomic (pysqlite would otherwise implicitly commit before each CREATE/ALTER/DROP).
    enable_sqlite_transactional_ddl(engine)
    # One transaction for the whole transition: any failure (incl. preflight SystemExit)
    # rolls back with NO partial schema left behind.
    with engine.begin() as conn:
        if "users" not in inspect(conn).get_table_names():
            print("No `users` table — fresh DB. Run the app / create_all() instead.")
            return
        _preflight_duplicate_emails(conn)
        _ensure_auth_identities(conn)
        # Canonicalize legacy rows BEFORE the rebuild copies them and BEFORE the
        # unique index is enforced (preflight already guaranteed collision-free).
        _canonicalize_existing_emails(conn)
        # Rebuild first (it re-establishes unique email via the model schema); then the
        # index helper is a no-op. For an already-nullable DB, only the index helper runs.
        _relax_password_hash_nullable(conn)
        _ensure_unique_email_index(conn)
        print("Gate 1.2 dev transition complete.")


if __name__ == "__main__":
    main()
