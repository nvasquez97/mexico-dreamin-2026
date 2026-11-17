#!/usr/bin/env bash
# Simulates EntregaYa for AC-004.6 (odd/tasks/req-004-carrier-status.md, S4, D2):
# gets an access token with the OAuth 2.0 client credentials flow of the External
# Client App "EntregaYa Status", POSTs one status change to
# /services/apexrest/entregaya/v1/status, and checks the outcome against the one
# the caller expects. Prints the HTTP status and the body of the POST answer.
#
# The check (exit 1 on any difference):
#   - the answer is HTTP 200 and its body's "result" is the expected one;
#   - expected "updated": the shipment changed (Status__c, Last_Location__c and
#     Last_Update__c are not all as before) and now holds the posted status, the
#     posted location and the posted timestamp as an instant; on "Delivered",
#     Delivered_At__c is that instant and Proof_Id__c the posted proofId; on any
#     other status, Delivered_At__c and Proof_Id__c are as before (AC-004.2);
#   - expected "ignored": Status__c, Last_Location__c, Last_Update__c,
#     Delivered_At__c and Proof_Id__c are exactly as before.
# The shipment is read before and after the POST with `sf data query` as the
# org's CLI user (read-only; the token is used only for the POST).
#
# The consumer key and secret come ONLY from the environment variables
# ENTREGAYA_CLIENT_ID and ENTREGAYA_CLIENT_SECRET (B4: the owner reads them in
# Setup). Neither they nor the access token are printed, written to disk or put
# on a command line: curl reads them from its standard input (-K -), so they do
# not show in the process list. Do not run this script with `bash -x`.
#
# Usage (type the key and the secret at the silent prompts, so they never land
# in the shell history, and unset them afterwards):
#   read -rs ENTREGAYA_CLIENT_ID && export ENTREGAYA_CLIENT_ID
#   read -rs ENTREGAYA_CLIENT_SECRET && export ENTREGAYA_CLIENT_SECRET
#   scripts/entregaya/simulate-status.sh <org-alias> <updated | ignored> \
#       <trackingNumber> <status> <location> <timestamp> [proofId]
#   unset ENTREGAYA_CLIENT_ID ENTREGAYA_CLIENT_SECRET
#   e.g. ... cargo-opus-t1 updated RC000001002 "Out for delivery" "Monterrey, NL" 2026-11-20T10:00:00-06:00
#   then the same arguments with "ignored" instead of "updated".
# The first argument is a Salesforce CLI org alias: the My Domain comes from
# `sf org display` and the shipment is read with `sf data query`.
#
# Exit codes: 0 the POST answered 200 with the expected result and the shipment
# matches it; 1 any difference; 2 usage or missing environment variables; 3 no
# token (the token endpoint's error code is printed, never the request); 4 the
# shipment could not be read, or there is not exactly one with that tracking
# number.
set -euo pipefail
set +x

usage() {
    {
        echo "Usage: $0 <org-alias> <updated | ignored> <trackingNumber> <status> <location> <timestamp> [proofId]"
        echo "Set the key and the secret first, without putting them on a command line:"
        echo "  read -rs ENTREGAYA_CLIENT_ID && export ENTREGAYA_CLIENT_ID"
        echo "  read -rs ENTREGAYA_CLIENT_SECRET && export ENTREGAYA_CLIENT_SECRET"
        echo "and run 'unset ENTREGAYA_CLIENT_ID ENTREGAYA_CLIENT_SECRET' when done."
    } >&2
    exit 2
}

# Escapes a value for a double-quoted curl config string.
curl_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# jq: the epoch seconds of an ISO-8601 instant, either Salesforce's
# 2026-11-20T16:00:00.000+0000 or the contract's 2026-11-20T10:00:00-06:00; null
# stays null; anything else is an error.
JQ_DEFS='
def epoch:
  if . == null then null else
    (capture("^(?<dt>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<tz>Z|[+-][0-9]{2}:?[0-9]{2})$")
      // error("not an ISO-8601 instant: \(.)"))
    | ((.dt + "Z") | fromdateiso8601)
      - (if .tz == "Z" then 0 else
           (.tz | capture("^(?<s>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2})$")
             | (if .s == "-" then -1 else 1 end) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60))
         end)
  end;
def shipment:
  {status: .Status__c, location: .Last_Location__c, lastUpdate: (.Last_Update__c | epoch),
   deliveredAt: (.Delivered_At__c | epoch), proofId: .Proof_Id__c};
'

