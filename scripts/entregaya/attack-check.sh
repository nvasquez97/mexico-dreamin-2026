#!/usr/bin/env bash
# Attack check for AC-004.8 (odd/tasks/req-004-carrier-status.md, BR-04): nobody
# without a token can move a shipment through the EntregaYa status endpoint.
#
# It POSTs a valid status body, with NO Authorization header and no cookies, to:
#   1. https://<My Domain>/services/apexrest/entregaya/v1/status   -> must be 401;
#   2. https://<site host>/<site prefix>/services/apexrest/entregaya/v1/status
#      (the RutaCargo site, path prefix included)                 -> 401, 403 or 404;
#   3. https://<site host>/services/apexrest/entregaya/v1/status
#      (the site domain's root path)                               -> 401, 403 or 404;
#   4. https://<site host>/<Visualforce site prefix>/services/apexrest/entregaya/v1/status
#      (the Network's own ChatterNetwork site)                     -> 401, 403 or 404.
# A refusal must come from the platform: a body carrying the resource's own error
# envelope ({"error":{"code":...}}) means the request reached
# EntregaYaStatusResource, which fails the check even with a 403. Any other
# answer (200, a 3xx, a 5xx, no answer) fails, with one exception: the LWR site
# runtime (path 2) answers every POST under /services/apexrest with 501 and the
# site's HTML error page, before any Apex runs. 501 is accepted on that path only
# when the body is not the resource's envelope AND a control POST to a resource
# that does not exist under the same prefix also answers 501, which proves the
# runtime refused it without routing to Apex (observed in cargo-opus-t1, T4).
# Then a read-only query confirms the target shipment did not change
# (Status__c, Last_Location__c, Last_Update__c, SystemModstamp).
#
# The My Domain comes from `sf org display`; the site host and prefix come from
# the site's own DomainSite row (as in scripts/checks/guest-access-check.sh),
# never hard-coded. The target is one seeded "In transit" shipment; nothing is
# inserted (A6).
#
# It runs only against a sandbox or scratch org (Organization.IsSandbox, as in
# scripts/setup/entregaya-integration.sh): its body is a valid "Out for delivery"
# change, so on a production org with an open endpoint it would move a real
# shipment. The check runs before any host is resolved or any request is sent.
#
# Exit codes: 0 refused everywhere and nothing changed; 1 a violation; 2 usage;
# 3 a failed query or no target shipment; 4 refused: not a sandbox or scratch org.
#
# Usage: scripts/entregaya/attack-check.sh <org-alias>
set -euo pipefail
export LC_ALL=C

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ENDPOINT_PATH='/services/apexrest/entregaya/v1/status'
SITE_NAME='RutaCargo1'
SITE_TYPE='ChatterNetworkPicasso'
VF_SITE_NAME='RutaCargo'
VF_SITE_TYPE='ChatterNetwork'
CONTROL_PATH='/services/apexrest/entregaya-attack-check-no-such-resource'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
abort() { echo "ERROR: $*" >&2; exit 3; }

query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "ERROR: query failed: $1" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 3
    fi
    jq -c '.result.records' <<<"$out"
}

# ─── Never a production org ─────────────────────────────────────────────────
org_row="$(query "SELECT IsSandbox FROM Organization")"
if [[ "$(jq -r '.[0].IsSandbox // false' <<<"$org_row")" != "true" ]]; then
    echo "ERROR: refused: $ORG is not a sandbox or scratch org" >&2
    exit 4
fi

