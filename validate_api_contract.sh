#!/usr/bin/env bash
# =============================================================================
# validate_api_contract.sh — Phase 7 API Contract Validator
#
# Reads api_contract.json and checks each Swift model's CodingKey declarations
# against the expected backend field names.
#
# Per-model results:
#   PASS                — exact match; every backend field decoded by iOS
#   PASS_WITH_EXCEPTIONS— all mismatches are documented in known_mismatches
#   FAIL                — unexpected mismatch not listed in known_mismatches
#
# Overall exit codes:
#   0  — all models PASS or PASS_WITH_EXCEPTIONS
#   1  — one or more models FAIL
#
# Usage:
#   ./validate_api_contract.sh              # run from project root
#   ./validate_api_contract.sh --verbose    # show all fields, not just issues
#
# What it checks:
#   - Every backend field has a corresponding CodingKey in iOS
#   - Fields not in known_mismatches are FAIL (required) or flagged EXTRA/WARN
#   - Fields listed in known_mismatches are reported as KNOWN → PASS_WITH_EXCEPTIONS
#
# What it does NOT check:
#   - Field types (Swift ↔ Pydantic type mapping)
#   - Nested models or arrays
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=0

for arg in "$@"; do
    [[ "$arg" == "--verbose" ]] && VERBOSE=1
done

# ---------------------------------------------------------------------------
# Embedded Python validator
# ---------------------------------------------------------------------------
python3 - "$SCRIPT_DIR" "$VERBOSE" <<'PYTHON'
import sys
import json
import re
from pathlib import Path

project_root = Path(sys.argv[1])
verbose      = sys.argv[2] == "1"
contract_path = project_root / "api_contract.json"

# ANSI colours (disabled if not a terminal)
if sys.stdout.isatty():
    GREEN  = "\033[32m"
    YELLOW = "\033[33m"
    RED    = "\033[31m"
    CYAN   = "\033[36m"
    DIM    = "\033[2m"
    RESET  = "\033[0m"
else:
    GREEN = YELLOW = RED = CYAN = DIM = RESET = ""


def die(msg: str) -> None:
    print(f"{RED}ERROR: {msg}{RESET}", file=sys.stderr)
    sys.exit(2)


if not contract_path.exists():
    die(
        "api_contract.json not found.\n"
        "  Run: cd backend && python generate_schema.py"
    )

contract = json.loads(contract_path.read_text())
models   = contract.get("models", {})

# ---------------------------------------------------------------------------
# Swift CodingKey parser
# ---------------------------------------------------------------------------