# check_outcome <expected> <http code> <answer body> <before row> <after row>
#               <status> <location> <timestamp> <proofId>
# The rows are the JSON records of SHIPMENT_FIELDS. Prints one line per
# difference; returns 0 when there is none, 1 otherwise (also when a value
# cannot be compared).
check_outcome() {
    local expected="$1" http="$2" answer="$3" before="$4" after="$5"
    local status="$6" location="$7" timestamp="$8" proof="$9" problems
    if ! problems="$(jq -rn --arg expected "$expected" --arg http "$http" --arg answer "$answer" \
        --argjson before "$before" --argjson after "$after" \
        --arg status "$status" --arg location "$location" --arg ts "$timestamp" --arg proof "$proof" \
        "$JQ_DEFS"'
        ($before | shipment) as $b | ($after | shipment) as $a | ($ts | epoch) as $t
        | ($answer | try fromjson catch null | if type == "object" then .result else null end) as $result
        | [
            (if $http != "200" then "HTTP \($http), expected 200" else empty end),
            (if $result != $expected then "result \($result // "none"), expected \($expected)" else empty end),
            (if $expected == "ignored" then
                (if $a != $b then "the shipment changed: before \($b | tojson), after \($a | tojson)" else empty end)
             else
                (if [$a.status, $a.location, $a.lastUpdate] == [$b.status, $b.location, $b.lastUpdate]
                 then "the shipment did not change: \($a | tojson)" else empty end),
                (if $a.status != $status then "Status__c is \($a.status), expected \($status)" else empty end),
                (if $a.location != $location then "Last_Location__c is \($a.location), expected \($location)" else empty end),
                (if $a.lastUpdate != $t then "Last_Update__c is \($after.Last_Update__c), expected the instant \($ts)" else empty end),
                (if $status == "Delivered" then
                    (if $a.deliveredAt != $t then "Delivered_At__c is \($after.Delivered_At__c), expected the instant \($ts)" else empty end),
                    (if $a.proofId != $proof then "Proof_Id__c is \($a.proofId), expected \($proof)" else empty end)
                 else
                    (if [$a.deliveredAt, $a.proofId] != [$b.deliveredAt, $b.proofId]
                     then "Delivered_At__c or Proof_Id__c changed on a non-Delivered update" else empty end)
                 end)
             end)
          ] | .[]' 2>&1)"; then
        echo "simulate-status: FAIL: the outcome could not be compared: $problems"
        return 1
    fi
    if [[ -n "$problems" ]]; then
        sed 's/^/simulate-status: FAIL: /' <<<"$problems"
        return 1
    fi
    return 0
}

SHIPMENT_FIELDS='Id, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c'

# shipment_row <org alias> <tracking number>: the shipment's record as JSON.
shipment_row() {
    local out
    out="$(sf data query --target-org "$1" --json \
        --query "SELECT $SHIPMENT_FIELDS FROM Shipment__c WHERE Name = '$2'" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "simulate-status: the shipment $2 could not be read in $1" >&2
        exit 4
    fi
    if [[ "$(jq '.result.records | length' <<<"$out")" != "1" ]]; then
        echo "simulate-status: there is not exactly one shipment $2 in $1" >&2
        exit 4
    fi
    jq -c '.result.records[0] | del(.attributes)' <<<"$out"
}

main() {
    [[ $# -ge 6 && $# -le 7 ]] || usage
    local org="$1" expected="$2" tracking="$3" status="$4" location="$5" timestamp="$6" proof_id="${7:-}"
    [[ "$expected" == "updated" || "$expected" == "ignored" ]] || usage
    # The tracking number goes into a SOQL literal: only the RC + 9 digits format.
    if [[ ! "$tracking" =~ ^RC[0-9]{9}$ ]]; then
        echo "simulate-status: '$tracking' is not a tracking number (RC followed by 9 digits)" >&2
        exit 2
    fi

    if [[ -z "${ENTREGAYA_CLIENT_ID:-}" || -z "${ENTREGAYA_CLIENT_SECRET:-}" ]]; then
        echo "simulate-status: set ENTREGAYA_CLIENT_ID and ENTREGAYA_CLIENT_SECRET in the environment with read -rs (consumer key and secret of the External Client App EntregaYa Status)" >&2
        exit 2
    fi

    # ─── My Domain ──────────────────────────────────────────────────────────
    local base_url
    base_url="$(sf org display --target-org "$org" --json 2>/dev/null | jq -r '.result.instanceUrl // empty' 2>/dev/null || true)"
    if [[ ! "$base_url" =~ ^https://[A-Za-z0-9.-]+\.my\.salesforce\.com$ ]]; then
        echo "simulate-status: '$org' is not an org alias with a https://<name>.my.salesforce.com My Domain" >&2
        exit 2
    fi

    # ─── 0. The shipment before ─────────────────────────────────────────────
    local before
    before="$(shipment_row "$org" "$tracking")"

    # ─── 1. Token (client credentials) ──────────────────────────────────────
    local token_answer token_status token_body token error
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

    # ─── 2. POST the status change ──────────────────────────────────────────
    local body answer http answer_body
    if [[ -n "$proof_id" ]]; then
        body="$(jq -cn --arg t "$tracking" --arg s "$status" --arg l "$location" --arg ts "$timestamp" --arg p "$proof_id" \
            '{trackingNumber: $t, status: $s, location: $l, timestamp: $ts, proofId: $p}')"
    else
        body="$(jq -cn --arg t "$tracking" --arg s "$status" --arg l "$location" --arg ts "$timestamp" \
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
    http="${answer##*$'\n'}"
    answer_body="${answer%$'\n'*}"
    echo "simulate-status: POST $body"
    echo "HTTP $http"
    echo "$answer_body"

    # ─── 3. The shipment after, against the expected outcome ────────────────
    local after
    after="$(shipment_row "$org" "$tracking")"
    echo "simulate-status: before $before"
    echo "simulate-status: after  $after"
    if ! check_outcome "$expected" "$http" "$answer_body" "$before" "$after" "$status" "$location" "$timestamp" "$proof_id"; then
        exit 1
    fi
    echo "simulate-status: passed: 200 $expected, and the shipment matches"
}

# Sourcing the script defines the functions without running it (dry runs of
# check_outcome); running it runs main.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
