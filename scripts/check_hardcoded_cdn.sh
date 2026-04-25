#!/usr/bin/env bash
# check_hardcoded_cdn.sh
#
# Detect hardcoded external HTTPS URL string literals in Swift source.
# Prevents regressions where upload or API flows bypass the dynamic URL
# returned by the backend and hardcode a stale or fake CDN domain instead.
#
# What is flagged:
#   Any line containing "https://  in a Swift file that is not:
#     - A comment-only line (^whitespace//)
#     - localhost  (development backend, intentional)
#     - *.apple.com / developer.apple / apps.apple  (SDK/App Store refs)
#
# What is NOT flagged:
#   - localhost:8000 references (documented dev backend URL)
#   - Apple documentation URL references
#   - Relative CDN paths like /cdn/avatars/  (these are correct — dynamic)
#   - Email placeholder strings like "you@example.com"  (not https://)
#
# Usage:  scripts/check_hardcoded_cdn.sh [search_root]
# Exit 0: clean. Exit 1: violation found.

set -euo pipefail
SEARCH_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

RESULT=$(
    find "$SEARCH_ROOT" -name "*.swift" \
        -not -path "*/Products/*" \
        -not -path "*/.git/*" \
        -print0 \
    | xargs -0 grep -nE '"https://[[:alnum:]]' 2>/dev/null \
    | grep -v ':[0-9]*:[[:space:]]*//'  \
    | grep -v 'localhost'               \
    | grep -v '\.apple\.com'           \
    | grep -v 'developer\.apple'       \
    | grep -v 'apps\.apple'            \
    || true
)

if [[ -z "$RESULT" ]]; then
    echo "✅  check_hardcoded_cdn: PASS"
    exit 0
fi

echo "❌  check_hardcoded_cdn: FAIL — hardcoded external URL(s) detected:"
echo "$RESULT" | while IFS= read -r line; do echo "  $line"; done
echo ""
echo "  Fix: use dynamic URLs from backend responses (e.g. FileUploadToken.fileURL)"
echo "  or configuration-backed base URLs (APIConfig.baseURL)."
echo "  To allow a specific URL, add a targeted grep -v exclusion above with justification."
exit 1
