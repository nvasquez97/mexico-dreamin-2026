#!/usr/bin/env bash
# Org check for AC-F.9 (odd/tasks/foundation.md): the RutaCargo site guest user.
# Read-only: constant SOQL queries and one anonymous HTTP GET.
#
# Exits non-zero unless:
#   1. the Network "RutaCargo" exists and its Status is Live;
#   2. the site's guest user exists, is found through the site (Site.GuestUserId,
#      never a hard-coded Id) and has the profile "RutaCargo Profile";
#   3. ObjectPermissions has 0 rows for the profile "RutaCargo Profile" and 0 rows
#      for every permission set assigned to the guest user (the profile's own
#      permission set included);
#   4. the guest user's TimeZoneSidKey is America/Mexico_City;
#   5. an anonymous GET (no session, no redirects followed) of the site home URL
#      returns 200.
#
# Usage: scripts/checks/guest-access-check.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

NETWORK_NAME='RutaCargo'
GUEST_PROFILE='RutaCargo Profile'
GUEST_TIME_ZONE='America/Mexico_City'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
finish() {
    if [[ "$violations" -gt 0 ]]; then
        echo "guest-access-check: $violations violation(s) in $ORG"
        exit 1
    fi
    echo "guest-access-check: passed in $ORG"
    exit 0
}

# Runs a SOQL query and prints the records as JSON; stops the script on an error.
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

# ─── 1. Network status ──────────────────────────────────────────────────────
network="$(query "SELECT Id, Name, Status, UrlPathPrefix FROM Network WHERE Name = 'RutaCargo'")"
if [[ "$(jq 'length' <<<"$network")" -ne 1 ]]; then
    fail "Network $NETWORK_NAME not found"
    finish
fi
status="$(jq -r '.[0].Status' <<<"$network")"
if [[ "$status" == "Live" ]]; then
    pass "Network $NETWORK_NAME Status is Live"
else
    fail "Network $NETWORK_NAME Status is $status, expected Live"
fi

# ─── 2. Guest user, found through the site ──────────────────────────────────
site="$(query "SELECT Id, Name, GuestUserId FROM Site WHERE Name = 'RutaCargo' AND SiteType = 'ChatterNetwork'")"
guest_id="$(jq -r '.[0].GuestUserId // empty' <<<"$site")"
if [[ ! "$guest_id" =~ ^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
    fail "site $NETWORK_NAME has no guest user"
    finish
fi
# guest_id is validated above as a Salesforce User Id before it enters any query.
guest="$(query "SELECT Id, Profile.Name, TimeZoneSidKey, UserType FROM User WHERE Id = '$guest_id'")"
guest_profile="$(jq -r '.[0].Profile.Name // empty' <<<"$guest")"
if [[ "$guest_profile" == "$GUEST_PROFILE" ]]; then
    pass "guest user profile is $GUEST_PROFILE"
else
    fail "guest user profile is '$guest_profile', expected '$GUEST_PROFILE'"
fi

# ─── 3. No object permissions for the guest ─────────────────────────────────
profile_perms="$(query "SELECT Id, SobjectType, Parent.Name FROM ObjectPermissions WHERE Parent.Profile.Name = 'RutaCargo Profile'")"
count="$(jq 'length' <<<"$profile_perms")"
if [[ "$count" -eq 0 ]]; then
    pass "profile $GUEST_PROFILE has 0 ObjectPermissions rows"
else
    fail "profile $GUEST_PROFILE has $count ObjectPermissions rows: $(jq -r '[.[].SobjectType] | join(", ")' <<<"$profile_perms")"
fi

assigned_perms="$(query "SELECT Id, SobjectType, Parent.Name FROM ObjectPermissions WHERE ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = '$guest_id')")"
count="$(jq 'length' <<<"$assigned_perms")"
if [[ "$count" -eq 0 ]]; then
    pass "permission sets assigned to the guest user have 0 ObjectPermissions rows"
else
    fail "permission sets assigned to the guest user have $count ObjectPermissions rows: $(jq -r '[.[] | .Parent.Name + ":" + .SobjectType] | join(", ")' <<<"$assigned_perms")"
fi

# ─── 4. Guest user time zone ────────────────────────────────────────────────
tz="$(jq -r '.[0].TimeZoneSidKey // empty' <<<"$guest")"
if [[ "$tz" == "$GUEST_TIME_ZONE" ]]; then
    pass "guest user TimeZoneSidKey is $GUEST_TIME_ZONE"
else
    fail "guest user TimeZoneSidKey is '$tz', expected '$GUEST_TIME_ZONE'"
fi

# ─── 5. Anonymous GET of the site home URL ──────────────────────────────────
# The LWR pages are served by the ChatterNetworkPicasso site (prefix rutacargo);
# the Network and ChatterNetwork site use the rutacargovforcesite prefix.
lwr_site="$(query "SELECT UrlPathPrefix FROM Site WHERE Name = 'RutaCargo1' AND SiteType = 'ChatterNetworkPicasso'")"
prefix="$(jq -r '.[0].UrlPathPrefix // empty' <<<"$lwr_site")"
domain="$(query "SELECT Domain FROM Domain WHERE Domain LIKE '%.my.site.com'")"
host="$(jq -r '.[0].Domain // empty' <<<"$domain")"
if [[ -z "$host" || -z "$prefix" ]]; then
    fail "site home URL cannot be built (domain '$host', prefix '$prefix')"
    finish
fi
url="https://$host/$prefix/"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 60 "$url" || true)"
if [[ "$code" == "200" ]]; then
    pass "anonymous GET $url returns 200"
else
    fail "anonymous GET $url returns $code, expected 200"
fi

finish