def extract_ios_json_keys(swift_file: Path, struct_name: str) -> tuple[bool, bool, set[str]]:
    """
    Parse a Swift source file for a named struct's CodingKeys enum.

    Returns:
        (file_found, has_explicit_coding_keys, set_of_json_key_strings)

    When has_explicit_coding_keys is False the returned set contains the raw
    Swift property names (which Codable uses as JSON keys by default).
    """
    if not swift_file.exists():
        return False, False, set()

    content = swift_file.read_text(encoding="utf-8")
    lines   = content.splitlines()

    # ---- Step 1: locate the struct declaration ----
    struct_start = None
    for i, line in enumerate(lines):
        if re.search(rf"\bstruct\s+{re.escape(struct_name)}\b", line):
            struct_start = i
            break

    if struct_start is None:
        return True, False, set()  # file exists but struct not found

    # ---- Step 2: collect struct body lines via brace tracking ----
    depth        = 0
    body_started = False
    body_lines   = []

    for i in range(struct_start, len(lines)):
        line = lines[i]
        for ch in line:
            if ch == "{":
                depth += 1
                body_started = True
            elif ch == "}":
                depth -= 1
        if body_started:
            body_lines.append(line)
        if body_started and depth == 0:
            break

    struct_body = "\n".join(body_lines)

    # ---- Step 3: find CodingKeys enum inside the struct ----
    ck_match = re.search(
        r"enum\s+CodingKeys\s*:\s*String\s*,\s*CodingKey",
        struct_body,
    )

    if not ck_match:
        # No explicit CodingKeys — Swift uses property names as JSON keys
        prop_names = re.findall(r"(?:let|var)\s+(\w+)\s*:", struct_body)
        return True, False, set(prop_names)

    # ---- Step 4: extract the CodingKeys enum body ----
    ck_tail  = struct_body[ck_match.start():]
    brace_pos = ck_tail.index("{")
    ck_depth = 0
    ck_end   = brace_pos

    for i, ch in enumerate(ck_tail[brace_pos:], brace_pos):
        if ch == "{":
            ck_depth += 1
        elif ch == "}":
            ck_depth -= 1
            if ck_depth == 0:
                ck_end = i
                break

    ck_body = ck_tail[brace_pos : ck_end + 1]

    # ---- Step 5: parse case declarations ----
    json_keys: set[str] = set()

    for line in ck_body.splitlines():
        stripped = line.strip()
        if not stripped.startswith("case "):
            continue
        # Strip trailing comments
        after_case = stripped[5:].split("//")[0].strip()

        # case foo = "bar"  →  JSON key is "bar"
        literal = re.search(r'=\s*"([^"]+)"', after_case)
        if literal:
            json_keys.add(literal.group(1))
        else:
            # case foo  OR  case foo, bar, baz  →  identifiers are the keys
            for part in after_case.split(","):
                part = part.strip()
                if part and re.match(r"^\w+$", part):
                    json_keys.add(part)

    return True, True, json_keys


# ---------------------------------------------------------------------------
# Validation loop
# ---------------------------------------------------------------------------

PASS_COUNT       = 0   # exact match — no mismatches at all
EXCEPTION_COUNT  = 0   # all mismatches are documented in known_mismatches
FAIL_COUNT       = 0   # unexpected mismatch not in known_mismatches
KNOWN_REASON_COUNTS = {}  # {reason_label: count} accumulated across all models

SEP = "─" * 62

print(f"\n{CYAN}SportsHub API Contract Validator{RESET}")
print(f"{DIM}Contract: {contract_path}{RESET}")
print(f"{DIM}Schema version: {contract.get('schema_version', '?')}  "
      f"Generated: {contract.get('generated_at', '?')}{RESET}\n")

