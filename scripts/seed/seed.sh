#!/usr/bin/env bash
# Loads the RutaCargo test data into an org. Safe to run more than once.
# Usage: scripts/seed/seed.sh <org-alias>
# The site users' password is generated on every run and never saved in the repository.
# It is printed once, or written to the file named by PASSWORD_FILE (mode 600) when that is set.
set -euo pipefail
ORG="${1:?Usage: scripts/seed/seed.sh <org-alias>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run() {
  local file="$1"
  local out
  out="$(sf apex run --file "$file" --target-org "$ORG" --json)"
  if ! echo "$out" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read(),strict=False); r=d.get("result",{}); sys.exit(0 if r.get("success") else 1)'; then
    echo "FAILED: $(basename "$file")"
    echo "$out" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read(),strict=False); r=d.get("result",{}); print(r.get("compileProblem") or r.get("exceptionMessage") or d.get("message"))'
    exit 1
  fi
  echo "$out" | python3 -c 'import json,sys,re; d=json.loads(sys.stdin.read(),strict=False); print("\n".join(l for l in re.findall(r"SEED\d (?:OK|SKIPPED)[^\n|]*", d["result"].get("logs","")) if "\x27" not in l))'
}

PASSWORD="Rc$(openssl rand -hex 6)9x"
sed "s/__SEED_PASSWORD__/${PASSWORD}/" "$DIR/03-site-users.apex" > "$TMP/03-site-users.apex"

run "$DIR/01-internal-users.apex"
run "$DIR/02-customers-and-shipments.apex"
run "$TMP/03-site-users.apex"
echo "Site users: ana.lopez@abarrotes-acme.example and marta.ruiz@globex-farma.example"
if [[ -n "${PASSWORD_FILE:-}" ]]; then
  (umask 077; printf '%s\n' "$PASSWORD" > "$PASSWORD_FILE")
  echo "Password for both written to $PASSWORD_FILE"
else
  echo "Password for both (shown once, store it safely): ${PASSWORD}"
fi
