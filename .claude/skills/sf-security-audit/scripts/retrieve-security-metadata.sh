#!/usr/bin/env bash
# Retrieve security-relevant metadata from an org into an isolated directory (never into force-app),
# then run the heuristic scanner over it.
#
# Usage: retrieve-security-metadata.sh <org-alias> [output-dir]
# Read-only against the org: it only runs a Metadata API retrieve.
set -euo pipefail

ORG="${1:?usage: retrieve-security-metadata.sh <org-alias> [output-dir]}"
OUT="${2:-${TMPDIR:-/tmp}/sf-security-audit/$(date +%Y%m%d-%H%M%S)-${ORG}}"
DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUT"
echo "Retrieving security metadata from '${ORG}' into ${OUT}/metadata ..." >&2
sf project retrieve start \
  --manifest "$DIR/security-package.xml" \
  --target-org "$ORG" \
  --output-dir "$OUT/metadata" \
  --wait 30 \
  --json > "$OUT/retrieve-result.json" || {
  echo "Retrieve failed or partially failed; see ${OUT}/retrieve-result.json" >&2
}

node "$DIR/sf-security-scan.mjs" --format json --out "$OUT/org-scan.json" "$OUT/metadata"
node "$DIR/sf-security-scan.mjs" --format md --out "$OUT/org-scan.md" "$OUT/metadata"
echo "$OUT"
