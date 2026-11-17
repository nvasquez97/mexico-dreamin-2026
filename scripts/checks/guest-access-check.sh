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
#   3b. FieldPermissions has 0 rows on Shipment__c and on the Account custom
#      fields (API names ending in __c) for the profile "RutaCargo Profile" and
#      every permission set assigned to the guest user (the platform keeps rows
#      on standard Account fields for the guest profile; with no Account object
#      permission they grant nothing);
#   4. the guest user's TimeZoneSidKey is America/Mexico_City;
#   5. the Visualforce pages enabled for the guest (profile "RutaCargo Profile"
#      and every permission set assigned to the guest user) are exactly the
#      allow-list GUEST_PAGES below: no self-registration page;
#   5b. the Apex classes enabled for the guest (same scope as 5) are exactly the
#      allow-list GUEST_CLASSES below (req-001 AC-001.6);
#   5c. source check: no Apex class or trigger under force-app/main/default
#      other than SELECTOR_FILES below names the without-sharing
#      PublicTrackingSelector (case-insensitive, as Apex), so its
#      SECURITY-JUSTIFICATION's "only caller is PublicTrackingController" holds
#      (req-001 SEC-001, P11);
#   6. an anonymous GET (no session, no redirects followed) of the site home URL
#      returns 200; the host comes from the site's own DomainSite row;
#   7. an anonymous GET of the self-registration pages on the Visualforce site
#      (/rutacargovforcesite/SiteRegister and /CommunitiesSelfReg) is refused:
#      401, 403 or 404, a 3xx whose Location is the LWR login page, or a 200
#      whose body only redirects to the LWR login. Any other answer (a timeout
#      or no answer, 000, a 5xx, another status) fails: the refusal is not proven.
#
# Usage: scripts/checks/guest-access-check.sh <org-alias>
set -euo pipefail
export LC_ALL=C  # byte order for sort and comm, the same order jq uses

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

NETWORK_NAME='RutaCargo'
GUEST_PROFILE='RutaCargo Profile'
GUEST_TIME_ZONE='America/Mexico_City'
# Visualforce pages the guest may open: what the CustomSite references
# (indexPage, authorizationRequiredPage and the four error pages). Must match
# force-app/main/default/profiles/RutaCargo Profile.profile-meta.xml.
GUEST_PAGES='BandwidthExceeded,CommunitiesLanding,CommunitiesLogin,Exception,FileNotFound,InMaintenance'
# Apex classes the guest may call: only the public tracking entry point
# (req-001 S1, C8). Must match the classAccesses of the guest profile.
GUEST_CLASSES='PublicTrackingController'
# The without-sharing selector and the only source files that may name it:
# itself, its single caller and that caller's test (req-001 SEC-001, P11).
SELECTOR='PublicTrackingSelector'
SELECTOR_FILES='PublicTrackingSelector.cls PublicTrackingController.cls PublicTrackingControllerTest.cls'
SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/force-app/main/default"
# Self-registration pages that must not answer an anonymous visitor.
SELF_REG_PAGES='SiteRegister CommunitiesSelfReg'

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

# ─── 3b. No field permissions for the guest on RutaCargo data ───────────────
guest_fls="$( { query "SELECT Field, Parent.Name FROM FieldPermissions WHERE SobjectType IN ('Shipment__c', 'Account') AND Parent.Profile.Name = 'RutaCargo Profile'"; \
    query "SELECT Field, Parent.Name FROM FieldPermissions WHERE SobjectType IN ('Shipment__c', 'Account') AND ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = '$guest_id')"; } \
    | jq -s -c '[.[][] | {field: .Field, parent: .Parent.Name}
                 | select((.field | startswith("Shipment__c.")) or (.field | test("^Account\\.[A-Za-z0-9_]+__c$")))]
                | unique')"
count="$(jq 'length' <<<"$guest_fls")"
if [[ "$count" -eq 0 ]]; then
    pass "the guest has 0 FieldPermissions rows on Shipment__c and the Account custom fields"
else
    fail "the guest has $count FieldPermissions rows on Shipment__c or Account custom fields: $(jq -r '[.[] | .parent + ":" + .field] | join(", ")' <<<"$guest_fls")"
fi

# ─── 4. Guest user time zone ────────────────────────────────────────────────
tz="$(jq -r '.[0].TimeZoneSidKey // empty' <<<"$guest")"
if [[ "$tz" == "$GUEST_TIME_ZONE" ]]; then
    pass "guest user TimeZoneSidKey is $GUEST_TIME_ZONE"
else
    fail "guest user TimeZoneSidKey is '$tz', expected '$GUEST_TIME_ZONE'"
