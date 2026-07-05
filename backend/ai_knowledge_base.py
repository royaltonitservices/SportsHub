# AI Coach Knowledge Base — source-grounded coaching support layer
#
# Honesty contract (see CLAUDE.md trust rules):
#   • This is a SMALL, CURATED, INTERNAL source registry. It is NOT web browsing.
#   • Every entry below is authored/vetted in-house. We do NOT ship fabricated
#     external citations, page titles, or URLs. `url` is intentionally None on
#     every internal entry, and NO external entries are shipped yet.
#   • The coach may only cite a source that retrieve_coach_sources() actually
#     returned for the current message. No source => no "Based on" claim.
#   • EXTERNAL reputable sources (organization-published, with real URLs) are
#     DEFERRED. The schema below is ready for them (`source_type` ==
#     "external_reference"), but none are added until a real, verified URL from
#     a publicly-known reputable organization can be confirmed. Do not invent.
#
# Source entry schema (plain dicts so they serialize straight into responses):
#   {
#     "source_id":         stable id,
#     "title":             short human title,
#     "publisher":         who authored/vetted it,
#     "url":               real reputable URL or None (None for all internal entries),
#     "source_type":       one of:
#                            "internal_guidance"        (SportsHub-authored guidance)
#                            "internal_drill"           (drill-library material)
#                            "external_reference"       (reputable org, general)   [deferred]
#                            "rules_reference"          (official rules body)       [deferred]
#                            "medical_safety_reference" (reputable medical/safety org) [deferred]
#     "topic_tags":        lowercase tags used for retrieval matching,
#     "sport_tags":        lowercase sport names this applies to; [] == all sports,
#     "safety_category":   "medical_caution" | "recovery" | "training" | "drill",
#     "priority":          1 (highest) .. 5 (lowest) — primary ranking weight,
#     "reliability_rank":  1 (most reliable) .. 5 — defaults to `priority`,
#     "last_reviewed_date":ISO date string or None,
#     "summary":           short vetted excerpt the coach may paraphrase/quote,
#   }
# Only the four client-facing fields (source_id/title/publisher/url) are exposed
# over the API (see `public_source`). All deferred external `source_type`s have
# NO entries yet — none are shipped until a real verified URL is confirmed.
#
# The public projection (`_public_source`) intentionally exposes only the four
# client-facing fields (source_id/title/publisher/url) to keep the API contract
# stable. `source_type`/`sport_tags`/`priority` are internal retrieval metadata.

import re
from typing import List, Dict, Optional


# MARK: - Curated source registry (internal entries only; external deferred)

_KNOWLEDGE_BASE: List[Dict] = [
    {
        "source_id": "injury-acute-red-flags",
        "title": "When to stop and seek care for an injury",
        "publisher": "SportsHub Safety Guidance (internal)",
        "url": None,
        "source_type": "internal_guidance",
        "topic_tags": [
            "injury", "injured", "pain", "painful", "sore", "hurt", "hurts",
            "swelling", "swollen", "sprain", "sprained", "strain", "strained",
            "rolled", "twisted", "ankle", "knee", "shoulder", "wrist", "acute",
            "pop", "popped",
        ],
        "sport_tags": [],
        "safety_category": "medical_caution",
        "priority": 1,
        "summary": (
            "Stop any activity that reproduces sharp or worsening pain. Seek a "
            "professional evaluation if pain is severe, the joint is unstable or "
            "can't bear weight, there is rapid swelling, numbness, or pain that "
            "doesn't improve with rest over a few days."
        ),
    },
    {
        "source_id": "head-impact-caution",
        "title": "Head impacts and concussion caution",
        "publisher": "SportsHub Safety Guidance (internal)",
        "url": None,
        "source_type": "internal_guidance",
        "topic_tags": [
            "head", "concussion", "dizzy", "dizziness", "hit my head",
            "hit in the head", "headache", "blurry", "blurred", "nausea",
            "confused", "knocked out", "blacked out",
        ],
        "sport_tags": [],
        "safety_category": "medical_caution",
        "priority": 1,
        "summary": (
            "Any blow to the head can be serious. Stop playing immediately. "
            "Watch for headache, dizziness, confusion, nausea, blurred vision, "
            "or sensitivity to light. Do not return to play the same day and get "
            "evaluated by a medical professional before resuming activity."
        ),
    },
    {
        "source_id": "soft-tissue-early-care",
        "title": "Early care for mild muscle/joint soreness",
        "publisher": "SportsHub Safety Guidance (internal)",
        "url": None,
        "source_type": "internal_guidance",
        "topic_tags": [
            "sore", "soreness", "stiff", "stiffness", "tight", "tightness",
            "mild", "ache", "achy", "doms", "ice", "rest",
        ],
        "sport_tags": [],
        "safety_category": "medical_caution",
        "priority": 2,
        "summary": (
            "For mild soreness with no sharp pain: relative rest, gentle "
            "mobility, and gradual return usually help. Ice for 15–20 minutes "
            "can ease swelling early on. Re-introduce load gradually and back "
            "off if pain sharpens."
        ),
    },
    {
        "source_id": "recovery-sleep-load",
        "title": "Recovery basics: sleep, load, and rest days",
        "publisher": "SportsHub Training Principles (internal)",
        "url": None,
        "source_type": "internal_guidance",
        "topic_tags": [
            "recovery", "recover", "rest", "tired", "fatigue", "fatigued",
            "overtraining", "overtrained", "sleep", "exhausted", "burnout",
            "rest day", "drained", "worn out",
        ],
        "sport_tags": [],
        "safety_category": "recovery",
        "priority": 2,
        "summary": (
            "Adaptation happens during recovery, not just training. Prioritize "
            "7–9 hours of sleep, keep at least one lighter or full rest day per "
            "week, and reduce intensity when fatigue, poor sleep, or a low "
            "readiness signal stacks up. Recovery is part of training, not a "
            "break from it."
        ),
    },
    {
        "source_id": "training-progressive-overload",
        "title": "Progressive overload and consistency",
        "publisher": "SportsHub Training Principles (internal)",
        "url": None,
        "source_type": "internal_guidance",
        "topic_tags": [
            "improve", "improving", "progress", "training", "consistency",
            "plateau", "stuck", "not improving", "overload", "skill",
            "technique", "fundamentals", "better",
        ],
        "sport_tags": [],
        "safety_category": "training",
        "priority": 3,
        "summary": (
            "Improvement comes from gradual, consistent increases in difficulty "
            "with good form — not from occasional maximal efforts. Master the "
            "fundamentals, add small challenges over time, and track reps so you "
            "can see progress week to week."
        ),
    },
    {
        "source_id": "hydration-fueling-basics",
        "title": "Hydration and fueling around training",
        "publisher": "SportsHub Training Principles (internal)",
        "url": None,
        "source_type": "internal_guidance",
        "topic_tags": [
            "hydration", "hydrate", "water", "nutrition", "fuel", "fueling",
            "eat", "eating", "cramp", "cramps", "cramping", "dehydrated",
            "dehydration", "energy",
        ],
        "sport_tags": [],
        "safety_category": "training",
        "priority": 3,
        "summary": (
            "Drink water before, during, and after activity, and more in heat. "
            "Eat a balanced meal a couple of hours before hard sessions and "
            "refuel with carbs and protein afterward. Persistent cramping or "
            "lightheadedness is a signal to stop and rehydrate."
        ),
    },
]


