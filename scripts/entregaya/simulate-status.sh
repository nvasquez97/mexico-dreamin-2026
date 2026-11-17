#!/usr/bin/env bash
# Simulates EntregaYa for AC-004.6 (odd/tasks/req-004-carrier-status.md, S4, D2):
# gets an access token with the OAuth 2.0 client credentials flow of the External
# Client App "EntregaYa Status" and POSTs one status change to
# /services/apexrest/entregaya/v1/status. Prints the HTTP status and the body of
# the POST answer.
#
# The consumer key and secret come ONLY from the environment variables
# ENTREGAYA_CLIENT_ID and ENTREGAYA_CLIENT_SECRET (B4: the owner reads them in
# Setup). Neither they nor the access token are printed, written to disk or put
# on a command line: curl reads them from its standard input (-K -), so they do
# not show in the process list. Do not run this script with `bash -x`.
#
# Usage:
#   ENTREGAYA_CLIENT_ID=... ENTREGAYA_CLIENT_SECRET=... \
#     scripts/entregaya/simulate-status.sh <org-alias | https://<my-domain>> \
#       <trackingNumber> <status> <location> <timestamp> [proofId]
#   e.g. ... cargo-opus-t1 RC000001002 "Out for delivery" "Monterrey, NL" 2026-11-20T10:00:00-06:00
# The first argument is a Salesforce CLI org alias (its My Domain comes from
# `sf org display`) or the My Domain URL itself.
#
# Exit codes: 0 the POST answered 2xx; 1 it answered another status; 2 usage or
# missing environment variables; 3 no token (the token endpoint's error code is
# printed, never the request).
set -euo pipefail
set +x

usage() {
    echo "Usage: ENTREGAYA_CLIENT_ID=... ENTREGAYA_CLIENT_SECRET=... $0 <org-alias | https://<my-domain>> <trackingNumber> <status> <location> <timestamp> [proofId]" >&2
    exit 2
}
[[ $# -ge 5 && $# -le 6 ]] || usage
TARGET="$1"; TRACKING="$2"; STATUS="$3"; LOCATION="$4"; TIMESTAMP="$5"; PROOF_ID="${6:-}"

if [[ -z "${ENTREGAYA_CLIENT_ID:-}" || -z "${ENTREGAYA_CLIENT_SECRET:-}" ]]; then
    echo "simulate-status: set ENTREGAYA_CLIENT_ID and ENTREGAYA_CLIENT_SECRET in the environment (consumer key and secret of the External Client App EntregaYa Status)" >&2
    exit 2
fi

# ─── My Domain ──────────────────────────────────────────────────────────────
if [[ "$TARGET" == https://* ]]; then
    base_url="${TARGET%/}"
else
    base_url="$(sf org display --target-org "$TARGET" --json 2>/dev/null | jq -r '.result.instanceUrl // empty' 2>/dev/null || true)"
fi
if [[ ! "$base_url" =~ ^https://[A-Za-z0-9.-]+\.my\.salesforce\.com$ ]]; then
    echo "simulate-status: '$TARGET' is not an org alias or a https://<name>.my.salesforce.com My Domain URL" >&2
    exit 2
fi

# Escapes a value for a double-quoted curl config string.
curl_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# ─── 1. Token (client credentials) ──────────────────────────────────────────
token_answer="$(
    {
        printf 'url = %s\n' "$(curl_quote "$base_url/services/oauth2/token")"
        printf 'data-urlencode = %s\n' "$(curl_quote "grant_type=client_credentials")"
        printf 'data-urlencode = %s\n' "$(curl_quote "client_id=$ENTREGAYA_CLIENT_ID")"
        printf 'data-urlencode = %s\n' "$(curl_quote "client_secret=$ENTREGAYA_CLIENT_SECRET")"
    } | curl -s --max-time 60 -X POST -w '\n%{http_code}' -K - || true
)"
token_status="${token_answer##*$'\n'}"
token_body="${token_answer%$'\n'*}"
token="$(jq -r '.access_token // empty' <<<"$token_body" 2>/dev/null || true)"
unset token_answer
if [[ "$token_status" != "200" || -z "$token" ]]; then
    error="$(jq -r '[.error // empty, .error_description // empty] | join(": ")' <<<"$token_body" 2>/dev/null || true)"
    echo "simulate-status: no token from $base_url/services/oauth2/token (HTTP $token_status${error:+, $error})" >&2
    exit 3
fi
unset token_body
echo "simulate-status: token obtained with the client credentials flow"

# ─── 2. POST the status change ──────────────────────────────────────────────
if [[ -n "$PROOF_ID" ]]; then
    body="$(jq -cn --arg t "$TRACKING" --arg s "$STATUS" --arg l "$LOCATION" --arg ts "$TIMESTAMP" --arg p "$PROOF_ID" \
        '{trackingNumber: $t, status: $s, location: $l, timestamp: $ts, proofId: $p}')"
else
    body="$(jq -cn --arg t "$TRACKING" --arg s "$STATUS" --arg l "$LOCATION" --arg ts "$TIMESTAMP" \
        '{trackingNumber: $t, status: $s, location: $l, timestamp: $ts, proofId: null}')"
fi
answer="$(
    {
        printf 'url = %s\n' "$(curl_quote "$base_url/services/apexrest/entregaya/v1/status")"
        printf 'header = %s\n' "$(curl_quote "Authorization: Bearer $token")"
        printf 'header = %s\n' "$(curl_quote "Content-Type: application/json")"
        printf 'data = %s\n' "$(curl_quote "$body")"
    } | curl -s --max-time 60 -X POST -w '\n%{http_code}' -K - || true
)"
unset token
status="${answer##*$'\n'}"
echo "simulate-status: POST $body"
echo "HTTP $status"
echo "${answer%$'\n'*}"
[[ "$status" =~ ^2[0-9][0-9]$ ]] || exit 1
