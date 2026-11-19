#!/usr/bin/env bash
# Repository secret scan (SEC-001, policy X14 / P2).
#
# Refuses secret-shaped values and secret files. It prints only "file:line RULE" per
# finding, never the matched text, so the output itself never leaks a secret.
#
# Usage:
#   bash scripts/checks/secret-scan.sh --staged   files staged for the commit, content read
#                                                 from the git index (used by .husky/pre-commit)
#   bash scripts/checks/secret-scan.sh --tree     every tracked file at HEAD (gate / audit)
#
# Exit: 0 no findings · 1 findings · 2 usage, git or tool error.
#
# Rules (content rules run on text files; SECRET-FILE also covers binary files):
#   ENTREGAYA-KEY-SHAPE  a value with the SHAPE of the EntregaYa API key: three lowercase
#                        groups of 2, 2 and 4 letters joined by underscores, an underscore,
#                        then at least 20 letters/digits. Only the shape is encoded (lengths
#                        and character classes), never the real prefix text, so this file
#                        never matches itself (H6).
#   PEM-PRIVATE-KEY      a PEM private-key header (RSA, EC, OPENSSH, DSA, ENCRYPTED, PGP ...).
#   SFDX-AUTH-URL        an SFDX auth URL: the force scheme with credentials before an "@".
#   SF-ACCESS-TOKEN      a Salesforce session id / access token (org id, "!", token).
#   JWT                  a JSON Web Token (three base64url segments, header and payload "eyJ").
#   BEARER-TOKEN         "Bearer <16+ token characters>", or "Basic <base64>" on an
#                        Authorization line. A Named Credential merge field
#                        (Bearer {!$Credential.Password}) or a variable is not a value.
#   SECRET-ASSIGNMENT    a secret-like name holding a literal of 8+ characters:
#                        - quoted (key = "v", key: 'v', "key": "v") for names containing
#                          consumer/client secret, password, api key, private key,
#                          access/refresh/auth token or secret; and for names that only END in
#                          secret, password, token, api key, private key or Authorization
#                          ("token", oauthToken) when the literal looks generated (a digit, or
#                          upper and lower case), so constants like X_TOKEN = 'SOME-MARKER'
#                          are not reported;
#                        - a header setter: setHeader / header / set / append / put with a
#                          header name ending in one of those words ('x-api-key') and a literal;
#                        - an XML element whose name ends in one of those words
#                          (<consumerSecret>, <password>, legacy Named Credential
#                          <oauthToken> / <oauthRefreshToken>, ...);
#                        - a Custom Metadata record whose <field> ends in Key, Secret, Token or
#                          Password (Api_Key__c) and whose <value> is on that or a later line;
#                        - unquoted (KEY=v, key: v) in configuration files only: .env*, *.yml,
#                          *.yaml, *.properties, *.ini, *.cfg, *.conf, *.toml.
#                        References and placeholders are not literals and are not reported:
#                        ${..}, $(..), $UPPER_CASE_VAR, {..} ({!merge}, {{tpl}}), %VAR%,
#                        anything with < or >, and "not-set", "placeholder", "changeme",
#                        "example", "dummy", "sample", "redacted", "your-...", "replace-with",
#                        "xxxx", "****". A value starting with "$" that is not one of those
#                        references (a password like "$..." ) IS reported.
#   SECRET-FILE          (line 0 = the whole file) a file that holds secrets by its name:
#                        .env and .env.* (except .env.example/.sample/.template/.dist, which
#                        are content-scanned), *.p12, *.pfx, *.jks, *.keystore, *.key, *.p8,
#                        id_rsa / id_dsa / id_ecdsa / id_ed25519.
#
# Paths are handled NUL-delimited end to end (git -z output parsed by perl), so a path with a
# tab or a newline is scanned; in the output such characters are shown escaped (\t, \n).
#
# Allow-list (by path only, where unavoidable): the pattern-definition files of the
# security tooling under .claude/skills/sf-security-audit/ may be listed in ALLOW_PATHS
# below if a vendored update ever makes them match. It is EMPTY today: every tracked file,
# including that tooling and this script, scans clean.
#
# Limits: content rules skip binary files (git grep -I; SECRET-FILE covers keystores by
# name); unquoted literals outside configuration files are not reported, because in code
# they are almost always variable names.
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

