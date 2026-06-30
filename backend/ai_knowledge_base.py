# AI Coach Knowledge Base — source-grounded coaching support layer
#
# Honesty contract (see CLAUDE.md trust rules):
#   • This is a SMALL, CURATED, INTERNAL source registry. It is NOT web browsing.
#   • Every entry below is authored/vetted in-house. We do NOT ship fabricated
#     external citations, page titles, or URLs. `url` is intentionally None on
#     every entry until a real, verified reputable link is added in a later pass.
#   • The coach may only cite a source that retrieve_coach_sources() actually
#     returned for the current message. No source => no "Based on" claim.
#   • External (web/organization-published) sources are DEFERRED — only the
#     interface/schema and internal guidance entries exist today.
#
# A source entry is a plain dict so it serializes straight into the API response:
#   {
#     "source_id":   stable id,
#     "title":       short human title,
#     "publisher":   who authored/vetted it (internal today),
#     "url":         real reputable URL or None (None today — external deferred),
#     "topic_tags":  list of lowercase tags used for retrieval matching,
#     "summary":     short vetted excerpt the coach may paraphrase/quote,
#     "safety_category": "medical_caution" | "recovery" | "training" | "drill",
#   }

from typing import List, Dict, Optional


# MARK: - Curated internal source registry (external URL'd sources deferred)

_KNOWLEDGE_BASE: List[Dict] = [
    {
        "source_id": "injury-acute-red-flags",
        "title": "When to stop and seek care for an injury",
        "publisher": "SportsHub Safety Guidance (internal)",
        "url": None,
        "topic_tags": [
            "injury", "pain", "sore", "hurt", "swelling", "sprain", "strain",
            "rolled", "twisted", "ankle", "knee", "shoulder", "wrist", "acute",
        ],
        "summary": (
            "Stop any activity that reproduces sharp or worsening pain. Seek a "
            "professional evaluation if pain is severe, the joint is unstable or "
            "can't bear weight, there is rapid swelling, numbness, or pain that "
            "doesn't improve with rest over a few days."
        ),
        "safety_category": "medical_caution",
    },
    {
        "source_id": "head-impact-caution",
        "title": "Head impacts and concussion caution",
        "publisher": "SportsHub Safety Guidance (internal)",
        "url": None,
        "topic_tags": [
            "head", "concussion", "dizzy", "dizziness", "hit my head",
            "hit in the head", "headache", "blurry", "nausea", "confused",
        ],
        "summary": (
            "Any blow to the head can be serious. Stop playing immediately. "
            "Watch for headache, dizziness, confusion, nausea, blurred vision, "
            "or sensitivity to light. Do not return to play the same day and get "
            "evaluated by a medical professional before resuming activity."
        ),
        "safety_category": "medical_caution",
    },
    {
        "source_id": "soft-tissue-early-care",
        "title": "Early care for mild muscle/joint soreness",
        "publisher": "SportsHub Safety Guidance (internal)",
        "url": None,
        "topic_tags": [
            "sore", "soreness", "stiff", "tight", "mild", "ache", "doms",
            "recovery", "ice", "rest",
        ],
        "summary": (
            "For mild soreness with no sharp pain: relative rest, gentle "
            "mobility, and gradual return usually help. Ice for 15–20 minutes "
            "can ease swelling early on. Re-introduce load gradually and back "
            "off if pain sharpens."
        ),
        "safety_category": "medical_caution",
    },
    {
        "source_id": "recovery-sleep-load",
        "title": "Recovery basics: sleep, load, and rest days",
        "publisher": "SportsHub Training Principles (internal)",
        "url": None,
        "topic_tags": [
            "recovery", "rest", "tired", "fatigue", "fatigued", "overtraining",
            "sleep", "exhausted", "burnout", "rest day",
        ],
        "summary": (
            "Adaptation happens during recovery, not just training. Prioritize "
            "7–9 hours of sleep, keep at least one lighter or full rest day per "
            "week, and reduce intensity when fatigue, poor sleep, or a low "
            "readiness signal stacks up. Recovery is part of training, not a "
            "break from it."
        ),
        "safety_category": "recovery",
    },
    {
        "source_id": "training-progressive-overload",
        "title": "Progressive overload and consistency",
        "publisher": "SportsHub Training Principles (internal)",
        "url": None,
        "topic_tags": [
            "improve", "progress", "training", "consistency", "plateau",
            "stuck", "not improving", "overload", "skill", "technique",
            "fundamentals",
        ],
        "summary": (
            "Improvement comes from gradual, consistent increases in difficulty "
            "with good form — not from occasional maximal efforts. Master the "
            "fundamentals, add small challenges over time, and track reps so you "
            "can see progress week to week."
        ),
        "safety_category": "training",
    },
    {
        "source_id": "hydration-fueling-basics",
        "title": "Hydration and fueling around training",
        "publisher": "SportsHub Training Principles (internal)",
        "url": None,
        "topic_tags": [
            "hydration", "hydrate", "water", "nutrition", "fuel", "eat",
            "cramp", "cramps", "dehydrated", "energy",
        ],
        "summary": (
            "Drink water before, during, and after activity, and more in heat. "
            "Eat a balanced meal a couple of hours before hard sessions and "
            "refuel with carbs and protein afterward. Persistent cramping or "
            "lightheadedness is a signal to stop and rehydrate."
        ),
        "safety_category": "training",
    },
]


# MARK: - Retrieval

# Intent → which safety categories are eligible for retrieval. Keeps drills/match
# prep from pulling medical sources they don't need.
_INTENT_CATEGORY_ELIGIBILITY = {
    "injury": {"medical_caution"},
    "recovery": {"recovery", "medical_caution"},
    "training": {"training"},
    "general": {"training", "recovery"},
}


def retrieve_coach_sources(
    query: str,
    sport: Optional[str] = None,
    intent: str = "general",
    limit: int = 2,
) -> List[Dict]:
    """Return curated internal sources relevant to the message.

    Matching is a simple tag-overlap score against the lowercased query. Only
    sources whose safety_category is eligible for the given intent are
    considered. Returns at most `limit` sources, highest tag-overlap first.

    Returns [] when nothing relevant is found — callers MUST treat an empty
    result as "no source-backed claim is allowed" (honest fallback).
    """
    if not query:
        return []

    low = query.lower()
    eligible = _INTENT_CATEGORY_ELIGIBILITY.get(intent, _INTENT_CATEGORY_ELIGIBILITY["general"])

    scored: List[tuple] = []
    for entry in _KNOWLEDGE_BASE:
        if entry["safety_category"] not in eligible:
            continue
        score = sum(1 for tag in entry["topic_tags"] if tag in low)
        if score > 0:
            scored.append((score, entry))

    scored.sort(key=lambda pair: pair[0], reverse=True)
    return [_public_source(entry) for _, entry in scored[:limit]]


def _public_source(entry: Dict) -> Dict:
    """Project an internal entry to the fields the API exposes to clients."""
    return {
        "source_id": entry["source_id"],
        "title": entry["title"],
        "publisher": entry["publisher"],
        "url": entry["url"],
    }
