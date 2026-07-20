"""
Relevance-based, privacy-conscious wearable/HealthKit context for the AI Coach.

Trust boundary (never violated here):
    Apple Watch / HealthKit
      → SportsHub iOS permission + sync layer
      → normalized SportsHub wearable data (BiometricData, TrainingSession rows)
      → this module (server-side selection of RELEVANT, FRESH, REAL metrics)
      → OpenAI model
    OpenAI never touches HealthKit; iOS never calls OpenAI; the API key stays
    server-side. Only relevant normalized summaries are sent — never raw history.

Honesty contract:
  - Only metrics that are actually present (non-null) are surfaced.
  - Freshness is always stated; stale data is never used for present-tense claims.
  - Missing metrics are listed as unavailable so the model cannot fabricate them.
  - Wearable readiness is supportive context only — it NEVER overrides hard safety.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional


# Wearable context is retrieved ONLY when the request plausibly benefits from it.
# Keep this list tight — do not retrieve wearable data just because it exists.
_WEARABLE_PHRASES = [
    "how hard should i train", "how hard do i train", "train today", "training today",
    "recovered", "recovery", "recover", "readiness", "ready to train", "am i ready",
    "tired", "fatigue", "fatigued", "exhausted", "worn out", "drained",
    "legs feel", "legs are", "heavy legs", "my legs", "sore",
    "lighter day", "rest day", "take it easy", "should i rest",
    "this week", "last week", "recent training", "recent workouts", "how much have i trained",
    "how has my training", "training been", "trained recently", "overtrain", "overtrained",
    "my watch", "smartwatch", "apple watch", "wearable", "after practice",
    "fitness tracker", "tracker", "fitbit", "garmin", "whoop", "oura",
    "strain", "training strain", "activity tracker", "step count",
    "sleep", "slept", "resting heart", "heart rate", "hrv", "check my recent",
    "build today", "around my recovery", "based on my recovery",
]

# Intents (from the pipeline) that are inherently wearable-relevant.
_WEARABLE_INTENTS = {"recovery", "progress_readiness"}


def wearable_relevant(user_message: str, intent: Optional[str]) -> bool:
    """Decide whether this turn should pull wearable context. Relevance-based:
    greetings, arithmetic, generic drills, writing, etc. return False."""
    if intent in _WEARABLE_INTENTS:
        return True
    low = (user_message or "").lower()
    return any(p in low for p in _WEARABLE_PHRASES)


def _freshness_label(days_old: int) -> str:
    if days_old <= 1:
        return "fresh"
    if days_old <= 3:
        return "recent"
    return "stale"


def build_wearable_context(db, user_id, *, now: Optional[datetime] = None,
                           lookback_days: int = 7) -> Dict:
    """Build a normalized, freshness-aware wearable context from REAL synced rows.

    Returns a dict describing what is genuinely available; never fabricates. Uses
    the most recent BiometricData within `lookback_days` (not just today) so we can
    honestly disclose staleness instead of silently claiming "unknown".
    """
    # Imported lazily so the pure helpers above stay import-light/testable.
    from models_premium import BiometricData
    import models as _models

    now = now or datetime.now(timezone.utc)
    horizon = now - timedelta(days=lookback_days)

    ctx: Dict = {
        "data_available": False,
        "freshness": "none",
        "data_age_days": None,
        "as_of": None,
        "metrics": {},
        "recent_training": None,
        "unavailable_metrics": [],
    }

    row = (
        db.query(BiometricData)
        .filter(BiometricData.user_id == user_id, BiometricData.date >= horizon)
        .order_by(BiometricData.date.desc())
        .first()
    )

    all_metric_labels = {
        "recovery_score": "recovery/readiness score",
        "sleep_hours": "sleep duration",
        "resting_heart_rate": "resting heart rate",
        "hrv_ms": "HRV",
        "fatigue_level": "fatigue level",
        "training_strain": "training strain",
    }

    if row is not None:
        row_date = row.date
        if row_date.tzinfo is None:
            row_date = row_date.replace(tzinfo=timezone.utc)
        days_old = max(0, (now - row_date).days)
        metrics: Dict = {}
        # recovery/readiness: prefer explicit recovery_score, fall back to readiness_score
        rec = row.recovery_score if row.recovery_score is not None else row.readiness_score
        if rec is not None:
            metrics["recovery_score"] = round(float(rec), 1)
        if row.sleep_duration:
            metrics["sleep_hours"] = round(row.sleep_duration / 60.0, 1)
        if row.resting_heart_rate is not None:
            metrics["resting_heart_rate"] = int(row.resting_heart_rate)
        if row.heart_rate_variability is not None:
            metrics["hrv_ms"] = int(row.heart_rate_variability)
        if row.fatigue_level:
            metrics["fatigue_level"] = row.fatigue_level
        if row.training_strain is not None:
            metrics["training_strain"] = round(float(row.training_strain), 1)

        if metrics:
            ctx["data_available"] = True
            ctx["freshness"] = _freshness_label(days_old)
            ctx["data_age_days"] = days_old
            ctx["as_of"] = row_date.date().isoformat()
            ctx["metrics"] = metrics

        ctx["unavailable_metrics"] = [
            all_metric_labels[k] for k in all_metric_labels if k not in metrics
        ]
    else:
        ctx["unavailable_metrics"] = list(all_metric_labels.values())

    # Recent training summary (last `lookback_days`) — real logged sessions.
    try:
        sessions = (
            db.query(_models.TrainingSession)
            .filter(_models.TrainingSession.user_id == user_id,
                    _models.TrainingSession.created_at >= horizon)
            .all()
        )
        if sessions:
            total = sum((s.total_duration or 0) for s in sessions)
            ctx["recent_training"] = {
                "sessions_last_7d": len(sessions),
                "total_minutes_last_7d": total,
            }
    except Exception:
        pass  # training summary is best-effort; never fail the coach turn

    return ctx


def format_wearable_block(ctx: Dict) -> str:
    """Render the wearable context as an honest system-prompt block."""
    if not ctx.get("data_available") and not ctx.get("recent_training"):
        return (
            "=== WEARABLE CONTEXT ===\n"
            "No recent synced wearable/recovery data is available for this athlete. "
            "Do NOT invent recovery, sleep, HRV, or heart-rate numbers. You may still "
            "help based on how they say they feel. Wearable data NEVER overrides a hard "
            "safety red flag.\n"
            "=== END WEARABLE CONTEXT ==="
        )

    lines = ["=== WEARABLE CONTEXT (real synced data — use ONLY what is listed) ==="]

    if ctx.get("data_available"):
        fresh = ctx.get("freshness")
        age = ctx.get("data_age_days")
        as_of = ctx.get("as_of")
        if fresh == "fresh":
            lines.append(f"Freshness: latest metrics are from {as_of} (current). Present-tense use is OK.")
        elif fresh == "recent":
            lines.append(f"Freshness: latest metrics are from {as_of} ({age} days ago) — recent but NOT today. "
                         "Do not claim they reflect 'today'.")
        else:
            lines.append(f"Freshness: latest metrics are from {as_of} ({age} days ago) — STALE. "
                         "Do not use them to judge today's readiness; say the data is old.")
        m = ctx["metrics"]
        if "recovery_score" in m:      lines.append(f"- Recovery/readiness score: {m['recovery_score']}/100")
        if "sleep_hours" in m:         lines.append(f"- Sleep duration: {m['sleep_hours']} h")
        if "resting_heart_rate" in m:  lines.append(f"- Resting heart rate: {m['resting_heart_rate']} bpm")
        if "hrv_ms" in m:              lines.append(f"- HRV: {m['hrv_ms']} ms")
        if "fatigue_level" in m:       lines.append(f"- Fatigue level: {m['fatigue_level']}")
        if "training_strain" in m:     lines.append(f"- Training strain: {m['training_strain']}")

    rt = ctx.get("recent_training")
    if rt:
        lines.append(f"Recent training (last 7 days): {rt['sessions_last_7d']} sessions, "
                     f"{rt['total_minutes_last_7d']} total minutes.")

    unavailable = ctx.get("unavailable_metrics") or []
    if unavailable:
        lines.append("Unavailable (do NOT invent these): " + ", ".join(unavailable) + ".")

    lines += [
        "RULES:",
        "- Use ONLY the metrics listed above. If something isn't listed, say you don't have it — never fabricate a number.",
        "- Separate observation (\"your data shows…\") from inference (\"that suggests…\").",
        "- No diagnosis, no fake precision, no invented recovery score.",
        "- Wearable readiness is supportive only; it NEVER overrides a hard safety red flag "
        "(head impact, inability to bear weight, chest pain, severe/worsening injury). Safety always wins.",
        "=== END WEARABLE CONTEXT ===",
    ]
    return "\n".join(lines)
