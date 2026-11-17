#!/usr/bin/env bash
# Sets the RutaCargo site guest user's time zone to America/Mexico_City
# (AC-F.9, odd/tasks/foundation.md). Idempotent: running it again changes nothing.
# Run it after the site metadata in force-app is deployed.
#
# Usage: scripts/setup/site-guest-user.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

out="$(sf apex run --file "$ROOT/scripts/setup/site-guest-user.apex" --target-org "$ORG" --json 2>/dev/null || true)"
compiled="$(jq -r '.result.compiled // false' <<<"$out" 2>/dev/null || echo false)"
success="$(jq -r '.result.success // false' <<<"$out" 2>/dev/null || echo false)"
if [[ "$compiled" != "true" || "$success" != "true" ]]; then
    echo "site-guest-user: failed in $ORG" >&2
    jq -r '.result.compileProblem // empty, .result.exceptionMessage // empty, .message // empty' <<<"$out" >&2 2>/dev/null || true
    exit 1
fi
jq -r '.result.logs // ""' <<<"$out" | grep 'USER_DEBUG' | grep -o 'site-guest-user: .*' || true
echo "site-guest-user: done in $ORG"
