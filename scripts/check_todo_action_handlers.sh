#!/usr/bin/env bash
# check_todo_action_handlers.sh
#
# Detect // TODO or // FIXME comments inside Button, .swipeActions,
# .onTapGesture, or .contextMenu action closures.
#
# A TODO inside an action closure means the affordance is visible to users
# but the action is not implemented — a silent dead end.
#
# Detection strategy:
#   awk tracks brace depth from the line an action keyword is seen.
#   Any TODO/FIXME comment within that closure is flagged.
#   Brace counting is approximate (ignores string literals containing braces)
#   but catches all practically observed patterns.
#
# Button forms covered:
#   Button("Title") { ... }        — Button followed by (
#   Button { ... } label: { ... }  — Button followed by {  (trailing-closure label form)
#   Button(role: .destructive) { } — also Button followed by (
#
# Not flagged:
#   - TODO/FIXME at function-declaration or file level (correct; e.g. OAuthManager)
#   - TODO inside comments that aren't in action closures
#   - Comment-only lines that trigger the action keyword match (e.g. // Button { )
#
# Usage:  scripts/check_todo_action_handlers.sh [search_root]
# Exit 0: clean. Exit 1: violation found.

set -euo pipefail
SEARCH_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FAIL=0

while IFS= read -r -d '' file; do
    violations=$(awk -v f="$file" '
        BEGIN { in_action = 0; depth = 0; action_line = 0 }
        {
            # Enter action context on non-comment lines that open a closure
            if (!in_action &&
                !/^[[:space:]]*\/\// &&
                (/Button[[:space:]]*[\({]/ || /\.swipeActions/ || /\.onTapGesture/ || /\.contextMenu/) &&
                /\{/) {
                in_action   = 1
                action_line = NR
                depth       = 0
            }

            if (in_action) {
                # Count brace delta for this line (rough; ignores string literals)
                line = $0
                for (i = 1; i <= length(line); i++) {
                    c = substr(line, i, 1)
                    if (c == "{") depth++
                    else if (c == "}") {
                        depth--
                        if (depth <= 0) { in_action = 0; break }
                    }
                }

                # Flag TODO/FIXME while still inside the closure
                if (in_action && /\/\/ *(TODO|FIXME)/) {
                    printf "  %s:%d: TODO/FIXME inside action closure (opened at line %d)\n", \
                        f, NR, action_line
                }
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
    echo "✅  check_todo_action_handlers: PASS"
    exit 0
fi

echo ""
echo "❌  check_todo_action_handlers: FAIL"
echo "    TODO/FIXME inside a user-facing action closure means the action"
echo "    is visible but not implemented. Either implement it or gate the"
echo "    affordance via CapabilityRegistry."
exit 1