# Backfill optional metadata so every entry has the full schema without repeating
# the fields on each literal. `reliability_rank` defaults to `priority`.
for _entry in _KNOWLEDGE_BASE:
    _entry.setdefault("reliability_rank", _entry.get("priority", 5))
    _entry.setdefault("last_reviewed_date", None)


# MARK: - Retrieval policy

# Intent → which safety categories are eligible. Keeps drill/match-prep messages
# from pulling medical sources, and keeps training messages out of injury cards.
_INTENT_CATEGORY_ELIGIBILITY = {
    "injury":   {"medical_caution"},
    "recovery": {"recovery", "medical_caution"},
    "training": {"training"},
    "general":  {"training", "recovery"},
}

# For ranking when an intent allows several categories, weight by clinical
# importance so safety material outranks general training material on ties.
_CATEGORY_WEIGHT = {
    "medical_caution": 3,
    "recovery": 2,
    "training": 1,
    "drill": 1,
}


def _tag_matches(tag: str, low: str) -> bool:
    """Word-boundary match (phrases allowed). Avoids substring false positives
    like 'ice' inside 'service' or 'rest' inside 'wrestling'."""
    return re.search(r"\b" + re.escape(tag) + r"\b", low) is not None


def retrieve_coach_source_entries(
    query: str,
    sport: Optional[str] = None,
    intent: str = "general",
    limit: int = 2,
) -> List[Dict]:
    """Return a small, ranked list of FULL internal source entries (incl. summary).

    Ranking is intent-aware, sport-aware, and safety-weighted — not naive
    substring matching:
      1. Only sources whose `safety_category` is eligible for `intent`.
      2. Only sources whose `sport_tags` is empty (universal) or contains `sport`.
      3. Score = (#word-boundary tag matches) + category weight + sport bonus,
         with `priority` as the final tie-breaker (lower = better).
      4. At most `limit`, highest score first.

    Returns [] when nothing relevant is found. Used by the orchestrator to build
    the GPT reference block (needs `summary`). The API-facing projection is
    `retrieve_coach_sources()` below.
    """
    if not query:
        return []

    low = query.lower()
    sport_l = (sport or "").lower()
    eligible = _INTENT_CATEGORY_ELIGIBILITY.get(intent, _INTENT_CATEGORY_ELIGIBILITY["general"])

    scored: List[tuple] = []
    for entry in _KNOWLEDGE_BASE:
        if entry["safety_category"] not in eligible:
            continue
        # Sport-specific sources only apply to their sport; [] == universal.
        sport_tags = entry.get("sport_tags") or []
        if sport_tags and sport_l and sport_l not in sport_tags:
            continue

        match_count = sum(1 for tag in entry["topic_tags"] if _tag_matches(tag, low))
        if match_count == 0:
            continue

        category_weight = _CATEGORY_WEIGHT.get(entry["safety_category"], 0)
        sport_bonus = 1 if (sport_tags and sport_l and sport_l in sport_tags) else 0
        priority = entry.get("priority", 5)
        # Higher score first; lower priority value first on ties.
        rank_key = (match_count + category_weight + sport_bonus, -priority)
        scored.append((rank_key, entry))

    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [entry for _, entry in scored[:limit]]


def retrieve_coach_sources(
    query: str,
    sport: Optional[str] = None,
    intent: str = "general",
    limit: int = 2,
) -> List[Dict]:
    """API-facing projection of `retrieve_coach_source_entries()`.

    Returns at most `limit` sources as the stable client contract
    (source_id/title/publisher/url). Empty => no source-backed claim allowed.
    """
    return [public_source(e) for e in retrieve_coach_source_entries(query, sport, intent, limit)]


def public_source(entry: Dict) -> Dict:
    """Project an internal entry to the fields the API exposes to clients.

    Deliberately limited to the stable CoachSource contract. `source_type`,
    `sport_tags`, and `priority` stay internal retrieval metadata for now.
    """
    return {
        "source_id": entry["source_id"],
        "title": entry["title"],
        "publisher": entry["publisher"],
        "url": entry["url"],
    }
