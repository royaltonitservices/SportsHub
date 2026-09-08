"""Gate 1.3 dev transition — create the `auth_attempts` table on an EXISTING database.

Smallest safe, repeatable, ADDITIVE-ONLY transition: it creates one new table and never
touches existing tables or data. Idempotent (checkfirst) and atomic (transactional DDL,
reusing the Gate 1.2 helper) so a failure leaves NO partially-applied state. Formal Alembic
migrations remain Gate 2.1A.

Note: the app's startup `init_db()` already calls `Base.metadata.create_all()`, which is
additive and would also create this missing table on the next boot. This script exists for
an explicit, testable, boot-independent upgrade of a running/existing database.

Run from backend/:  python migrate_gate13_auth_attempts.py
"""
from sqlalchemy import inspect
from database import engine
import models  # noqa: F401 — registers AuthAttempt on Base
from migrate_gate12_identity import enable_sqlite_transactional_ddl


def _ensure_auth_attempts(conn) -> bool:
    if "auth_attempts" in inspect(conn).get_table_names():
        print("auth_attempts: already present (no-op).")
        return False
    models.AuthAttempt.__table__.create(bind=conn, checkfirst=True)
    print("auth_attempts: created.")
    return True


def main() -> None:
    enable_sqlite_transactional_ddl(engine)   # SQLite transactional DDL -> rollback-safe
    with engine.begin() as conn:
        if "users" not in inspect(conn).get_table_names():
            print("No `users` table — fresh DB. Run the app / init_db() instead.")
            return
        _ensure_auth_attempts(conn)
    print("Gate 1.3 dev transition complete.")


if __name__ == "__main__":
    main()
