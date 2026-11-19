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
# rep TEXT N -> TEXT repeated N times
rep() {
  local out="" i=0
  while [ "$i" -lt "$2" ]; do
    out="$out$1"
    i=$((i + 1))
  done
  printf '%s' "$out"
}
U="_"
# EntregaYa key SHAPE only: 2 lower, 2 lower, 4 lower (underscore-separated), then 20+
# mixed alphanumerics. Letters chosen by this test, never the real prefix or key.
KEY_FIX="$(rep z 2)$U$(rep q 2)$U$(rep z 4)$U$(rep Fx7 6)Qa"   # 20-character tail
KEY_FIX2="$(rep m 2)$U$(rep w 2)$U$(rep k 4)$U$(rep R4d 9)"    # 27-character tail
KEY_NEAR="$(rep z 2)$U$(rep q 2)$U$(rep z 4)$U$(rep Fx7 6)Q"   # 19-character tail: not the shape
PEM_DASH="$(rep - 5)"
PEM_FIX="${PEM_DASH}BEGIN RSA PRIVATE KEY${PEM_DASH}"
PEM_FIX2="${PEM_DASH}BEGIN OPENSSH PRIVATE KEY${PEM_DASH}"
PEM_PUBLIC="${PEM_DASH}BEGIN PUBLIC KEY${PEM_DASH}"
PEM_CERT="${PEM_DASH}BEGIN CERTIFICATE${PEM_DASH}"
SCHEME="force"
TOK_PART="5Aep$(rep T9 15)"
TOK_PART2="5Aep$(rep q8W 9)"
SFDX_FIX="${SCHEME}://PlatformCLI::${TOK_PART}@example.my.salesforce.com"
SFDX_FIX2="${SCHEME}://SalesforceDevelopmentExperience:${TOK_PART2}:refresh@test.salesforce.com"
SFDX_NEAR="${SCHEME}://login.salesforce.com"
ASSIGN_KEY="consumer$(printf 'S')ecret"
ASSIGN_VAL="$(rep Kw3 6)"
PLACEHOLDER_VAL="not-set-enter-the-key-in-setup"
# Values for the rules added in the fix round (CODE-001 / CODE-003), all from parts.
OAUTH_TAG="oauth$(printf 'T')oken"
OAUTH_REFRESH_TAG="oauthRefresh$(printf 'T')oken"
TOKEN_VAL="$(rep Hq4 7)"
CMDT_FIELD="Api$U$(printf 'K')ey__c"
CMDT_VAL="$(rep Ng6 7)"
ENV_VAL="$(rep Vb2 6)"
YAML_VAL="$(rep Yy5 5)"
BEARER_WORD="Bear$(printf 'e')r"
BEARER_VAL="$(rep Zt8 8)"
BEARER_VAL2="$(rep Mc3 7)Xp"
APIKEY_HDR="x-api-$(printf 'k')ey"
APIKEY_VAL="$(rep Jd7 7)"
JWT_HEAD="e$(printf 'y')J$(rep hb 9)"
JWT_FIX="${JWT_HEAD}.e$(printf 'y')J$(rep Pa1 6).$(rep sG 8)"
JSON_TOKEN_KEY="to$(printf 'k')en"
JSON_TOKEN_VAL="$(rep Wq9 7)"
DOLLAR_VAL="\$$(rep Pw9 4)x"   # a literal password whose first character is "$"
SID_FIX="00D$(rep A1 7)A!$(rep Ab9 12)"
P12_MARK="$(rep Bn5 5)"

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

# put FILE CONTENT -> writes CONTENT (plus a newline) to FILE, creating its directory
put() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}

