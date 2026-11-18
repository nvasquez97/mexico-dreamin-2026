#!/usr/bin/env bash
# Repository secret scan (SEC-001, policy X14 / P2).
#
# Refuses secret-shaped values. It prints only "file:line RULE" per finding, never the
# matched text, so the output itself never leaks a secret.
#
# Usage:
#   bash scripts/checks/secret-scan.sh --staged   files staged for the commit, content read
#                                                 from the git index (used by .husky/pre-commit)
#   bash scripts/checks/secret-scan.sh --tree     every tracked file at HEAD (gate / audit)
#
# Exit: 0 no findings · 1 findings · 2 usage or git error.
#
# Rules:
#   ENTREGAYA-KEY-SHAPE  a value with the SHAPE of the EntregaYa API key: three lowercase
#                        groups of 2, 2 and 4 letters joined by underscores, an underscore,
#                        then at least 20 letters/digits. Only the shape is encoded (lengths
#                        and character classes), never the real prefix text, so this file
#                        never matches itself (H6).
#   PEM-PRIVATE-KEY      a PEM private-key header (RSA, EC, OPENSSH, DSA, ENCRYPTED, PGP ...).
#   SFDX-AUTH-URL        an SFDX auth URL: the force scheme with credentials before an "@".
#   SECRET-ASSIGNMENT    consumerSecret / clientSecret / password / api key / token-like
#                        names assigned a quoted literal of 8+ characters (key = "v",
#                        key: 'v', "key": "v") or an XML element holding a literal
#                        (<consumerSecret>v</consumerSecret>). Values that are references
#                        or placeholders ($VAR, ${..}, {!..}, <..>, %..%, "not-set...",
#                        "placeholder", "changeme", "example", "redacted", "your-...", "xxxx",
#                        "****") are not literals and are not reported.
#
# Allow-list (by path only, where unavoidable): the pattern-definition files of the
# security tooling under .claude/skills/sf-security-audit/ may be listed in ALLOW_PATHS
# below if a vendored update ever makes them match. It is EMPTY today: every tracked file,
# including that tooling and this script, scans clean.
#
# Limits: binary files are skipped (git grep -I); unquoted literals (key=value without
# quotes) are not reported, because in code they are almost always variable names.
set -u

ALLOW_PATHS=() # e.g. ':(exclude).claude/skills/sf-security-audit/scripts/<file>' - none needed today

usage() {
  echo "usage: bash scripts/checks/secret-scan.sh --staged | --tree" >&2
  exit 2
}

[ $# -eq 1 ] || usage
MODE="$1"
case "$MODE" in
  --staged | --tree) ;;
  *) usage ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "secret-scan: not inside a git repository" >&2
  exit 2
}
cd "$ROOT" || exit 2

WORK="$(mktemp -d "${TMPDIR:-/tmp}/secret-scan.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM
HITS="$WORK/hits"
: >"$HITS"

if [ "$MODE" = "--tree" ]; then
  git rev-parse -q --verify HEAD >/dev/null || {
    echo "secret-scan: HEAD does not exist (no commit yet)" >&2
    exit 2
  }
  SOURCE=(HEAD)
  STRIP="HEAD:"
  SCOPE="tracked files at HEAD"
else
  SOURCE=(--cached)
  STRIP=""
  SCOPE="staged files"
  # Paths added, copied, modified, renamed or type-changed in the index (deletions carry no content).
  git -c core.quotepath=off diff --cached --name-only -z --diff-filter=ACMRT >"$WORK/staged.z" || exit 2
  tr '\0' '\n' <"$WORK/staged.z" >"$WORK/staged"
  if [ ! -s "$WORK/staged" ]; then
    echo "secret-scan: 0 findings in $SCOPE"
    exit 0
  fi
fi

# Shape pieces of the EntregaYa key, assembled here so the pattern is data, not a sample.
L='[a-z]'
KEY_SHAPE="(^|[^A-Za-z0-9])${L}{2}_${L}{2}_${L}{4}_[A-Za-z0-9]{20,}"
PEM_HEADER='-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----'
SFDX_URL="force://[A-Za-z0-9._~-]+:[^@[:space:]'\"]{10,}@[A-Za-z0-9.-]+"
NAMES='(consumer_?secret|client_?secret|passw(or)?d|api_?key|private_?key|access_?token|refresh_?token|auth_?token|secret)'
QUOTED="${NAMES}[A-Za-z0-9_]*['\"]?[[:space:]]*[:=][[:space:]]*['\"][^'\"[:space:]]{8,}['\"]"
XML_ELEM="<${NAMES}>[^<[:space:]]{8,}</"

