#!/usr/bin/env python3
"""
Phase 7: API Contract Generator

Generates api_contract.json from Pydantic schemas and manual dict specs.
This is the authoritative record of what JSON shapes the backend sends.

Usage:
    cd backend
    python generate_schema.py                        # writes ../api_contract.json
    python generate_schema.py --output /path/out.json

Re-run this script whenever a backend Pydantic schema changes to keep
api_contract.json in sync. Then run validate_api_contract.sh to detect
any new drift against iOS models.
"""
import json
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path

# Allow importing schemas from the backend directory
sys.path.insert(0, str(Path(__file__).parent))


# ---------------------------------------------------------------------------
# Pydantic model → JSON key extraction
# ---------------------------------------------------------------------------

def _extract_type(field_schema: dict) -> str:
    """Return a readable type string from a Pydantic v2 JSON Schema field."""
    # anyOf is Pydantic v2's representation of Optional
    if "anyOf" in field_schema:
        non_null = [_extract_type(t) for t in field_schema["anyOf"] if t.get("type") != "null"]
        return non_null[0] if non_null else "any"
    t = field_schema.get("type")
    if t:
        return t
    # $ref points to an enum or nested model in $defs
    if "$ref" in field_schema:
        return field_schema["$ref"].split("/")[-1]
    if "format" in field_schema:
        return field_schema["format"]
    return "any"


def pydantic_to_fields(cls) -> dict:
    """
    Return a dict of {json_field_name: {type, required}} extracted from
    a Pydantic v2 model's JSON schema.
    """
    schema = cls.model_json_schema()
    properties = schema.get("properties", {})
    required_set = set(schema.get("required", []))
    return {
        name: {
            "type": _extract_type(field_schema),
            "required": name in required_set,
        }
        for name, field_schema in properties.items()
    }


# ---------------------------------------------------------------------------
# Contract builder
# ---------------------------------------------------------------------------

