#!/usr/bin/env bash
# Re-sync the vendored Salesforce skills (github.com/forcedotcom/sf-skills) into .claude/skills.
# Usage: scripts/sync-sf-skills.sh [git-ref]   (default: main)
# Review the resulting diff before committing — upstream skills change frequently.
set -euo pipefail

REF="${1:-main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DST="$ROOT/.claude/skills"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SKILLS=(
  dx-code-analyzer-run
  dx-code-analyzer-configure
  dx-code-analyzer-custom-rule-create
  dx-org-analyze
  experience-lwc-security-validate
  integration-connectivity-connected-app-configure
  integration-connectivity-generate
  platform-apex-generate
  platform-encryption-configure
  platform-metadata-retrieve
  platform-permission-set-generate
  platform-sharing-owd-configure
  platform-sharing-rules-generate
  platform-soql-query
)

git clone --quiet --depth 1 --branch "$REF" https://github.com/forcedotcom/sf-skills.git "$TMP/sf-skills"
SHA="$(git -C "$TMP/sf-skills" rev-parse HEAD)"

for s in "${SKILLS[@]}"; do
  if [ ! -d "$TMP/sf-skills/skills/$s" ]; then
    echo "WARNING: $s no longer exists upstream (renamed or removed) — kept local copy" >&2
    continue
  fi
  rm -rf "${DST:?}/$s"
  cp -R "$TMP/sf-skills/skills/$s" "$DST/$s"
done
cp "$TMP/sf-skills/LICENSE.txt" "$DST/SF-SKILLS-LICENSE.txt"

sed -i.bak -E "s/^(- \*\*Commit:\*\* ).*/\1\`$SHA\` (ref \`$REF\`, synced $(date +%Y-%m-%d))/" "$DST/VENDORED.md"
rm -f "$DST/VENDORED.md.bak"
echo "Synced ${#SKILLS[@]} skills from forcedotcom/sf-skills@$SHA"