fi

# ─── 5. Visualforce pages enabled for the guest ─────────────────────────────
# SetupEntityAccess rows of the guest profile and of every permission set
# assigned to the guest user (the profile's own permission set included).
page_ids="$( { query "SELECT SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'ApexPage' AND Parent.Profile.Name = 'RutaCargo Profile'"; \
    query "SELECT SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'ApexPage' AND ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = '$guest_id')"; } \
    | jq -s -r '[.[][].SetupEntityId] | unique | .[]')"
enabled_pages=''
if [[ -n "$page_ids" ]]; then
    id_list=''
    while IFS= read -r page_id; do
        # Every Id is validated as an ApexPage Id before it enters the query.
        if [[ ! "$page_id" =~ ^066[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
            fail "unexpected SetupEntityId '$page_id' for an ApexPage"
            finish
        fi
        id_list="${id_list:+$id_list,}'$page_id'"
    done <<<"$page_ids"
    pages="$(query "SELECT Name, NamespacePrefix FROM ApexPage WHERE Id IN ($id_list)")"
    enabled_pages="$(jq -r '[.[] | (if .NamespacePrefix then .NamespacePrefix + "__" else "" end) + .Name] | sort | join(",")' <<<"$pages")"
fi
expected_pages="$(tr ',' '\n' <<<"$GUEST_PAGES" | sort | paste -sd ',' -)"
if [[ "$enabled_pages" == "$expected_pages" ]]; then
    pass "guest Visualforce pages are exactly the allow-list ($expected_pages)"
else
    extra="$(comm -23 <(tr ',' '\n' <<<"$enabled_pages" | sed '/^$/d') <(tr ',' '\n' <<<"$expected_pages") | paste -sd ',' -)"
    missing="$(comm -13 <(tr ',' '\n' <<<"$enabled_pages" | sed '/^$/d') <(tr ',' '\n' <<<"$expected_pages") | paste -sd ',' -)"
    fail "guest Visualforce pages differ from the allow-list: not allowed '$extra', missing '$missing'"
fi

# ─── 5b. Apex classes enabled for the guest ─────────────────────────────────
# SetupEntityAccess rows of the guest profile and of every permission set
# assigned to the guest user (the profile's own permission set included) must
# name exactly the classes in GUEST_CLASSES (req-001 AC-001.6).
class_ids="$( { query "SELECT SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'ApexClass' AND Parent.Profile.Name = 'RutaCargo Profile'"; \
    query "SELECT SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'ApexClass' AND ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = '$guest_id')"; } \
    | jq -s -r '[.[][].SetupEntityId] | unique | .[]')"
enabled_classes=''
if [[ -n "$class_ids" ]]; then
    id_list=''
    while IFS= read -r class_id; do
        # Every Id is validated as an ApexClass Id before it enters the query.
        if [[ ! "$class_id" =~ ^01p[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
            fail "unexpected SetupEntityId '$class_id' for an ApexClass"
            finish
        fi
        id_list="${id_list:+$id_list,}'$class_id'"
    done <<<"$class_ids"
    classes="$(query "SELECT Name, NamespacePrefix FROM ApexClass WHERE Id IN ($id_list)")"
    enabled_classes="$(jq -r '[.[] | (if .NamespacePrefix then .NamespacePrefix + "__" else "" end) + .Name] | sort | join(",")' <<<"$classes")"
fi
expected_classes="$(tr ',' '\n' <<<"$GUEST_CLASSES" | sort | paste -sd ',' -)"
if [[ "$enabled_classes" == "$expected_classes" ]]; then
    pass "guest Apex classes are exactly the allow-list ($expected_classes)"
else
    extra="$(comm -23 <(tr ',' '\n' <<<"$enabled_classes" | sed '/^$/d') <(tr ',' '\n' <<<"$expected_classes") | paste -sd ',' -)"
    missing="$(comm -13 <(tr ',' '\n' <<<"$enabled_classes" | sed '/^$/d') <(tr ',' '\n' <<<"$expected_classes") | paste -sd ',' -)"
    fail "guest Apex classes differ from the allow-list: not allowed '$extra', missing '$missing'"
fi

# ─── 5c. Only PublicTrackingController calls the without-sharing selector ──
# Every .cls and .trigger file that names the selector (whole word, any case);
# grep exits 1 when nothing matches and 2 on an error, which fails the check.
selector_refs=''
grep_status=0
scan_dirs=("$SOURCE_ROOT/classes")
if [[ -d "$SOURCE_ROOT/triggers" ]]; then
    scan_dirs+=("$SOURCE_ROOT/triggers")
fi
selector_refs="$(grep -rliw --include='*.cls' --include='*.trigger' -- "$SELECTOR" "${scan_dirs[@]}" 2>&1)" \
    || grep_status=$?
if [[ "$grep_status" -gt 1 || ! -d "$SOURCE_ROOT/classes" ]]; then
    fail "could not scan the Apex source for $SELECTOR: ${selector_refs:-no classes directory}"
else
    other_callers="$(comm -23 \
        <(sed '/^$/d; s#.*/##' <<<"$selector_refs" | sort -u) \
        <(tr ' ' '\n' <<<"$SELECTOR_FILES" | sort -u) | paste -sd ',' -)"
    if [[ -z "$other_callers" ]]; then
        pass "only $SELECTOR_FILES name $SELECTOR in the Apex source"
    else
        fail "Apex source outside the allow-list names the without-sharing $SELECTOR: $other_callers"
    fi
fi

# ─── 6. Anonymous GET of the site home URL ──────────────────────────────────
# The host and path come from the site's own DomainSite row: the LWR pages are
# served by the ChatterNetworkPicasso site (RutaCargo1, prefix rutacargo); the
# Network and its ChatterNetwork site use the rutacargovforcesite prefix.
# Sets SITE_URL to "https://<host><path>" when the site has exactly one
# DomainSite row; otherwise records a violation and returns 1. Called without a
# subshell so that fail() counts.
SITE_URL=''
site_url() {
    local rows n
    SITE_URL=''
    rows="$(query "SELECT Domain.Domain, PathPrefix FROM DomainSite WHERE Site.Name = '$1' AND Site.SiteType = '$2'")"
    n="$(jq 'length' <<<"$rows")"
    if [[ "$n" -ne 1 ]]; then
        fail "site $1 ($2) has $n DomainSite rows, expected exactly 1"
        return 1
    fi
    SITE_URL="$(jq -r '.[0] | "https://" + (.Domain.Domain // "") + (.PathPrefix // "")' <<<"$rows")"
}
anonymous_get() {
    curl -s -o /dev/null -w '%{http_code}' --max-time 60 "$1" || true
}

home_prefix=''
if site_url 'RutaCargo1' 'ChatterNetworkPicasso'; then
    home_prefix="${SITE_URL##*/}"
    url="$SITE_URL/"
    code="$(anonymous_get "$url")"
    if [[ "$code" == "200" ]]; then
        pass "anonymous GET $url returns 200"
    else
        fail "anonymous GET $url returns $code, expected 200"
    fi
fi

# ─── 7. Self-registration pages closed to anonymous visitors ────────────────
# A refused page answers 401 with a script that sends the visitor to the LWR
# login page. The CustomSite's own selfRegPage answers 200 with that same
# script, so a 200 counts as refused only when its body is that redirect to
# "<lwr prefix>/login?ec=302" and nothing renders a registration form. A
# timeout, no answer (000), a 5xx or any other status proves nothing and fails.
# SELF_REG_TIMEOUT (seconds, default 60) bounds each GET.
if site_url 'RutaCargo' 'ChatterNetwork'; then
    login_redirect="/${home_prefix:-rutacargo}/login?ec=302"
    login_path="/${home_prefix:-rutacargo}/login"
    for page in $SELF_REG_PAGES; do
        url="$SITE_URL/$page"
        body_file="$(mktemp)"
        read -r code location <<<"$(curl -s -o "$body_file" -w '%{http_code} %{redirect_url}' \
            --max-time "${SELF_REG_TIMEOUT:-60}" "$url" || true)"
        code="${code:-000}"
        if [[ "$code" =~ ^(401|403|404)$ ]]; then
            pass "anonymous GET $url returns $code (refused)"
        elif [[ "$code" =~ ^3[0-9][0-9]$ ]]; then
            if [[ "$location" == "https://$(cut -d/ -f3 <<<"$SITE_URL")$login_path"* ]]; then
                pass "anonymous GET $url returns $code to the login page $location (refused)"
            else
                fail "anonymous GET $url returns $code to '${location:-no Location}', expected a redirect to $login_path"
            fi
        elif [[ "$code" != "200" ]]; then
            fail "anonymous GET $url returns $code, expected 401, 403, 404 or a redirect to login (refusal not proven)"
        elif grep -qF "$login_redirect" "$body_file" && ! grep -qi '<form' "$body_file"; then
            pass "anonymous GET $url returns 200 with only a redirect to $login_redirect (refused)"
        else
            fail "anonymous GET $url returns 200 with page content, expected a refusal or a redirect to login"
        fi
        rm -f "$body_file"
    done
fi

finish