# refused NAME FILE LINE RULE VALUE
# FILE is already written (the secret on LINE). Stages it plus an unformatted JSON, commits
# through the hook and checks: refused, file:line rule named, value never printed,
# lint-staged ran. LINE 0 means the whole file (filename rule).
refused() {
  local name="$1" file="$2" line="$3" rule="$4" value="$5"
  local head_before out rc
  head_before="$(git rev-parse HEAD)"
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

# accepted NAME -> the files already written (a near miss, a reference or a placeholder) are
# committed through the hook: no false positive.
accepted() {
  local name="$1" head_before out rc
  head_before="$(git rev-parse HEAD)"
  git add -A
  out="$(git commit -q -m "$name" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$(git rev-parse HEAD)" != "$head_before" ]; then
    pass "$name: accepted (not a secret)"
  else
    fail "$name: accepted (not a secret) (rc=$rc): $(printf '%s' "$out" | grep -E ' [A-Z0-9-]+$' | head -3)"
  fi
  git reset -q --hard HEAD
  git clean -fdq
}

# scan_refuses NAME EXPECTED VALUE -> runs secret-scan.sh --staged directly over what is staged
# (no hook, so paths lint-staged cannot handle are still tested) and checks exit 1, the
# EXPECTED "file:line RULE" text and no value.
scan_refuses() {
  local name="$1" expected="$2" value="$3" out rc
  out="$(bash scripts/checks/secret-scan.sh --staged 2>&1)"
  rc=$?
  if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qF -e "$expected" &&
    ! printf '%s\n' "$out" | grep -qF -e "$value"; then
    pass "$name: --staged reports $expected (exit 1, no value)"
  else
    fail "$name: --staged reports $expected (exit 1, no value) (rc=$rc)"
  fi
  git reset -q --hard HEAD
  git clean -fdq
}

# ---- the original rules, two positives each
put docs/handoff.txt "$(printf 'Ticket\n\nAPI key: %s (test env)' "$KEY_FIX")"
refused "entregaya-key-shape" "docs/handoff.txt" 3 "ENTREGAYA-KEY-SHAPE" "$KEY_FIX"
put docs/handoff2.txt "$(printf 'key=%s' "$KEY_FIX2")"
refused "entregaya-key-shape (27-character tail)" "docs/handoff2.txt" 1 "ENTREGAYA-KEY-SHAPE" "$KEY_FIX2"
put keys/server.txt "$(printf 'material\n%s\nAAAA' "$PEM_FIX")"
refused "pem-private-key" "keys/server.txt" 2 "PEM-PRIVATE-KEY" "$PEM_FIX"
put keys/deploy.txt "$(printf '%s\nAAAA' "$PEM_FIX2")"
refused "pem-private-key (OPENSSH)" "keys/deploy.txt" 1 "PEM-PRIVATE-KEY" "$PEM_FIX2"
put auth/url.txt "$SFDX_FIX"
refused "sfdx-auth-url" "auth/url.txt" 1 "SFDX-AUTH-URL" "$TOK_PART"
put auth/url2.txt "$(printf 'export SFDX_AUTH_URL=%s' "$SFDX_FIX2")"
refused "sfdx-auth-url (refresh token form)" "auth/url2.txt" 1 "SFDX-AUTH-URL" "$TOK_PART2"
put app/settings.sh "$(printf '#!/bin/sh\n%s="%s"' "$ASSIGN_KEY" "$ASSIGN_VAL")"
refused "consumer-secret-assignment" "app/settings.sh" 2 "SECRET-ASSIGNMENT" "$ASSIGN_VAL"
put app/demo.connectedApp-meta.xml "$(printf '<ConnectedApp>\n  <oauthConfig>\n    <%s>%s</%s>\n  </oauthConfig>\n</ConnectedApp>' "$ASSIGN_KEY" "$ASSIGN_VAL" "$ASSIGN_KEY")"
refused "consumer-secret-xml" "app/demo.connectedApp-meta.xml" 3 "SECRET-ASSIGNMENT" "$ASSIGN_VAL"