# grep_rule RULE [git grep pattern options...] -> appends "path<TAB>line<TAB>RULE<TAB>content"
# to $HITS. Content stays inside the work dir (deleted on exit); it is never printed.
grep_rule() {
  local rule="$1"
  shift
  git -c core.quotepath=off grep --no-color -I -n --null "$@" "${SOURCE[@]}" -- . "${ALLOW_PATHS[@]+"${ALLOW_PATHS[@]}"}" \
    >"$WORK/raw" 2>"$WORK/err"
  local rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "secret-scan: git grep failed for $rule" >&2
    exit 2
  fi
  tr '\0' '\001' <"$WORK/raw" | awk -F'\001' -v rule="$rule" -v strip="$STRIP" '
    {
      path = $1
      if (strip != "" && index(path, strip) == 1) path = substr(path, length(strip) + 1)
      content = substr($0, length($1) + length($2) + 3)
      printf "%s\t%s\t%s\t%s\n", path, $2, rule, content
    }' >>"$HITS"
}

grep_rule ENTREGAYA-KEY-SHAPE -E -e "$KEY_SHAPE"
grep_rule PEM-PRIVATE-KEY -E -e "$PEM_HEADER"
grep_rule SFDX-AUTH-URL -E -e "$SFDX_URL"
grep_rule SECRET-ASSIGNMENT -E -i -e "$QUOTED" -e "$XML_ELEM"

# Filter: staged paths only (--staged); for SECRET-ASSIGNMENT keep only literal values.
# Prints "file:line RULE", nothing else.
awk -F'\t' -v mode="$MODE" -v staged="$WORK/staged" '
  function placeholder(v) {
    if (v ~ /^[$%{<@(]/) return 1
    if (v ~ /not-set|placeholder|changeme|change[-_]me|example|dummy|sample|redacted|your[-_]|xxxx|\*\*\*\*|enter[-_]the|<|>/) return 1
    return 0
  }
  function literal_secret(s,    l, rest, m, v, q) {
    l = tolower(s)
    rest = l
    while (match(rest, /(consumer_?secret|client_?secret|passw(or)?d|api_?key|private_?key|access_?token|refresh_?token|auth_?token|secret)[a-z0-9_]*["\047]?[ \t]*[:=][ \t]*["\047][^"\047 \t]+["\047]/)) {
      m = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      sub(/^[^:=]*[:=][ \t]*/, "", m)
      v = substr(m, 2, length(m) - 2)
      if (length(v) >= 8 && !placeholder(v)) return 1
    }
    rest = l
    while (match(rest, /<(consumer_?secret|client_?secret|passw(or)?d|api_?key|private_?key|access_?token|refresh_?token|auth_?token|secret)>[^< \t]+<\//)) {
      m = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      sub(/^<[^>]*>/, "", m)
      v = substr(m, 1, length(m) - 2)
      if (length(v) >= 8 && !placeholder(v)) return 1
    }
    return 0
  }
  BEGIN {
    if (mode == "--staged") {
      while ((getline p < staged) > 0) keep[p] = 1
      close(staged)
    }
  }
  {
    path = $1; line = $2; rule = $3
    content = substr($0, length($1) + length($2) + length($3) + 4)
    if (mode == "--staged" && !(path in keep)) next
    if (rule == "SECRET-ASSIGNMENT" && !literal_secret(content)) next
    key = path ":" line " " rule
    if (key in seen) next
    seen[key] = 1
    print key
  }' "$HITS" | sort -t: -k1,1 -k2,2n >"$WORK/findings"

COUNT="$(wc -l <"$WORK/findings" | tr -d ' ')"
if [ "$COUNT" -eq 0 ]; then
  echo "secret-scan: 0 findings in $SCOPE"
  exit 0
fi
cat "$WORK/findings"
echo "secret-scan: $COUNT finding(s) in $SCOPE - values are never printed. Remove the value" \
  "(use a Named/External Credential or a local, git-ignored file) and rotate it if it was ever pushed." >&2
exit 1
