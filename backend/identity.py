"""
Canonical identity helpers (Gate 1.2).

Single source of truth for:
  - email normalization (used at every persistence + lookup boundary)
  - the 13+ age gate (shared by local signup and OAuth first-time onboarding)
  - OAuth provider-name canonicalization

Age is computed with a calendar-EXACT whole-year rule (NOT a days/365.25
approximation) so the 13+ boundary is correct to the day — the same foundation
Gate 1.5 reuses for 17->18 transitions. Keep this tiny and dependency-light so
models.py can import it without cycles.
"""
from datetime import date, datetime

MIN_AGE_YEARS = 13


def normalize_email(email: str | None) -> str | None:
    """Canonical form of an email for identity/account use: trimmed + lowercased.

    Returns None only for None input. Callers that require a value should validate
    non-empty separately. This is the ONE authority — do not lowercase ad hoc.
    """
    if email is None:
        return None
    return email.strip().lower()


def canonical_provider(provider: str | None) -> str:
    """Lowercase/trim an OAuth provider name (e.g. 'Apple' -> 'apple')."""
    return (provider or "").strip().lower()


def _as_date(value) -> date:
    """Coerce a date or (naive/aware) datetime to a plain calendar date."""
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    raise TypeError(f"expected date/datetime, got {type(value)!r}")


def calendar_age(dob, *, today: "date | datetime | None" = None) -> int:
    """Whole-year calendar age. `today` is injectable for deterministic tests.

    Rule: years since birth, minus one if this year's birthday has not occurred
    yet (month/day comparison). A Feb-29 date of birth is treated as having its
    birthday on Mar-1 in non-leap years — there is no Feb-29 to reach — which this
    month/day tuple comparison yields naturally (asserted in tests).
    """
    d = _as_date(dob)
    ref = _as_date(today) if today is not None else date.today()
    had_birthday_this_year = (ref.month, ref.day) >= (d.month, d.day)
    return ref.year - d.year - (0 if had_birthday_this_year else 1)


def is_valid_signup_dob(dob, *, today: "date | datetime | None" = None) -> bool:
    """True iff dob is a real, non-future date and the person is at least 13 by
    calendar-EXACT age.

    Shared by local signup (routers/auth.py) and OAuth first-time onboarding
    (routers/oauth.py) so the age boundary is byte-for-byte identical everywhere.
    """
    if dob is None:
        return False
    d = _as_date(dob)
    ref = _as_date(today) if today is not None else date.today()
    if d > ref:                     # future DOB is invalid
        return False
    return calendar_age(d, today=ref) >= MIN_AGE_YEARS