# ---- CODE-001: secret kinds this repository can hold
put nc/Legacy.namedCredential-meta.xml "$(printf '<NamedCredential>\n  <%s>%s</%s>\n</NamedCredential>' "$OAUTH_TAG" "$TOKEN_VAL" "$OAUTH_TAG")"
refused "legacy named credential oauth token" "nc/Legacy.namedCredential-meta.xml" 2 "SECRET-ASSIGNMENT" "$TOKEN_VAL"
put nc/Legacy2.namedCredential-meta.xml "$(printf '<NamedCredential>\n  <protocol>Oauth</protocol>\n  <%s>%s</%s>\n</NamedCredential>' "$OAUTH_REFRESH_TAG" "$TOKEN_VAL" "$OAUTH_REFRESH_TAG")"
refused "legacy named credential oauth refresh token" "nc/Legacy2.namedCredential-meta.xml" 3 "SECRET-ASSIGNMENT" "$TOKEN_VAL"
put cmdt/Settings.Default.md-meta.xml "$(printf '<CustomMetadata>\n  <values>\n    <field>%s</field>\n    <value xsi:type="xsd:string">%s</value>\n  </values>\n</CustomMetadata>' "$CMDT_FIELD" "$CMDT_VAL")"
refused "cmdt key value on the line after its field" "cmdt/Settings.Default.md-meta.xml" 4 "SECRET-ASSIGNMENT" "$CMDT_VAL"
put .env.example "$(printf '# local settings\nAPI_KEY=%s' "$ENV_VAL")"
refused "unquoted env assignment" ".env.example" 2 "SECRET-ASSIGNMENT" "$ENV_VAL"
put config/app.yml "$(printf 'db:\n  password: %s' "$YAML_VAL")"
refused "unquoted yaml password" "config/app.yml" 2 "SECRET-ASSIGNMENT" "$YAML_VAL"
put scripts/call.sh "$(printf '#!/bin/sh\ncurl -H "Authorization: %s %s" https://example.invalid/x' "$BEARER_WORD" "$BEARER_VAL")"
refused "bearer header literal (curl)" "scripts/call.sh" 2 "BEARER-TOKEN" "$BEARER_VAL"
put web/call.js "$(printf 'const h = { Authorization: "%s %s" };' "$BEARER_WORD" "$BEARER_VAL2")"
refused "bearer header literal (js)" "web/call.js" 1 "BEARER-TOKEN" "$BEARER_VAL2"
put web/key.js "$(printf 'req.setHeader("%s", "%s");' "$APIKEY_HDR" "$APIKEY_VAL")"
refused "x-api-key header literal" "web/key.js" 1 "SECRET-ASSIGNMENT" "$APIKEY_VAL"
put docs/jwt.txt "$(printf 'id token\n%s' "$JWT_FIX")"
refused "jwt" "docs/jwt.txt" 2 "JWT" "$JWT_FIX"
put data/resp.json "$(printf '{ "%s": "%s" }' "$JSON_TOKEN_KEY" "$JSON_TOKEN_VAL")"
refused "json token value" "data/resp.json" 1 "SECRET-ASSIGNMENT" "$JSON_TOKEN_VAL"
put app/login.sh "$(printf '#!/bin/sh\npassword='"'"'%s'"'"'' "$DOLLAR_VAL")"
refused "password starting with a dollar sign" "app/login.sh" 2 "SECRET-ASSIGNMENT" "$DOLLAR_VAL"
put docs/sid.txt "$(printf 'session %s' "$SID_FIX")"
refused "salesforce access token" "docs/sid.txt" 1 "SF-ACCESS-TOKEN" "$SID_FIX"

# ---- CODE-003: secret files by name, binary content included
put .env.local "$(printf 'MODE=dev')"
refused "env.local file" ".env.local" 0 "SECRET-FILE" "MODE=dev"
printf 'P\000K\001%s\000\002' "$P12_MARK" >client.p12
refused "binary keystore (.p12)" "client.p12" 0 "SECRET-FILE" "$P12_MARK"
put certs/server.key "$(printf 'material')"
refused "private key file (.key)" "certs/server.key" 0 "SECRET-FILE" "material"
printf '\000\001%s\000' "$P12_MARK" >store.jks
refused "java keystore (.jks)" "store.jks" 0 "SECRET-FILE" "$P12_MARK"