for model_name, model in models.items():
    ios_file_rel = model["ios_file"]
    ios_struct   = model["ios_struct"]
    swift_path   = project_root / ios_file_rel

    print(SEP)
    print(f"Model   : {model_name}")
    print(f"Endpoint: {DIM}{model['backend_endpoint']}{RESET}")
    print(f"iOS     : {DIM}{ios_file_rel} → {ios_struct}{RESET}")

    file_found, has_ck, ios_keys = extract_ios_json_keys(swift_path, ios_struct)

    if not file_found:
        print(f"  {RED}FILE NOT FOUND{RESET}: {swift_path}")
        FAIL_COUNT += 1
        continue

    if ios_struct not in open(swift_path).read():
        print(f"  {RED}STRUCT NOT FOUND{RESET}: {ios_struct!r} not in {ios_file_rel}")
        FAIL_COUNT += 1
        continue

    if not has_ck:
        print(f"  {DIM}NOTE: No CodingKeys — using property names as JSON keys{RESET}")

    known_raw = model.get("known_mismatches", {})
    # Support both legacy flat-list and new {field: {reason, note}} dict format
    if isinstance(known_raw, list):
        known = {k: {} for k in known_raw}
    else:
        known = known_raw
    fields = model.get("fields", {})

    model_unexpected = False   # any mismatch NOT in known_mismatches
    model_has_known  = False   # any mismatch that IS in known_mismatches
    issues           = []

    # -- backend fields vs iOS keys --
    for field, info in fields.items():
        required = info.get("required", True)
        in_ios   = field in ios_keys
        is_known = field in known

        if in_ios:
            if verbose:
                issues.append((f"  {GREEN}OK   {RESET} {field}", "ok"))
        elif is_known:
            entry      = known.get(field) if isinstance(known.get(field), dict) else {}
            reason     = entry.get("reason", "")
            note       = entry.get("note", "documented — see notes")
            reason_tag = f"  [{reason}]" if reason else ""
            KNOWN_REASON_COUNTS[reason or "unclassified"] = KNOWN_REASON_COUNTS.get(reason or "unclassified", 0) + 1
            issues.append((f"  {DIM}KNOWN{RESET} {field}{reason_tag} — {note}", "known"))
            model_has_known = True
        elif required:
            issues.append((f"  {RED}FAIL {RESET} {field}  (required — missing from iOS CodingKeys)", "fail"))
            model_unexpected = True
        else:
            issues.append((f"  {YELLOW}WARN {RESET} {field}  (optional — not decoded by iOS)", "warn"))
            model_unexpected = True

    # -- iOS extras not in backend contract --
    extras = ios_keys - set(fields.keys())
    for extra in sorted(extras):
        is_known = extra in known
        if is_known:
            entry      = known.get(extra) if isinstance(known.get(extra), dict) else {}
            reason     = entry.get("reason", "")
            note       = entry.get("note", "iOS-only key — documented")
            reason_tag = f"  [{reason}]" if reason else ""
            KNOWN_REASON_COUNTS[reason or "unclassified"] = KNOWN_REASON_COUNTS.get(reason or "unclassified", 0) + 1
            issues.append((f"  {DIM}KNOWN{RESET} {extra}{reason_tag} — {note}", "known"))
            model_has_known = True
        else:
            issues.append((f"  {YELLOW}EXTRA{RESET} {extra} (iOS decodes this; not in backend contract)", "warn"))
            model_unexpected = True

    # Print issues (suppress "ok" lines unless --verbose)
    for line, kind in issues:
        if kind == "ok" and not verbose:
            continue
        print(line)

    # Per-model result
    if model_unexpected:
        print(f"  → {RED}FAIL{RESET}  (unexpected mismatch)")
        FAIL_COUNT += 1
    elif model_has_known:
        print(f"  → {YELLOW}PASS_WITH_EXCEPTIONS{RESET}  (documented + intentional)")
        EXCEPTION_COUNT += 1
    else:
        print(f"  → {GREEN}PASS{RESET}  (exact match)")
        PASS_COUNT += 1

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

total = PASS_COUNT + EXCEPTION_COUNT + FAIL_COUNT
print(f"\n{SEP}")
print(f"SUMMARY  {total} models checked")
print(f"  {GREEN}PASS{RESET}                 {PASS_COUNT}  — exact match")
print(f"  {YELLOW}PASS_WITH_EXCEPTIONS{RESET}  {EXCEPTION_COUNT}  — documented + intentional")
print(f"  {RED}FAIL{RESET}                 {FAIL_COUNT}  — unexpected mismatch")

if KNOWN_REASON_COUNTS:
    total_known = sum(KNOWN_REASON_COUNTS.values())
    print(f"\nKNOWN mismatch breakdown ({total_known} total):")
    for rsn, cnt in sorted(KNOWN_REASON_COUNTS.items(), key=lambda x: -x[1]):
        print(f"  {cnt:3d}  {rsn}")

if FAIL_COUNT > 0:
    print(f"\n{RED}OVERALL: FAIL{RESET}")
    print("  Unexpected mismatches found — add CodingKey cases or update known_mismatches.")
    sys.exit(1)
elif EXCEPTION_COUNT > 0:
    print(f"\n{YELLOW}OVERALL: PASS_WITH_EXCEPTIONS{RESET}")
    print("  All mismatches are documented in api_contract.json known_mismatches.")
    sys.exit(0)
else:
    print(f"\n{GREEN}OVERALL: PASS{RESET}")
    print("  All models are exact matches.")
    sys.exit(0)

PYTHON