command -v perl >/dev/null 2>&1 || {
  echo "secret-scan: perl is required (it ships with git)" >&2
  exit 2
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "secret-scan: not inside a git repository" >&2
  exit 2
}
cd "$ROOT" || exit 2

WORK="$(mktemp -d "${TMPDIR:-/tmp}/secret-scan.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM

if [ "$MODE" = "--tree" ]; then
  git rev-parse -q --verify HEAD >/dev/null || {
    echo "secret-scan: HEAD does not exist (no commit yet)" >&2
    exit 2
  }
  SOURCE=(HEAD)
  STRIP="HEAD:"
  BLOB_REV="HEAD:"
  SCOPE="tracked files at HEAD"
  git ls-tree -r -z --name-only HEAD >"$WORK/paths.z" || exit 2
else
  SOURCE=(--cached)
  STRIP=""
  BLOB_REV=":0:"
  SCOPE="staged files"
  # Paths added, copied, modified, renamed or type-changed in the index (deletions carry no content).
  git diff --cached --name-only -z --diff-filter=ACMRT >"$WORK/paths.z" || exit 2
  if [ ! -s "$WORK/paths.z" ]; then
    echo "secret-scan: 0 findings in $SCOPE"
    exit 0
  fi
fi

# Coarse candidate lines (a superset, case-insensitive); the precise rules run in perl below.
# Shape pieces of the EntregaYa key are character classes only, so the pattern is data, not a sample.
# One git grep per pattern: a single call with every pattern is about 100 times slower.
# A line found by several patterns is reported once (the filter de-duplicates).
WORDS='(secret|passw(or)?d|token|api[-_]?key|apikey|private[-_]?key|authorization)'
COARSE=(
  '[a-z]{2}_[a-z]{2}_[a-z]{4}_[a-z0-9]{20,}'
  '-----BEGIN [A-Z0-9 ]*PRIVATE KEY'
  'force://'
  '00D[a-z0-9]{12,15}!'
  'eyJ[a-z0-9_-]{8,}\.eyJ'
  '(bearer|basic)[[:space:]]+[a-z0-9._~+/=-]{16,}'
  "${WORDS}[a-z0-9_]*['\"]?[[:space:]]*[:=,]"
  "${WORDS}[^>]*>[^<]"
  '<field>'
)
: >"$WORK/grep.z"
for pattern in "${COARSE[@]}"; do
  git grep --no-color -I -n -z -i -E -e "$pattern" "${SOURCE[@]}" -- . \
    "${ALLOW_PATHS[@]+"${ALLOW_PATHS[@]}"}" >>"$WORK/grep.z" 2>"$WORK/err"
  rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "secret-scan: git grep failed" >&2
    exit 2
  fi
done

cat >"$WORK/filter.pl" <<'PERL'
use strict;
use warnings;

my ($mode, $strip, $blob_rev, $paths_file, $grep_file) = @ARGV;

sub slurp {
  my ($f) = @_;
  open(my $h, '<:raw', $f) or die "secret-scan: cannot read $f\n";
  local $/;
  my $d = <$h>;
  close $h;
  return defined $d ? $d : '';
}

my @paths = grep { length } split /\0/, slurp($paths_file);
my %in_scope = map { $_ => 1 } @paths;
my (%seen, @out, %cmdt_files);

# Display only: control characters in a path are escaped, so one finding is one line.
sub show {
  my ($p) = @_;
  $p =~ s/\\/\\\\/g;
  $p =~ s/\t/\\t/g;
  $p =~ s/\n/\\n/g;
  $p =~ s/([\x00-\x1f\x7f])/sprintf('\\x%02x', ord $1)/ge;
  return $p;
}

