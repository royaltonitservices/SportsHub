"""
AI Coach usage policy for SportsHub.

Product rule (the ONLY AI Coach quota — no burst / per-minute / per-10-minute /
rolling-window / concurrency / free-tier quotas):

    A Premium AI Coach user may send up to 200 user-visible AI Coach messages
    per calendar day (UTC). Message 201 is rejected BEFORE any model call.

Counting semantics:
  - One ACCEPTED user message counts at most once, regardless of how many
    internal operations (source retrieval, transport retry, one bounded semantic
    repair, escalation-model use) occur while producing the reply.
  - A request that produces a user-visible reply (including a safe deterministic
    fallback after provider failure) counts.
  - A request that fails entirely with NO user-visible reply must NOT permanently
    consume a slot — the caller reserves, then releases on total failure.
  - Auth failures, non-Premium rejections, and malformed pre-AI requests never
    reach the reservation and so never consume quota.

STORAGE (honest scope):
  LOCAL / DEV — the shipped in-memory counter is single-process; it resets when
                the backend process restarts.
  PRODUCTION  — a multi-instance deployment MUST back this with a shared store
                (e.g. Redis). The `reserve`/`release` interface lets the storage
                be swapped without touching the router or orchestrator.

No content and no identity beyond the user id key is stored.
"""
from __future__ import annotations

import threading
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Dict, Optional, Protocol, Tuple

# Central, single knob. Import-time default; the router reads it from settings so
# it can be tuned per-environment without code changes.
DEFAULT_DAILY_MESSAGE_LIMIT = 200


@dataclass(frozen=True)
class DailyLimitDecision:
    allowed: bool
    remaining: int
    limit: int
    reset_epoch: int            # unix seconds at next UTC midnight (day boundary)
    reason: Optional[str] = None
    retry_after_s: Optional[int] = None


def _utc_day_key(now: Optional[datetime] = None) -> str:
    now = now or datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%d")


def _seconds_until_utc_midnight(now: Optional[datetime] = None) -> int:
    now = now or datetime.now(timezone.utc)
    tomorrow = now.date().toordinal() + 1
    midnight = datetime.fromordinal(tomorrow).replace(tzinfo=timezone.utc)
    return max(1, int((midnight - now).total_seconds()))


class AIDailyLimiter(Protocol):
    def reserve(self, user_id: str, limit: int) -> DailyLimitDecision: ...
    def release(self, user_id: str) -> None: ...
    def peek(self, user_id: str, limit: int) -> DailyLimitDecision: ...


class InMemoryDailyLimiter:
    """Single-process per-user daily counter (UTC day). See module docstring for
    the production caveat. Thread-safe within one process."""

    def __init__(self):
        self._lock = threading.Lock()
        # (user_id, utc_day) -> count of accepted user-visible messages
        self._counts: Dict[Tuple[str, str], int] = {}

    def reserve(self, user_id: str, limit: int) -> DailyLimitDecision:
        """Atomically check the daily allowance and, if under the limit, reserve
        one slot. Reserve BEFORE any model call. Call `release` if the request
        ends up producing no user-visible reply."""
        day = _utc_day_key()
        reset = _seconds_until_utc_midnight()
        with self._lock:
            used = self._counts.get((user_id, day), 0)
            if used >= limit:
                return DailyLimitDecision(False, 0, limit,
                                          int(datetime.now(timezone.utc).timestamp()) + reset,
                                          reason="daily_limit", retry_after_s=reset)
            self._counts[(user_id, day)] = used + 1
            return DailyLimitDecision(True, limit - (used + 1), limit,
                                      int(datetime.now(timezone.utc).timestamp()) + reset)

    def release(self, user_id: str) -> None:
        """Return the reserved slot when a request produced no user-visible reply
        (e.g. an unhandled server error). Never drops below zero."""
        day = _utc_day_key()
        with self._lock:
            used = self._counts.get((user_id, day), 0)
            if used > 0:
                self._counts[(user_id, day)] = used - 1

    def peek(self, user_id: str, limit: int) -> DailyLimitDecision:
        day = _utc_day_key()
        reset = _seconds_until_utc_midnight()
        with self._lock:
            used = self._counts.get((user_id, day), 0)
        allowed = used < limit
        return DailyLimitDecision(allowed, max(0, limit - used), limit,
                                  int(datetime.now(timezone.utc).timestamp()) + reset,
                                  reason=None if allowed else "daily_limit",
                                  retry_after_s=None if allowed else reset)


# Process-wide singleton for local/dev enforcement.
ai_daily_limiter: AIDailyLimiter = InMemoryDailyLimiter()
