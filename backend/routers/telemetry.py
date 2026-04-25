"""
Telemetry event ingestion endpoint.

Receives fire-and-forget diagnostic events from the iOS CoachTelemetry system.
Stores events as newline-delimited JSON (JSONL) for external log collection / dashboarding.

No authentication required — events are non-sensitive diagnostic data.
Never fails the caller — all storage errors are swallowed silently.

Payload shape (from iOS CoachTelemetry):
  {
    "event_name": "gpt_validation_fail",
    "sport":      "basketball",
    "timestamp":  "2026-04-20T12:00:00Z",   // ISO 8601 from device
    "metadata":   {"violation_count": "2"},
    "app_version": "1.0"                     // optional
  }

Supported event_name values (minimum required):
  gpt_validation_fail, gpt_repair_applied, gpt_fallback_to_local,
  football_repair_failed, session_depth, endpoint_failure,
  constrained_retry_started, constrained_retry_succeeded, constrained_retry_failed,
  survey_updated, gpt_success, local_fallback, gpt_violation, safety_mode,
  feedback, high_specificity, session_started, overtraining, injury_context

Collection strategy:
  Events are appended to uploads/telemetry/events.jsonl.
  Use `grep`, `jq`, or any log-aggregation tool to query.
  Example: jq 'select(.event_name == "gpt_validation_fail")' uploads/telemetry/events.jsonl
"""
from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
import json
import os
from datetime import datetime, timezone

router = APIRouter(prefix="/telemetry", tags=["telemetry"])

# Newline-delimited JSON log — append-only, safe for concurrent writes on single-process servers
TELEMETRY_LOG_PATH = "./uploads/telemetry/events.jsonl"


class TelemetryEventRequest(BaseModel):
    """Single telemetry event from the iOS client."""
    event_name: str
    sport: str
    timestamp: str            # ISO 8601 from device clock
    metadata: dict = {}
    app_version: Optional[str] = None


@router.post("/event", status_code=204)
async def ingest_event(event: TelemetryEventRequest):
    """
    Ingest a single telemetry event.

    - Never blocks or errors the caller (204 is returned even if storage fails).
    - Events are appended to uploads/telemetry/events.jsonl as newline-delimited JSON.
    - The ingested_at field captures server-side receipt time for latency analysis.
    """
    try:
        os.makedirs(os.path.dirname(TELEMETRY_LOG_PATH), exist_ok=True)
        entry = {
            "event_name":  event.event_name,
            "sport":       event.sport,
            "timestamp":   event.timestamp,
            "metadata":    event.metadata,
            "app_version": event.app_version,
            "ingested_at": datetime.now(timezone.utc).isoformat(),
        }
        with open(TELEMETRY_LOG_PATH, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass  # Telemetry is best-effort — never propagate failures to the client