# ─── Hosts ──────────────────────────────────────────────────────────────────
display="$(sf org display --target-org "$ORG" --json 2>/dev/null || true)"
my_domain="$(jq -r '.result.instanceUrl // empty' <<<"$display" 2>/dev/null)"
[[ "$my_domain" =~ ^https://[A-Za-z0-9.-]+\.my\.salesforce\.com$ ]] || abort "no My Domain URL for $ORG"

# Sets SITE_HOST and SITE_PREFIX from the site's only DomainSite row.
SITE_HOST=''
SITE_PREFIX=''
domain_site() {
    local rows
    rows="$(query "SELECT Domain.Domain, PathPrefix FROM DomainSite WHERE Site.Name = '$1' AND Site.SiteType = '$2'")"
    [[ "$(jq 'length' <<<"$rows")" == "1" ]] || abort "site $1 ($2) must have exactly 1 DomainSite row"
    SITE_HOST="$(jq -r '.[0].Domain.Domain // empty' <<<"$rows")"
    SITE_PREFIX="$(jq -r '.[0].PathPrefix // empty' <<<"$rows")"
    [[ "$SITE_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || abort "unexpected site host '$SITE_HOST'"
    [[ -z "$SITE_PREFIX" || "$SITE_PREFIX" =~ ^/[A-Za-z0-9_-]+$ ]] || abort "unexpected site prefix '$SITE_PREFIX'"
}
domain_site "$VF_SITE_NAME" "$VF_SITE_TYPE"
vf_host="$SITE_HOST"
vf_prefix="$SITE_PREFIX"
domain_site "$SITE_NAME" "$SITE_TYPE"
site_host="$SITE_HOST"
site_prefix="$SITE_PREFIX"

# ─── Target shipment (read-only) ────────────────────────────────────────────
TARGET_FIELDS='Id, Name, Status__c, Last_Location__c, Last_Update__c, SystemModstamp'
targets="$(query "SELECT $TARGET_FIELDS FROM Shipment__c WHERE Status__c = 'In transit' ORDER BY Name LIMIT 1")"
[[ "$(jq 'length' <<<"$targets")" == "1" ]] || abort "no seeded 'In transit' shipment to target"
before="$(jq -c '.[0] | del(.attributes)' <<<"$targets")"
target_id="$(jq -r '.Id' <<<"$before")"
[[ "$target_id" =~ ^[A-Za-z0-9]{15}([A-Za-z0-9]{3})?$ ]] || abort "unexpected shipment Id"
tracking="$(jq -r '.Name' <<<"$before")"
[[ "$tracking" =~ ^RC[0-9]{9}$ ]] || abort "unexpected tracking number '$tracking'"

# A valid body that would be applied if the caller were authorized: newer than
# any seeded Last_Update__c, a few minutes in the past in -06:00.
timestamp="$(TZ=America/Mexico_City date -v-2M '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null \
    || TZ=America/Mexico_City date -d '-2 minutes' '+%Y-%m-%dT%H:%M:%S%z')"
timestamp="${timestamp:0:22}:${timestamp:22:2}"
body="$(jq -cn --arg t "$tracking" --arg ts "$timestamp" \
    '{trackingNumber: $t, status: "Out for delivery", location: "Attack check, no token", timestamp: $ts, proofId: null}')"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# POSTs the body without credentials; prints "<http code>"; the body goes to $tmp/body.
anonymous_post() {
    : >"$tmp/body"
    curl -s -o "$tmp/body" -w '%{http_code}' --max-time 60 -X POST \
        -H 'Content-Type: application/json' --data "$body" "$1" || true
}

reached_resource() {
    jq -e 'type == "object" and (.error | type == "object") and (.error.code | type == "string")' "$tmp/body" >/dev/null 2>&1
}

# check_refused <url> <allowed codes> [<control url for an unrouted 501>]
check_refused() {
    local url="$1" allowed="$2" control="${3:-}" code control_code
    code="$(anonymous_post "$url")"
    if reached_resource; then
        fail "POST $url without a token reached EntregaYaStatusResource ($code, code $(jq -r '.error.code' "$tmp/body"))"
    elif [[ " $allowed " == *" $code "* ]]; then
        pass "POST $url without a token is refused with $code"
    elif [[ "$code" == "501" && -n "$control" ]]; then
        control_code="$(anonymous_post "$control")"
        if [[ "$control_code" == "501" ]] && ! reached_resource; then
            pass "POST $url without a token is refused with 501 by the LWR site runtime (a resource that does not exist answers the same 501: not routed to Apex)"
        else
            fail "POST $url without a token answered 501, but the control $control answered $control_code"
        fi
    else
        fail "POST $url without a token answered $code, expected one of: $allowed"
    fi
}

echo "attack-check: target $tracking ($(jq -r '.Status__c' <<<"$before")), timestamp $timestamp"
check_refused "$my_domain$ENDPOINT_PATH" '401'
check_refused "https://$site_host$site_prefix$ENDPOINT_PATH" '401 403 404' "https://$site_host$site_prefix$CONTROL_PATH"
check_refused "https://$site_host$ENDPOINT_PATH" '401 403 404'
check_refused "https://$vf_host$vf_prefix$ENDPOINT_PATH" '401 403 404'

# ─── Nothing changed ────────────────────────────────────────────────────────
rows_after="$(query "SELECT $TARGET_FIELDS FROM Shipment__c WHERE Id = '$target_id'")"
after="$(jq -c '.[0] | del(.attributes)' <<<"$rows_after")"
if [[ "$after" == "$before" ]]; then
    pass "shipment $tracking did not change (status, location, last update, SystemModstamp)"
else
    fail "shipment $tracking changed: before $before, after $after"
fi

if [[ "$violations" -gt 0 ]]; then
    echo "attack-check: $violations violation(s) in $ORG"
    exit 1
fi
echo "attack-check: passed in $ORG"
