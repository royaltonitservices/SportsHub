"""Gate 1.4D — shared deterministic server-side text policy.

Single source of truth for "is this user-authored free text allowed to be persisted?".
It is a NARROW, RULE-BASED, PURE-PYTHON gate — NO OpenAI, NO network, NO external provider,
for any user of any age. It runs BEFORE persistence on create AND edit; on a violation the
caller rejects the whole write with a stable, non-sensitive message.

WHAT IT DETECTS
    A small, explicit set of clearly-objectionable base terms (strong sexual profanity + a
    curated set of unambiguous hate slurs). Matching is boundary-anchored and tolerant of the
    common lightweight evasions:
      - case (casefold) and Unicode presentation (NFKC; full-width / compatibility forms),
      - zero-width / invisible format characters and soft hyphens (stripped),
      - single-character "leet" confusables (a=@4, s=$5, i=1!, o=0, e=3, t=7+, ...),
      - a BOUNDED run of separators between letters ("f.u.c.k", "s h i t", "f*u*c*k").
    Each term is matched only at word boundaries, so it is NOT indiscriminate substring
    matching — "class", "grass", "assassin", "Scunthorpe", "cockpit", "analysis", "pass"
    do not trip the filter.

WHAT IT CANNOT DETECT (documented, not comprehensive semantic safety)
    - Meaning/harassment/threats/bullying expressed with ordinary words.
    - Novel spellings, heavy homoglyph substitution, spacing beyond the bounded separator run,
      or terms not on the curated list.
    - Context ("you played like garbage" is allowed; targeted abuse in clean words is allowed).
    - Non-English objectionable content beyond the curated list.
    This is a deterministic FIRST LINE that raises the floor; it is not a moderator and does
    not certify content as "safe" (see moderation_status/safety_checked — untouched here).

PRIVACY
    Never logs the rejected text and never returns the matched term. A verdict carries only a
    stable machine code.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Optional

# Hard cap on how much text this policy will evaluate. Callers should also enforce their own
# field length limits; this is a defense-in-depth bound so an unbounded field (e.g. a multipart
# Form description) cannot hand the matcher a pathological input.
MAX_TEXT_LEN = 5000

# Stable, non-sensitive public codes (safe to surface to clients / map to HTTP detail strings).
CODE_OK = "ok"
CODE_BLOCKED = "blocked_language"
CODE_TOO_LONG = "too_long"

_PUBLIC_MESSAGES = {
    CODE_BLOCKED: "This text contains language that isn't allowed. Please edit it and try again.",
    CODE_TOO_LONG: "This text is too long.",
}


@dataclass(frozen=True)
class Verdict:
    """Result of evaluating a single text value. Carries NO matched term and NO input text."""
    allowed: bool
    code: str

    @property
    def message(self) -> str:
        return _PUBLIC_MESSAGES.get(self.code, "This text can't be accepted.")


# ── curated base terms ────────────────────────────────────────────────────────────────────
# Intentionally NARROW and English-centric. Ambiguous mild/benign-collision words (e.g. "ass",
# "dick", "cock", "hell", "damn", "sex") are DELIBERATELY excluded to protect real names and
# sports vocabulary; compounds that are unambiguous ("asshole", "dickhead") are included.
# STEM terms match as a word prefix (catch inflections: fuck/fucker/fucking) — only for stems
# with negligible benign-prefix collisions. WHOLE terms require both word boundaries.
# NOTE: this list is a starting floor, not a comprehensive lexicon; production should expand it
# under review. It is the ONLY place base terms live.
_STEM_TERMS = [
    "fuck", "shit", "cunt", "bitch", "bastard", "whore", "slut",
    "asshole", "dickhead", "motherfucker", "wanker",
]

# Unambiguous hate slurs (kept minimal here; expand under review). Matched WHOLE-WORD ONLY (no
# prefix continuation) so benign look-alikes never trip — e.g. "niggardly" does not match "nigga".
# DELIBERATELY EXCLUDED for false-positive safety (they collide with common benign words and need
# a context-aware classifier, which is out of scope): "chink" (chink in the armor), "spic"
# (spicy / spick-and-span), "retard" (retardant / retardation / musical retard).
_SLUR_TERMS = [
    "nigger", "nigga", "faggot", "kike",
]

# Single-character confusable classes. Each maps a base letter to a regex character class
# covering the letter plus its common leet/symbol substitutes.
_LEET = {
    "a": "a4@",
    "b": "b8",
    "c": "c(",
    "e": "e3",
    "g": "g9",
    "i": "i1!",
    "l": "l1|",
    "o": "o0",
    "s": "s5$",
    "t": "t7+",
    "u": "uv",
}

# Bounded separator run allowed BETWEEN letters of a term (spaces/punct that survived
# normalization). Bounded to {0,3} so this stays "common separator evasion", not arbitrary.
_SEP = r"[\s._\-*+~,/\\]{0,3}"

# Word-boundary lookarounds treat only ASCII letters as "word" chars, so a trailing digit or
# symbol still ends a token ("fuck123" is caught; "class" is not, because the char before "ass"
# would be a letter).
_LEFT = r"(?<![a-z])"
_RIGHT = r"(?![a-z])"

# Small, explicit inflection set appended to slur whole-words (kept tight to avoid collisions).
_SLUR_SUFFIX = r"(?:s|es|z)?"
# Explicit inflection set for profanity stems. A TIGHT allow-list (not "any letters") so a stem
# followed by an unrelated tail does NOT match: e.g. "shiitake"/"shitake" never trip "shit",
# while "fucking"/"fucker"/"bitches" do. The trailing word boundary is still required.
_STEM_SUFFIX = (
    r"(?:er|ers|ing|ings|in|ings|ed|s|es|y|ies|hole|holes|head|heads|"
    r"face|faces|bag|bags|tard|tards)?"
)


def _atom(cls: str, quant: str) -> str:
    """Build a regex atom from a confusable class string with the given quantifier."""
    if len(cls) > 1 and not cls.startswith("\\"):
        return f"[{cls}]{quant}"
    return f"{cls}{quant}"


def _letter_atom(ch: str) -> str:
    """One base letter, its confusable class, allowing character repetition (fuuuck)."""
    return _atom(_LEET.get(ch, re.escape(ch)), "+")


def _letter_atom_single(ch: str) -> str:
    """One base letter, its confusable class, EXACTLY ONE occurrence (no repetition)."""
    return _atom(_LEET.get(ch, re.escape(ch)), "")


def _term_core(term: str) -> str:
    """Obfuscation-tolerant core: letters in order, each repeatable, separated by a bounded run."""
    return _SEP.join(_letter_atom(c) for c in term)


def _term_core_norepeat(term: str) -> str:
    """Core with NO letter repetition — so a doubled inner letter in a benign word ("shiitake")
    cannot be absorbed and mis-matched as the stem."""
    return _SEP.join(_letter_atom_single(c) for c in term)


def _compile_patterns() -> list[re.Pattern]:
    patterns: list[re.Pattern] = []
    # STEM terms (strong profanity, no benign-prefix collisions) get TWO patterns:
    #   1. whole-word / elongated / inflected: left+right boundaries, repetition, tight suffix set
    #      → "fuck", "fuuuck", "fucker", "fucking", "bitches", "s h i t".
    #   2. prefix + free continuation, NO letter repetition → catches concatenations like
    #      "fuckyou" / "shithead" while the no-repeat rule keeps "shiitake" safe and the LEFT
    #      boundary keeps the Scunthorpe family ("class", "assassin") safe.
    for t in _STEM_TERMS:
        patterns.append(re.compile(_LEFT + _term_core(t) + _STEM_SUFFIX + _RIGHT))
        patterns.append(re.compile(_LEFT + _term_core_norepeat(t) + r"[a-z]*"))
    # SLUR terms: WHOLE-WORD ONLY (both boundaries + tight suffix); never prefix-continued, so
    # benign look-alikes ("niggardly") do not match.
    for t in _SLUR_TERMS:
        patterns.append(re.compile(_LEFT + _term_core(t) + _SLUR_SUFFIX + _RIGHT))
    return patterns


_PATTERNS = _compile_patterns()

# Unicode format/zero-width characters to strip before matching (category Cf) plus soft hyphen.
_ZERO_WIDTH = {"­", "​", "‌", "‍", "⁠", "﻿"}


def _normalize(value: str) -> str:
    """Normalize FOR EVALUATION ONLY (the stored/returned text is never mutated)."""
    # NFKC folds full-width / compatibility presentation forms to their canonical letters.
    text = unicodedata.normalize("NFKC", value)
    # Drop zero-width / invisible format characters and combining marks used to break up words.
    text = "".join(
        ch for ch in text
        if ch not in _ZERO_WIDTH and unicodedata.category(ch) not in ("Cf", "Mn")
    )
    return text.casefold()


def evaluate(value: Optional[str], *, max_len: int = MAX_TEXT_LEN) -> Verdict:
    """Evaluate a single free-text value. Pure and deterministic.

    Empty / whitespace-only / None is allowed (optional fields). Over-length is rejected before
    any matching work. Returns a Verdict with a stable code and NO sensitive data.
    """
    if value is None:
        return Verdict(True, CODE_OK)
    if not value.strip():
        return Verdict(True, CODE_OK)
    if len(value) > max_len:
        return Verdict(False, CODE_TOO_LONG)
    normalized = _normalize(value)
    for pat in _PATTERNS:
        if pat.search(normalized):
            return Verdict(False, CODE_BLOCKED)
    return Verdict(True, CODE_OK)


def enforce(value: Optional[str], *, field: Optional[str] = None, max_len: int = MAX_TEXT_LEN) -> None:
    """Raise HTTPException(400) with a stable, non-sensitive message if `value` is disallowed.

    No-op when allowed. FastAPI is imported lazily so the core stays framework-agnostic and
    unit-testable without a web context. The rejected text and matched term are never included.
    """
    verdict = evaluate(value, max_len=max_len)
    if verdict.allowed:
        return
    from fastapi import HTTPException, status
    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=verdict.message)


def enforce_all(fields: dict[str, Optional[str]], *, max_len: int = MAX_TEXT_LEN) -> None:
    """Enforce every (field -> value) BEFORE any persistence, for multi-field writes.

    Raises on the FIRST violation so nothing is written — callers must call this before any
    db.add/commit or file upload to preserve all-or-nothing writes. Field names are used only to
    order/iterate; they are not leaked in the error message.
    """
    for _field, value in fields.items():
        enforce(value, field=_field, max_len=max_len)