sub hit {
  my ($p, $n, $rule) = @_;
  my $key = show($p) . ":$n $rule";
  push @out, [show($p), $n, $rule] unless $seen{$key}++;
}

my $PLACEHOLDER = qr/not-set|placeholder|changeme|change[-_]me|example|dummy|sample|redacted|your[-_]|replace[-_]?(?:with|me)|xxxx|\*\*\*\*|enter[-_]the/i;

sub placeholder {
  my ($v) = @_;
  return 1 if $v =~ /^\$[{(]/;                 # ${VAR}, $(command)
  return 1 if $v =~ /^\$[A-Z_][A-Z0-9_]*$/;    # $ENV_VAR
  return 1 if $v =~ /^\{/;                     # {!$Credential.X}, {{template}}, {placeholder}
  return 1 if $v =~ /^%[A-Za-z_][A-Za-z0-9_]*%$/;
  return 1 if $v =~ /[<>]/;
  return 1 if $v =~ $PLACEHOLDER;
  return 0;
}

sub literal {
  my ($v) = @_;
  return length($v) >= 8 && !placeholder($v);
}

sub mixed {
  my ($v) = @_;
  return $v =~ /[0-9]/ || ($v =~ /[a-z]/ && $v =~ /[A-Z]/);
}

my $WORD = qr/(?:secret|passw(?:or)?d|token|api[-_]?key|apikey|private[-_]?key)/i;
my $NAME_ANY = qr/(?:consumer_?secret|client_?secret|passw(?:or)?d|api_?key|private_?key|access_?token|refresh_?token|auth_?token|secret)[A-Za-z0-9_]*/i;
my $CONFIG = qr/(?:^|\/)(?:\.env(?:\.[^\/]*)?|[^\/]*\.(?:ya?ml|properties|ini|cfg|conf|toml|env))$/i;
my $KEY_FIELD = qr/(?:key|secret|token|passw(?:or)?d)(?:__c)?$/i;

sub line_rules {
  my ($p, $n, $c) = @_;
  hit($p, $n, 'ENTREGAYA-KEY-SHAPE') if $c =~ /(?:^|[^A-Za-z0-9])[a-z]{2}_[a-z]{2}_[a-z]{4}_[A-Za-z0-9]{20,}/;
  hit($p, $n, 'PEM-PRIVATE-KEY') if $c =~ /-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----/;
  hit($p, $n, 'SFDX-AUTH-URL') if $c =~ m{force://[A-Za-z0-9._~-]+:[^\@\s'"]{10,}\@[A-Za-z0-9.-]+};
  hit($p, $n, 'SF-ACCESS-TOKEN') if $c =~ /(?<![A-Za-z0-9])00D[A-Za-z0-9]{12,15}![A-Za-z0-9._]{20,}/;
  hit($p, $n, 'JWT') if $c =~ /eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/;

  my $bearer = 0;
  while ($c =~ m{\bbearer\s+([A-Za-z0-9._~+/=-]{16,})}gi) { $bearer = 1 unless placeholder($1); }
  if ($c =~ /authorization/i) {
    while ($c =~ m{\bbasic\s+([A-Za-z0-9+/]{16,}={0,2})(?![A-Za-z0-9+/=])}gi) { $bearer = 1 unless placeholder($1); }
  }
  hit($p, $n, 'BEARER-TOKEN') if $bearer;

  my $assign = 0;
  while ($c =~ /$NAME_ANY["']?\s*[:=]\s*["']([^"'\s]+)["']/g) { $assign = 1 if literal($1); }
  # Names that only END in a secret word (oauthToken, x-api-key, "token") may be constants or
  # markers, so here the literal must also look generated: a digit, or upper and lower case.
  while ($c =~ /(?:$WORD|authorization)["']?\s*[:=]\s*["']([^"'\s]+)["']/gi) { $assign = 1 if literal($1) && mixed($1); }
  # Header setters: setHeader('x-api-key', 'v'), headers.set(...), .append(...), .put(...).
  while ($c =~ /\b(?:setHeader|header|set|append|put)\s*\(\s*["'][A-Za-z0-9_-]*(?:$WORD|authorization)["']\s*,\s*["']([^"'\s]+)["']/gi) {
    $assign = 1 if literal($1);
  }
  while ($c =~ /<[A-Za-z0-9_:.-]*$WORD(?:\s[^>]*)?>([^<\s]+)<\//g) { $assign = 1 if literal($1); }
  if ($p =~ $CONFIG && $c =~ /^\s*(?:export\s+)?[A-Za-z0-9_.-]*$WORD\s*[:=]\s*([^\s'"#][^\s#]*)/) {
    $assign = 1 if literal($1);
  }
  hit($p, $n, 'SECRET-ASSIGNMENT') if $assign;

  while ($c =~ /<field>\s*([A-Za-z0-9_]+)\s*<\/field>/gi) { $cmdt_files{$p} = 1 if $1 =~ $KEY_FIELD; }
}

# Grep records are "path NUL line NUL content LF"; a path may hold a tab or a newline,
# content holds neither NUL (-I) nor LF, so this parse is unambiguous.
my $raw = slurp($grep_file);
while ($raw =~ /\G([^\0]*)\0(\d+)\0([^\n]*)\n/gc) {
  my ($p, $n, $c) = ($1, $2, $3);
  $p = substr($p, length $strip) if $strip ne '' && index($p, $strip) == 0;
  next if $mode eq '--staged' && !$in_scope{$p};
  line_rules($p, $n, $c);
}
my $pos = pos($raw) // 0;
die "secret-scan: unexpected git grep output\n" if $pos != length $raw;

# Custom Metadata records: a key-like <field> and its <value> on that or a later line.
for my $p (sort keys %cmdt_files) {
  open(my $h, '-|', 'git', 'cat-file', '-p', $blob_rev . $p) or die "secret-scan: cannot read $p\n";
  binmode $h;
  my ($n, $armed) = (0, 0);
  while (my $line = <$h>) {
    $n++;
    if ($line =~ /<field>\s*([A-Za-z0-9_]+)\s*<\/field>/i) { $armed = $1 =~ $KEY_FIELD ? 1 : 0; }
    if ($line =~ /<value(?:\s[^>]*)?>\s*([^<]*?)\s*<\/value>/i) {
      hit($p, $n, 'SECRET-ASSIGNMENT') if $armed && literal($1);
      $armed = 0;
    }
    $armed = 0 if $line =~ /<\/values>/i;
  }
  close $h or die "secret-scan: git cat-file failed for a candidate file\n";
}

# Secret files by name (binary keystores included).
for my $p (@paths) {
  (my $base = $p) =~ s{.*/}{}s;
  if ($base eq '.env'
    || ($base =~ /^\.env\./ && $base !~ /^\.env\.(?:example|sample|template|dist)$/i)
    || $base =~ /\.(?:p12|pfx|jks|keystore|key|p8)$/i
    || $base =~ /^id_(?:rsa|dsa|ecdsa|ed25519)$/) {
    hit($p, 0, 'SECRET-FILE');
  }
}

for my $f (sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] || $a->[2] cmp $b->[2] } @out) {
  print "$f->[0]:$f->[1] $f->[2]\n";
}
PERL

perl "$WORK/filter.pl" "$MODE" "$STRIP" "$BLOB_REV" "$WORK/paths.z" "$WORK/grep.z" >"$WORK/findings" || {
  echo "secret-scan: the filter failed" >&2
  exit 2
}

COUNT="$(wc -l <"$WORK/findings" | tr -d ' ')"
if [ "$COUNT" -eq 0 ]; then
  echo "secret-scan: 0 findings in $SCOPE"
  exit 0
fi
cat "$WORK/findings"
echo "secret-scan: $COUNT finding(s) in $SCOPE - values are never printed. Remove the value" \
  "(use a Named/External Credential or a local, git-ignored file) and rotate it if it was ever pushed." >&2
exit 1
