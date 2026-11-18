#!/usr/bin/env bash
# Self-test of scripts/checks/secret-scan.sh and of the Husky pre-commit that runs it.
#
# AC-H4.1 (SEC-001, X14): Given the repository after `npm install`, When a commit stages a
# file containing a value shaped like the EntregaYa key (built at runtime from parts, never a
# real key), a PEM private-key header or an SFDX auth URL, Then the Husky pre-commit refuses it
# naming the file, line and rule and never the value, and lint-staged still runs; and
# scripts/checks/secret-scan.sh over the tracked tree at HEAD reports 0 findings.
#
# How: it scans this repository's tree at HEAD, then builds a temporary git repository with
# this repository's package.json, .husky/pre-commit, prettier config and secret-scan.sh,
# links node_modules, runs `npm run prepare` (what `npm install` runs: husky installs its
# hooks), and commits through the real hook. Every secret-shaped fixture is assembled at
# runtime from harmless parts, so no secret (and no secret-shaped text) is in this file.
# The temporary repository is deleted on exit.
#
# Usage: bash scripts/checks/tests/secret-scan-selftest.sh   (exit 0 = all checks pass)
set -u

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "selftest: not inside a git repository" >&2
  exit 2
}
SCAN="$ROOT/scripts/checks/secret-scan.sh"
FAILS=0
pass() { echo "PASS  $1"; }
fail() {
  echo "FAIL  $1"
  FAILS=$((FAILS + 1))
}

for need in "$ROOT/node_modules/.bin/husky" "$ROOT/node_modules/.bin/lint-staged" "$ROOT/node_modules/.bin/prettier"; do
  if [ ! -x "$need" ]; then
    echo "selftest: $need missing - run npm install first" >&2
    exit 2
  fi
done

# ---------------------------------------------------------------- 1. tree at HEAD is clean
if [ ! -f "$SCAN" ]; then
  fail "secret-scan.sh exists at scripts/checks/secret-scan.sh"
  echo "selftest: $FAILS failure(s)"
  exit 1
fi
tree_out="$(bash "$SCAN" --tree 2>&1)"
tree_rc=$?
if [ "$tree_rc" -eq 0 ] && printf '%s\n' "$tree_out" | grep -q '0 findings'; then
  pass "secret-scan.sh --tree over this repository at HEAD reports 0 findings"
else
  fail "secret-scan.sh --tree over this repository at HEAD reports 0 findings (rc=$tree_rc): $tree_out"
fi

# usage errors exit 2
bash "$SCAN" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 2 ] && pass "no argument exits 2 (usage)" || fail "no argument exits 2 (usage), got $rc"
bash "$SCAN" --bogus >/dev/null 2>&1
rc=$?
[ "$rc" -eq 2 ] && pass "unknown argument exits 2 (usage)" || fail "unknown argument exits 2 (usage), got $rc"

# ---------------------------------------------------------------- 2. fixtures from parts
# rep CHAR N -> CHAR repeated N times
rep() {
  local out="" i=0
  while [ "$i" -lt "$2" ]; do
    out="$out$1"
    i=$((i + 1))
  done
  printf '%s' "$out"
}
U="_"
# EntregaYa key SHAPE only: 2 lower, 2 lower, 4 lower (underscore-separated), then 20
# mixed alphanumerics. Letters chosen by this test, never the real prefix or key.
KEY_FIX="$(rep z 2)$U$(rep q 2)$U$(rep z 4)$U$(rep Fx7 6)Qa"
PEM_DASH="$(rep - 5)"
PEM_FIX="${PEM_DASH}BEGIN RSA PRIVATE KEY${PEM_DASH}"
SCHEME="force"
TOK_PART="5Aep$(rep T9 15)"
SFDX_FIX="${SCHEME}://PlatformCLI::${TOK_PART}@example.my.salesforce.com"
ASSIGN_KEY="consumer$(printf 'S')ecret"
ASSIGN_VAL="$(rep Kw3 6)"
PLACEHOLDER_VAL="not-set-enter-the-key-in-setup"

# ---------------------------------------------------------------- 3. temporary repository
TMP="$(mktemp -d "${TMPDIR:-/tmp}/secret-scan-selftest.XXXXXX")" || exit 2
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

cd "$TMP" || exit 2
unset HUSKY GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git init -q .
git config user.name "secret-scan selftest"
git config user.email "selftest@example.invalid"
git config commit.gpgsign false
mkdir -p .husky scripts/checks
cp "$ROOT/package.json" package.json
cp "$ROOT/.husky/pre-commit" .husky/pre-commit
cp "$SCAN" scripts/checks/secret-scan.sh
[ -f "$ROOT/.prettierrc" ] && cp "$ROOT/.prettierrc" .prettierrc
[ -f "$ROOT/.prettierignore" ] && cp "$ROOT/.prettierignore" .prettierignore
ln -s "$ROOT/node_modules" node_modules
printf 'node_modules\n' >.gitignore

