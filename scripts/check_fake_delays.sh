#!/usr/bin/env bash
# check_fake_delays.sh
#
# Detect Task.sleep used as a fake delay stub: a sleep immediately followed
# (within 5 source lines) by a throw in a non-retry context.
# This is the canonical placeholder pattern from pre-Phase-1 where a sleep
# simulates a real operation without performing it.
#
# API coverage:
#   Matches both Task.sleep(nanoseconds:) (Swift 5.5) and the Duration-based
#   Task.sleep(for:) API (Swift 5.7+) — the regex is Task\.sleep regardless
#   of argument label.  Post-success UX delays using either form are fine as
#   long as no throw follows within 5 lines.
#
# Legitimate patterns are excluded:
#   Lines containing retry / backoff / maxRetries / attempt keywords.
#   Standalone continue/break after sleep (loop-control → retry pattern).
#
# KNOWN EXCLUSION — OAuthManager.swift
#   signInWithGoogle() is an intentional, documented stub.
#   .googleSignIn is gated as .unavailableHidden in CapabilityRegistry.
#   Remove this exclusion only when Google Sign-In is fully implemented.
#
# Usage:  scripts/check_fake_delays.sh [search_root]
# Exit 0: clean. Exit 1: violation found.

set -euo pipefail
SEARCH_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
FAIL=0

while IFS= read -r -d '' file; do
    violations=$(awk -v f="$file" '
        BEGIN { sleep_line = 0 }

        /Task\.sleep/ {
            if ($0 !~ /isTransientError|maxRetries|retry|backoff|attempt|exponential/) {
                sleep_line = NR
            }
            next
        }

        sleep_line > 0 {
            if (NR - sleep_line > 5) {
                sleep_line = 0
            } else if (/^[[:space:]]*continue[[:space:]]*$/ || /^[[:space:]]*break[[:space:]]*$/) {
                # Loop-control after sleep means this is retry/backoff, not a fake delay
                sleep_line = 0
            } else if (/throw / && !/^[[:space:]]*\/\//) {
                printf "  %s:%d: Task.sleep (line %d) followed by throw — likely fake delay stub\n", \
                    f, NR, sleep_line
                sleep_line = 0
            }
        }
    ' "$file")
    if [[ -n "$violations" ]]; then
        echo "$violations"
        FAIL=1
    fi
done < <(find "$SEARCH_ROOT" -name "*.swift" \
    -not -name "OAuthManager.swift" \
    -not -path "*/Products/*" \
    -not -path "*/.git/*" \
    -print0)

if [[ $FAIL -eq 0 ]]; then
    echo "✅  check_fake_delays: PASS"
    exit 0
fi

echo ""
echo "❌  check_fake_delays: FAIL"
echo "    Remove Task.sleep from production action paths."
echo "    UX delays after a successful response are fine."
echo "    Delays that replace real work are not."
echo "    For documented stubs in gated features, add the file to the exclusion list above."
exit 1