# ---- near misses, references and placeholders are accepted (no false positive)
put docs/near.txt "$(printf 'id: %s' "$KEY_NEAR")"
accepted "key shape with a 19-character tail"
put keys/public.txt "$(printf '%s\nAAAA\n%s\nBBBB' "$PEM_PUBLIC" "$PEM_CERT")"
accepted "PUBLIC KEY and CERTIFICATE headers"
put auth/login.txt "$(printf 'instance %s' "$SFDX_NEAR")"
accepted "force:// with no credentials"
put web/merge.js "$(printf 'req.setHeader("Authorization", "%s {!$Credential.Password}");\nreq.setHeader("Authorization", "%s " + key);' "$BEARER_WORD" "$BEARER_WORD")"
accepted "bearer from a Named Credential merge field or a variable"
put app/env.sh "$(printf '#!/bin/sh\npassword="$DB_PASSWORD"\n%s="${CONSUMER_SECRET}"' "$ASSIGN_KEY")"
accepted "environment variable references"
put .env.example "$(printf 'API_KEY=changeme\nPASSWORD=\nTOKEN=${TOKEN}')"
accepted "env template with placeholders"
put cmdt/Other.Default.md-meta.xml "$(printf '<CustomMetadata>\n  <values>\n    <field>Label_Text__c</field>\n    <value xsi:type="xsd:string">%s</value>\n  </values>\n</CustomMetadata>' "$CMDT_VAL")"
accepted "cmdt value of a field that is not a key"
put config/oauth.yml "$(printf 'oauth:\n  tokenUrl: https://example.invalid/oauth2/%s\n  tokenType: bearer' "$JSON_TOKEN_KEY")"
accepted "yaml names that only start with token"

# ---- CODE-002: staged paths with a tab or a newline are scanned (escaped in the output)
TAB_PATH="$(printf 'notes\tkey.txt')"
printf 'k = %s\n' "$KEY_FIX" >"$TAB_PATH"
git add -A
scan_refuses "staged path with a tab" 'notes\tkey.txt:1 ENTREGAYA-KEY-SHAPE' "$KEY_FIX"
NL_PATH="$(printf 'notes\nkey.txt')"
printf 'k = %s\n' "$KEY_FIX" >"$NL_PATH"
git add -A
scan_refuses "staged path with a newline" 'notes\nkey.txt:1 ENTREGAYA-KEY-SHAPE' "$KEY_FIX"

# --tree over the temporary repository finds a committed secret and a committed secret file,
# without the value
printf 'k = %s\n' "$KEY_FIX" >leak.txt
printf '\000\001%s\000' "$P12_MARK" >leak.pfx
git add leak.txt leak.pfx
git -c core.hooksPath=/dev/null commit -q -m "bypass hook to test --tree" >/dev/null 2>&1
tree2_out="$(bash scripts/checks/secret-scan.sh --tree 2>&1)"
tree2_rc=$?
if [ "$tree2_rc" -eq 1 ] && printf '%s\n' "$tree2_out" | grep -qF "leak.txt:1 ENTREGAYA-KEY-SHAPE" &&
  ! printf '%s\n' "$tree2_out" | grep -qF -e "$KEY_FIX"; then
  pass "--tree reports a committed key shape (exit 1, file:line rule, no value)"
else
  fail "--tree reports a committed key shape (rc=$tree2_rc)"
fi
if printf '%s\n' "$tree2_out" | grep -qF "leak.pfx:0 SECRET-FILE"; then
  pass "--tree reports a committed keystore file (SECRET-FILE)"
else
  fail "--tree reports a committed keystore file (SECRET-FILE)"
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "selftest: all checks passed"
  exit 0
fi
echo "selftest: $FAILS failure(s)"
exit 1