# Given the repository after npm install: npm install runs "prepare" (husky).
npm run prepare --silent >/dev/null 2>&1
if [ "$(git config --get core.hooksPath)" = ".husky/_" ] && [ -x .husky/_/pre-commit ]; then
  pass "npm run prepare (npm install) enables the Husky pre-commit"
else
  fail "npm run prepare (npm install) enables the Husky pre-commit"
fi

UNFORMATTED_JSON='{"a":1,"b":[1,2]}'

# lint_ran FILE-SPEC -> 0 when prettier reformatted the staged/committed JSON
lint_ran() { git show "$1" 2>/dev/null | grep -q '"a": 1'; }

# ---- clean commit passes, and lint-staged runs (prettier formats the staged JSON)
printf '%s\n' "$UNFORMATTED_JSON" >data.json
printf '# Notes\n\npassword: "%s"\n' "$PLACEHOLDER_VAL" >notes.md
git add -A
clean_out="$(git commit -q -m "clean commit" 2>&1)"
clean_rc=$?
if [ "$clean_rc" -eq 0 ] && git rev-parse -q --verify HEAD >/dev/null; then
  pass "a clean commit (placeholder value included) passes the hook"
else
  fail "a clean commit passes the hook (rc=$clean_rc): $clean_out"
fi
if lint_ran HEAD:data.json; then
  pass "lint-staged runs in the hook (prettier formatted data.json in the clean commit)"
else
  fail "lint-staged runs in the hook (data.json was not formatted)"
fi

# refused NAME FILE LINE RULE CONTENT VALUE
# Stages FILE (CONTENT, the secret on LINE) plus an unformatted JSON, commits through the hook
# and checks: refused, file:line rule named, value never printed, lint-staged ran.
refused() {
  local name="$1" file="$2" line="$3" rule="$4" content="$5" value="$6"
  local head_before out rc
  head_before="$(git rev-parse HEAD)"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" >"$file"
  printf '%s\n' "$UNFORMATTED_JSON" >data2.json
  git add -A
  out="$(git commit -q -m "$name" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$(git rev-parse HEAD)" = "$head_before" ]; then
    pass "$name: the pre-commit refuses the commit"
  else
    fail "$name: the pre-commit refuses the commit (rc=$rc, the test commit was accepted)"
  fi
  if printf '%s\n' "$out" | grep -qF -e "$file:$line $rule"; then
    pass "$name: output names $file:$line $rule"
  else
    fail "$name: output names $file:$line $rule"
  fi
  if printf '%s\n' "$out" | grep -qF -e "$value"; then
    fail "$name: output never contains the value"
  else
    pass "$name: output never contains the value"
  fi
  if lint_ran :data2.json; then
    pass "$name: lint-staged still ran before the refusal"
  else
    fail "$name: lint-staged still ran before the refusal"
  fi
  git reset -q --hard HEAD
  git clean -fdq
}

refused "entregaya-key-shape" "docs/handoff.txt" 3 "ENTREGAYA-KEY-SHAPE" \
  "$(printf 'Ticket\n\nAPI key: %s (test env)' "$KEY_FIX")" "$KEY_FIX"
refused "pem-private-key" "keys/server.txt" 2 "PEM-PRIVATE-KEY" \
  "$(printf 'material\n%s\nAAAA\n' "$PEM_FIX")" "$PEM_FIX"
refused "sfdx-auth-url" "auth/url.txt" 1 "SFDX-AUTH-URL" \
  "$SFDX_FIX" "$TOK_PART"
refused "consumer-secret-assignment" "app/settings.sh" 2 "SECRET-ASSIGNMENT" \
  "$(printf '#!/bin/sh\n%s="%s"\n' "$ASSIGN_KEY" "$ASSIGN_VAL")" "$ASSIGN_VAL"
refused "consumer-secret-xml" "app/demo.connectedApp-meta.xml" 3 "SECRET-ASSIGNMENT" \
  "$(printf '<ConnectedApp>\n  <oauthConfig>\n    <%s>%s</%s>\n  </oauthConfig>\n</ConnectedApp>' "$ASSIGN_KEY" "$ASSIGN_VAL" "$ASSIGN_KEY")" "$ASSIGN_VAL"

# --tree over the temporary repository finds a committed secret, without the value
printf 'k = %s\n' "$KEY_FIX" >leak.txt
git add leak.txt
git -c core.hooksPath=/dev/null commit -q -m "bypass hook to test --tree" >/dev/null 2>&1
tree2_out="$(bash scripts/checks/secret-scan.sh --tree 2>&1)"
tree2_rc=$?
if [ "$tree2_rc" -eq 1 ] && printf '%s\n' "$tree2_out" | grep -qF "leak.txt:1 ENTREGAYA-KEY-SHAPE" &&
  ! printf '%s\n' "$tree2_out" | grep -qF -e "$KEY_FIX"; then
  pass "--tree reports a committed key shape (exit 1, file:line rule, no value)"
else
  fail "--tree reports a committed key shape (rc=$tree2_rc)"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "selftest: all checks passed"
  exit 0
fi
echo "selftest: $FAILS failure(s)"
exit 1
