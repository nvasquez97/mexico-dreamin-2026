#!/usr/bin/env bash
# Retrieve security-relevant metadata from an org into an isolated directory (never into force-app),
# in source format, then run the heuristic scanner over it.
#
# Usage: retrieve-security-metadata.sh <org-alias> [output-dir]
# Read-only against the org: it only runs a Metadata API retrieve.
#
# Why the detour: the Salesforce CLI resolves no metadata inside folders whose name starts with a dot
# (such as .security-reports/), and `retrieve --output-dir` only accepts folders inside the project.
# So the script retrieves in metadata format into a temporary folder, converts it to source format
# there, and copies the result to the output dir. The default output dir is the git-ignored
# .security-reports/org-retrieve/ folder of the project; a relative path is taken from the project root.
set -euo pipefail

ORG="${1:?usage: retrieve-security-metadata.sh <org-alias> [output-dir]}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../../../.." && pwd)"
[ -f "$ROOT/sfdx-project.json" ] || { echo "Cannot find sfdx-project.json at $ROOT" >&2; exit 1; }

OUT="${2:-.security-reports/org-retrieve/$(date +%Y%m%d-%H%M%S)-${ORG}}"
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
case "$OUT/" in "$ROOT"/force-app/*) echo "Refusing to write into force-app." >&2; exit 1 ;; esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
cd "$ROOT"

echo "Retrieving security metadata from '${ORG}' ..." >&2
sf project retrieve start \
  --manifest "$DIR/security-package.xml" \
  --target-org "$ORG" \
  --target-metadata-dir "$WORK/mdapi" \
  --unzip \
  --wait 30 \
  --json > "$OUT/retrieve-result.json" 2>/dev/null || {
  echo "Retrieve failed or partially failed; see ${OUT}/retrieve-result.json" >&2
}
# Components that do not exist in this org (for example Network without Experience Cloud) are reported
# as Failed in retrieve-result.json; the rest is still retrieved.

if [ -d "$WORK/mdapi" ]; then
  sf project convert mdapi --root-dir "$WORK/mdapi" --output-dir "$WORK/source" --json \
    > "$OUT/convert-result.json" 2>/dev/null || echo "Conversion failed; see ${OUT}/convert-result.json" >&2
fi
rm -rf "$OUT/metadata"
if [ -d "$WORK/source" ]; then
  cp -R "$WORK/source" "$OUT/metadata"
  echo "Retrieved $(find "$OUT/metadata" -type f | wc -l | tr -d ' ') files into ${OUT}/metadata" >&2
else
  mkdir -p "$OUT/metadata"
  echo "Nothing was retrieved; see ${OUT}/retrieve-result.json" >&2
fi

node "$DIR/sf-security-scan.mjs" --format json --out "$OUT/org-scan.json" "$OUT/metadata"
node "$DIR/sf-security-scan.mjs" --format md --out "$OUT/org-scan.md" "$OUT/metadata"
echo "$OUT"