def generate_contract() -> dict:
    from schemas import (
        EvidenceFileUploadResponse,
        EvidenceResponse,
        ChallengeResponse,
        TournamentResponse,
        UserResponse,
    )

    models: dict = {}

    # -------------------------------------------------------------------
    # Pydantic-modelled schemas
    # -------------------------------------------------------------------
    pydantic_entries = [
        {
            "key": "EvidenceFileUploadResponse",
            "cls": EvidenceFileUploadResponse,
            "backend_endpoint": "POST /evidence/upload",
            "ios_file": "SportsHub/FileUploadToken.swift",
            "ios_struct": "FileUploadToken",
            "notes": [
                "Real multipart upload pipeline implemented in Phase 4b.",
                "iOS FileUploadToken.swift has explicit CodingKeys for all 4 fields.",
            ],
            "known_mismatches": {},
        },
        {
            "key": "EvidenceResponse",
            "cls": EvidenceResponse,
            "backend_endpoint": "GET /evidence/match/{challenge_id}",
            "ios_file": "SportsHub/APIModels.swift",
            "ios_struct": "EvidenceResponse",
            "notes": [
                "12-field response; iOS APIModels.swift EvidenceResponse maps all fields.",
            ],
            "known_mismatches": {},
        },
        {
            "key": "ChallengeResponse",
            "cls": ChallengeResponse,
            "backend_endpoint": "GET /challenges/{challenge_id}",
            "ios_file": "SportsHub/APIModels.swift",
            "ios_struct": "ChallengeResponse",
            "notes": [
                "iOS model decodes 5 optional extra fields beyond the Pydantic schema: "
                "challenger_submitted_score, opponent_submitted_score, accepted_at, "
                "completed_at, winner_user_id.  Some challenge routers return these as "
                "extra dict fields; if absent the optionals decode as nil — harmless.",
            ],
            "known_mismatches": {
                "challenger_submitted_score": {"reason": "future-backed", "note": "some routers return as extra dict field; will be standardised into ChallengeResponse Pydantic schema"},
                "opponent_submitted_score":   {"reason": "future-backed", "note": "same as challenger_submitted_score"},
                "accepted_at":                {"reason": "future-backed", "note": "extra dict field from some routers; not yet in Pydantic schema"},
                "completed_at":               {"reason": "future-backed", "note": "extra dict field from some routers; not yet in Pydantic schema"},
                "winner_user_id":             {"reason": "future-backed", "note": "extra dict field from some routers; not yet in Pydantic schema"},
                "challenger_confirmed":       {"reason": "future-backed", "note": "backend already sends this required field; iOS needs CodingKey + awaiting-confirmation UI"},
                "opponent_confirmed":         {"reason": "future-backed", "note": "backend already sends this required field; iOS needs CodingKey + awaiting-confirmation UI"},
            },
        },
        {
            "key": "TournamentResponse",
            "cls": TournamentResponse,
            "backend_endpoint": "GET /tournaments/{tournament_id}",
            "ios_file": "PremiumModels.swift",
            "ios_struct": "Tournament",
            "notes": [
                "Fixed 2026-04-18: iOS startsAt/endsAt/participantCount CodingKeys corrected "
                "to match backend start_date/end_date/current_participants.",
                "iOS Tournament declares many fields absent from backend: tournament_type, "
                "ranked_type, team_size, min_elo, max_elo, current_round, is_public, "
                "is_school, is_regional, region, school_name, prizes. "
                "All decode as nil/0/[] — iOS-side future feature stubs.",
                "Backend sends creator_username, is_premium_only, location, is_online, "
                "entry_fee, prize_description — not decoded by iOS.",
            ],
            "known_mismatches": {
                # Backend fields iOS does not decode yet:
                "creator_username":  {"reason": "future-backed", "note": "backend sends; iOS will decode when creator attribution UI is added"},
                "is_premium_only":   {"reason": "future-backed", "note": "backend sends; iOS will decode when premium tournament badge is added"},
                "location":          {"reason": "future-backed", "note": "backend sends; iOS will decode when venue display is added"},
                "is_online":         {"reason": "future-backed", "note": "backend sends; iOS will decode when online/in-person filter is added"},
                "entry_fee":         {"reason": "future-backed", "note": "backend sends; iOS will decode when payment flow is added"},
                "prize_description": {"reason": "future-backed", "note": "backend sends; iOS will decode when prize section is added"},
                # iOS CodingKey stubs not yet in backend:
                "tournament_type":   {"reason": "future-backed", "note": "iOS stub; backend will add when tournament type system ships"},
                "ranked_type":       {"reason": "future-backed", "note": "iOS stub; backend will add ranked/unranked distinction"},
                "team_size":         {"reason": "future-backed", "note": "iOS stub; backend will add for team tournament support"},
                "min_elo":           {"reason": "future-backed", "note": "iOS stub; backend will add ELO floor gating"},
                "max_elo":           {"reason": "future-backed", "note": "iOS stub; backend will add ELO ceiling gating"},
                "current_round":     {"reason": "future-backed", "note": "iOS stub; backend will add bracket round tracking"},
                "is_public":         {"reason": "future-backed", "note": "iOS stub; backend will add public/private toggle"},
                "is_school":         {"reason": "future-backed", "note": "iOS stub; backend will add school league support"},
                "is_regional":       {"reason": "future-backed", "note": "iOS stub; backend will add regional designation"},
                "region":            {"reason": "future-backed", "note": "iOS stub; backend will add region field"},
                "school_name":       {"reason": "future-backed", "note": "iOS stub; backend will add school name for leagues"},
                "prizes":            {"reason": "future-backed", "note": "iOS stub (array); backend will add structured prize list"},
            },
        },
        {
            "key": "UserResponse",
            "cls": UserResponse,
            "backend_endpoint": "GET /users/me",
            "ios_file": "SportsHub/SessionManager.swift",
            "ios_struct": "User",
            "notes": [
                "iOS User struct has NO CodingKeys enum. Swift Codable uses property names "
                "directly, so camelCase properties look for camelCase JSON keys. "
                "Backend sends snake_case. displayName/dateOfBirth/parentEmail will not decode.",
                "iOS User struct is a 8-field subset of the 13-field backend UserResponse.",
                "bio is in UserProfile (extends UserResponse), not UserResponse itself.",
            ],
            "known_mismatches": {
                # Backend fields iOS does not correctly decode:
                "display_name":      {"reason": "deprecated",    "note": "backend sends display_name but iOS User has no CodingKeys; Codable looks for 'displayName' — fix by adding CodingKeys enum to User struct"},
                "account_status":    {"reason": "future-backed", "note": "backend sends; iOS will decode for account suspension / moderation warnings UI"},
                "age_verified":      {"reason": "future-backed", "note": "backend sends; iOS will decode for COPPA gate and age verification badge"},
                "email_verified":    {"reason": "future-backed", "note": "backend sends; iOS will decode to show email verification status badge"},
                "survey_completed":  {"reason": "future-backed", "note": "backend sends; iOS will decode to skip onboarding survey for returning users"},
                "is_legacy_account": {"reason": "future-backed", "note": "backend sends; iOS will decode for legacy migration messaging"},
                "created_at":        {"reason": "future-backed", "note": "backend sends; iOS will decode for member-since display in Profile"},
                "full_name":         {"reason": "future-backed", "note": "backend sends; iOS will decode when real name is surfaced in profile UI"},
                "is_admin":          {"reason": "future-backed", "note": "backend sends; iOS admin routing uses user.role via SessionManager.isAdmin"},
                # iOS property names that don't match backend keys:
                "displayName":       {"reason": "deprecated",    "note": "iOS property name with no CodingKey — Codable looks for 'displayName' but backend sends 'display_name'"},
                "dateOfBirth":       {"reason": "client-only",   "note": "not in backend UserResponse; stored locally for age verification / COPPA compliance UI"},
                "parentEmail":       {"reason": "client-only",   "note": "not in backend UserResponse; parent account info stored locally for COPPA compliance UI"},
                "bio":               {"reason": "future-backed", "note": "in UserProfile extended schema; available once /users/me returns UserProfile"},
            },
        },
    ]

    for entry in pydantic_entries:
        cls = entry["cls"]
        models[entry["key"]] = {
            "source": "pydantic",
            "pydantic_class": cls.__name__,
            "backend_endpoint": entry["backend_endpoint"],
            "ios_file": entry["ios_file"],
            "ios_struct": entry["ios_struct"],
            "notes": entry["notes"],
            "known_mismatches": entry["known_mismatches"],
            "fields": pydantic_to_fields(cls),
        }

    # -------------------------------------------------------------------
    # Manual dict specs (raw dict returns — no Pydantic model on backend)
    # -------------------------------------------------------------------
    manual_specs = [
        {
            "key": "EvidenceRequirementResponse",
            "source": "manual_dict",
            "backend_endpoint": "GET /evidence/required/{challenge_id}",
            "backend_file": "backend/routers/evidence.py",
            "ios_file": "SportsHub/APIModels.swift",
            "ios_struct": "EvidenceRequirementResponse",
            "notes": [
                "Backend returns raw dict from check_evidence_required(). "
                "No Pydantic model — fields confirmed from evidence.py source.",
            ],
            "known_mismatches": {},
            "fields": {
                "challenge_id":       {"type": "string",  "required": True},
                "requirement":        {"type": "string",  "required": True},
                "reason":             {"type": "string",  "required": True},
                "is_disputed":        {"type": "boolean", "required": True},
                "user_trust_tier":    {"type": "string",  "required": True},
                "opponent_trust_tier":{"type": "string",  "required": True},
            },
        },
        {
            "key": "ActivityItem",
            "source": "manual_dict",
            "backend_endpoint": "GET /activity/feed",
            "backend_file": "backend/routers/activity.py",
            "ios_file": "SportsHub/APIModels.swift",
            "ios_struct": "ActivityItem",
            "notes": [
                "STRUCTURAL MISMATCH — cross-checked 2026-04-19 against backend/routers/activity.py.",
                "Backend sends a deeply-nested dict: { type, timestamp, challenge_id, sport, match_type, "
                "challenger: {id, username, display_name}, opponent: {id, username, display_name}, "
                "winner: {id, username, display_name}|null, rating_change: {challenger: int, opponent: int}|null }.",
                "iOS ActivityItem expects flat scalar fields: user_id, username, opponent_username, "
                "winner_username, user_score, opponent_score, rating_change (Int?), created_at.",
                "RESULT: only 'type', 'sport', and 'match_type' decode correctly. All other iOS fields are "
                "silent nil/empty. NotificationsView rows will show no usernames, no scores, no time.",
                "Fix options: (A) flatten the backend dict to match iOS shape, or "
                "(B) redesign iOS ActivityItem to decode nested challenger/opponent/winner objects.",
            ],
            "known_mismatches": {
                "user_id":           {"reason": "deprecated",    "note": "iOS expects flat 'user_id' string; backend sends nested challenger.id — iOS field decodes as nil."},
                "username":          {"reason": "deprecated",    "note": "iOS expects flat 'username' string; backend sends nested challenger.username — decodes as nil."},
                "opponent_username": {"reason": "deprecated",    "note": "iOS expects flat 'opponent_username'; backend sends nested opponent.username — decodes as nil."},
                "winner_username":   {"reason": "deprecated",    "note": "iOS expects flat 'winner_username'; backend sends nested winner.username — decodes as nil."},
                "user_score":        {"reason": "deprecated",    "note": "iOS expects flat 'user_score' Int?; backend does not send any score field — always nil."},
                "opponent_score":    {"reason": "deprecated",    "note": "iOS expects flat 'opponent_score' Int?; backend does not send any score field — always nil."},
                "rating_change":     {"reason": "deprecated",    "note": "iOS expects Int?; backend sends {challenger: int, opponent: int} dict — type mismatch, iOS decodes as nil."},
                "created_at":        {"reason": "deprecated",    "note": "iOS expects key 'created_at'; backend sends key 'timestamp' — decodes as nil."},
                "timestamp":         {"reason": "deprecated",    "note": "Backend sends 'timestamp'; iOS has no CodingKey for it. Rename to 'created_at' on backend."},
                "challenge_id":      {"reason": "future-backed", "note": "Backend sends challenge_id; iOS has no field. Useful for deep-linking into match detail."},
                "challenger":        {"reason": "deprecated",    "note": "Backend sends nested {id, username, display_name}; iOS has no struct for it."},
                "opponent":          {"reason": "deprecated",    "note": "Backend sends nested {id, username, display_name}; iOS has no struct for it."},
                "winner":            {"reason": "deprecated",    "note": "Backend sends nested object or null; iOS has no struct for it."},
            },
            # Fields reflect actual backend shape, not the (incorrect) iOS CodingKeys.
            "fields": {
                "type":         {"type": "string", "required": True},
                "timestamp":    {"type": "string", "required": True,  "note": "iOS decodes as 'created_at' — key mismatch, always nil"},
                "challenge_id": {"type": "string", "required": True},
                "sport":        {"type": "string", "required": True},
                "match_type":   {"type": "string", "required": False},
                "challenger":   {"type": "object", "required": True,  "note": "nested {id, username, display_name}; iOS has no CodingKey"},
                "opponent":     {"type": "object", "required": True,  "note": "nested {id, username, display_name}; iOS has no CodingKey"},
                "winner":       {"type": "object", "required": False, "note": "nested object or null; iOS has no CodingKey"},
                "rating_change":{"type": "object", "required": False, "note": "{challenger: int, opponent: int} or null; iOS expects Int?"},
            },
        },
    ]

    for spec in manual_specs:
        models[spec["key"]] = {
            "source": spec["source"],
            "backend_endpoint": spec["backend_endpoint"],
            "backend_file": spec.get("backend_file", ""),
            "ios_file": spec["ios_file"],
            "ios_struct": spec["ios_struct"],
            "notes": spec["notes"],
            "known_mismatches": spec["known_mismatches"],
            "fields": spec["fields"],
        }

    return {
        "schema_version": "1.2",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "note": (
            "v1.2: ActivityItem cross-checked against backend/routers/activity.py — "
            "structural mismatch documented. "
            "Regenerate from Pydantic source with: cd backend && python generate_schema.py"
        ),
        "description": (
            "API contract between SportsHub FastAPI backend and iOS Swift client. "
            "JSON field names must match iOS CodingKey string literals. "
            "Used by validate_api_contract.sh for schema drift detection."
        ),
        "known_mismatch_reasons": {
            "future-backed": "iOS has a stub OR backend sends this; the other side will catch up in a future sprint",
            "client-only":   "field is derived/computed on the client; it never comes from or goes to the backend",
            "deprecated":    "field exists on one side but should be removed or renamed; tracked for a cleanup sprint",
        },
        "models": models,
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Generate api_contract.json from Pydantic schemas")
    parser.add_argument(
        "--output",
        default=str(Path(__file__).parent.parent / "api_contract.json"),
        help="Output path (default: <project_root>/api_contract.json)",
    )
    args = parser.parse_args()

    print("Generating API contract from Pydantic schemas…")
    try:
        contract = generate_contract()
    except ImportError as e:
        print(f"ERROR: Could not import schemas. Run from the backend directory.\n  {e}")
        sys.exit(1)

    output_path = Path(args.output)
    output_path.write_text(json.dumps(contract, indent=2, default=str))

    total_fields = sum(len(m["fields"]) for m in contract["models"].values())
    print(f"Written: {output_path}")
    print(f"  {len(contract['models'])} models, {total_fields} total fields")
    for name, model in contract["models"].items():
        src = model["source"]
        nf = len(model["fields"])
        nm = len(model.get("known_mismatches", []))
        flag = f" ({nm} known mismatches)" if nm else ""
        print(f"  [{src:>12}]  {name} — {nf} fields{flag}")


if __name__ == "__main__":
    main()
