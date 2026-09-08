"""Gate 1.3 — existing-database upgrade (create auth_attempts) evidence.

Exercises the smallest additive dev transition on a DISPOSABLE database representing the
frozen parent schema (all tables EXCEPT auth_attempts, plus a real user + identity):
  - upgrade creates auth_attempts without losing users/identities;
  - repeating it is a safe no-op;
  - the attempt row works afterward;
  - a failure mid-transition leaves NO partially-applied state (transactional DDL rollback).
SQLite only; production Postgres/Alembic is Gate 2.1A. Never touches the real dev DB.

Run from backend/:  ../.venv/bin/python -m unittest tests.test_gate13_migration -v
"""
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import sessionmaker

from database import Base
import models
import models_premium  # noqa: F401
from migrate_gate12_identity import enable_sqlite_transactional_ddl
from migrate_gate13_auth_attempts import _ensure_auth_attempts


def _frozen_parent_engine():
    """A DB at the pre-Gate-1.3 shape: every table EXCEPT auth_attempts, with data."""
    fd, path = tempfile.mkstemp(suffix=".db"); os.close(fd)
    eng = create_engine(f"sqlite:///{path}", connect_args={"check_same_thread": False})
    Base.metadata.create_all(eng)
    # Simulate the frozen parent: drop the new table, keep everything else.
    with eng.begin() as c:
        c.execute(text("DROP TABLE IF EXISTS auth_attempts"))
    db = sessionmaker(bind=eng)()
    u = models.User(email="keep@x.com", username="keepme", password_hash="x",
                    display_name="Keep", date_of_birth=datetime(2000, 1, 1))
    db.add(u); db.flush()
    db.add(models.AuthIdentity(user_id=u.id, provider="apple", subject="KEEP-SUB"))
    db.commit(); db.close()
    enable_sqlite_transactional_ddl(eng); eng.dispose()   # transactional DDL for new conns
    return eng, path


class Gate13MigrationTests(unittest.TestCase):
    def setUp(self):
        self.eng, self.path = _frozen_parent_engine()

    def tearDown(self):
        self.eng.dispose(); os.remove(self.path)

    def _tables(self):
        with self.eng.connect() as c:
            return set(inspect(c).get_table_names())

    def test_upgrade_creates_table_and_preserves_data(self):
        self.assertNotIn("auth_attempts", self._tables())     # pre-state
        with self.eng.begin() as c:
            self.assertTrue(_ensure_auth_attempts(c))         # created
        self.assertIn("auth_attempts", self._tables())
        db = sessionmaker(bind=self.eng)()
        try:
            self.assertEqual(db.query(models.User).filter(models.User.email == "keep@x.com").count(), 1)
            self.assertEqual(db.query(models.AuthIdentity).filter_by(subject="KEEP-SUB").count(), 1)
        finally:
            db.close()

    def test_repeat_is_safe_noop(self):
        with self.eng.begin() as c:
            self.assertTrue(_ensure_auth_attempts(c))
        with self.eng.begin() as c:
            self.assertFalse(_ensure_auth_attempts(c))        # idempotent no-op
        self.assertIn("auth_attempts", self._tables())

    def test_attempt_row_works_after_upgrade(self):
        with self.eng.begin() as c:
            _ensure_auth_attempts(c)
        db = sessionmaker(bind=self.eng)()
        try:
            a = models.AuthAttempt(provider="apple", nonce="n",
                                   status=models.AuthAttemptStatus.PENDING,
                                   expires_at=datetime.utcnow() + timedelta(minutes=10))
            db.add(a); db.commit(); db.refresh(a)
            self.assertEqual(a.status, models.AuthAttemptStatus.PENDING)
        finally:
            db.close()

    def test_failure_mid_transition_leaves_no_partial(self):
        try:
            with self.eng.begin() as c:
                _ensure_auth_attempts(c)          # creates the table within the txn
                raise RuntimeError("boom after create, before commit")
        except RuntimeError:
            pass
        # Transactional DDL must have rolled the CREATE back — no partially-applied table.
        self.assertNotIn("auth_attempts", self._tables())
        # And no data was harmed.
        db = sessionmaker(bind=self.eng)()
        try:
            self.assertEqual(db.query(models.User).count(), 1)
        finally:
            db.close()


if __name__ == "__main__":
    unittest.main()
