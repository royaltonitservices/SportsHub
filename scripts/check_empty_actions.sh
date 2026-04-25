#!/usr/bin/env bash
# check_empty_actions.sh
#
# Detect .swipeActions closures that contain no Button call.
# An empty .swipeActions block presents a swipe affordance that does nothing —
# the pre-Phase-1 violation in MessagesListView (dead swipe-to-delete).
#
# Two patterns caught:
#   1. Inline empty:  .swipeActions { }  on a single line
#   2. Block empty:   .swipeActions {    with no Button() within the next 8 lines
#
# Note: alert dismiss buttons (Button("OK") { }) are NOT targeted here because
# they are intentional and correct. Only .swipeActions is checked.
#
# Usage:  scripts/check_empty_actions.sh [search_root]
# Exit 0: clean. Exit 1: violation found.

set -euo pipefail
SEARCH_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FAIL=0

while IFS= read -r -d '' file; do
    violations=$(awk -v f="$file" '
        BEGIN { swipe_line = 0; has_button = 0 }

        # Pattern 1: inline empty  .swipeActions { }
        /\.swipeActions[[:space:]]*\{[[:space:]]*\}/ {
            printf "  %s:%d: empty .swipeActions closure (inline)\n", f, NR
        }

        # Pattern 2: block — detect open, then check for Button within 8 lines
        /\.swipeActions/ && !/\{[[:space:]]*\}/ {
            swipe_line = NR
            has_button = 0
        }

        swipe_line > 0 && NR > swipe_line {
            if (/Button[[:space:]]*\(/) has_button = 1

            # Closing brace or exceeded window
            if (NR - swipe_line >= 8) {
                if (!has_button) {
                    printf "  %s:%d: .swipeActions block has no Button within 8 lines\n", f, swipe_line
                }
                swipe_line = 0
            }
        }
    ' "$file")
    if [[ -n "$violations" ]]; then
        echo "$violations"
        FAIL=1
    fi
done < <(find "$SEARCH_ROOT" -name "*.swift" \
    -not -path "*/Products/*" \
    -not -path "*/.git/*" \
    -print0)

if [[ $FAIL -eq 0 ]]; then
    echo "✅  check_empty_actions: PASS"
    exit 0
fi

echo ""
echo "❌  check_empty_actions: FAIL"
echo "    .swipeActions must contain at least one Button."
echo "    Remove the .swipeActions block entirely if no action is implemented."
exit 1
