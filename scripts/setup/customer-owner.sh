#!/usr/bin/env bash
# Setup for the access of registered customers (odd/tasks/
# req-005-customer-signup.md, S1, AC-005.7). Run it after the customer profile,
# its password policy, the permission set RutaCargo_Customer and the role
# RutaCargo_Customer_Owner are deployed, and after the site exists
# (scripts/setup/DEPLOY-ORDER.md).
#
# Steps (idempotent: running it again changes nothing):
#   0. refuses an org that is not a sandbox or scratch org
#      (Organization.IsSandbox must be true); stops if the profile
#      "RutaCargo Customer" or the role RutaCargo_Customer_Owner is missing;
#   1. reads the guest default record owner of the sites RutaCargo and
#      RutaCargo1 (Site.GuestRecordDefaultOwnerId, the CustomSite field
#      siteGuestRecordDefaultOwner); fails if it is not set or the two differ;
#      gives that user the role RutaCargo_Customer_Owner when it has no role,
#      and refuses to replace another role (the owner decides). It never
#      touches sites/RutaCargo.site-meta.xml;
#   2. network phase 1, when the profile is not yet a member of the Network
#      RutaCargo: deploys scripts/setup/templates/RutaCargo.network-bootstrap
#      (force-app's network with the profile as a member and self-registration
#      off). The platform refuses a self-registration profile that is not
#      already a member ("You can only select profiles that are associated
#      with the experience."), so membership comes first;
#   3. network phase 2, when self-registration is off or uses another profile:
#      deploys force-app/main/default/networks/RutaCargo.network-meta.xml (the
#      final state: self-registration on with the profile "RutaCargo Customer"
#      and no default self-registration account);
#   4. reads the result back and fails unless the owner has the role, the
#      profile is a member, self-registration is on with that profile and no
#      default self-registration account exists.
#
# Both network deploys use a temporary metadata folder, so source tracking is
# not involved. The bootstrap must equal force-app's network except for the
# selfRegistration and selfRegProfile lines; the script fails otherwise.
#
# Usage: scripts/setup/customer-owner.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NETWORK_FILE="$ROOT/force-app/main/default/networks/RutaCargo.network-meta.xml"
BOOTSTRAP="$ROOT/scripts/setup/templates/RutaCargo.network-bootstrap"
CUSTOMER_PROFILE='RutaCargo Customer'
OWNER_ROLE='RutaCargo_Customer_Owner'
NETWORK_NAME='RutaCargo'
SITE_NAMES="'RutaCargo','RutaCargo1'"
API_VERSION='67.0'

die() { echo "customer-owner: $*" >&2; exit 1; }

# Runs a SOQL query and stores the records as JSON in ROWS; stops the script on
# an error. Called directly, never in a $(...) subshell, so that die ends the
# script.
ROWS='[]'
query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" == "0" ]] || die "query failed: $1"
    ROWS="$(jq -c '.result.records' <<<"$out")"
}

# Deploys one Network file (metadata format) from a temporary folder.
deploy_network() {
    local source="$1" label="$2" tmp out
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/networks"
    cp "$source" "$tmp/networks/$NETWORK_NAME.network"
    cat > "$tmp/package.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>$NETWORK_NAME</members>
        <name>Network</name>
    </types>
    <version>$API_VERSION</version>
</Package>
EOF
    out="$(cd "$ROOT" && sf project deploy start --metadata-dir "$tmp" --target-org "$ORG" --wait 30 --json 2>/dev/null || true)"
    rm -rf "$tmp"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "customer-owner: the $label network deploy failed in $ORG" >&2
        jq -r '.message // empty, (.result.details.componentFailures // [] | if type == "array" then .[] else . end | .problem // empty)' <<<"$out" >&2 2>/dev/null || true
        exit 1
    fi
    echo "customer-owner: deployed the $label network ($(jq -r '.result.id' <<<"$out"))"
}

# ─── 0. Never a production org; the profile and the role must exist ─────────
query "SELECT Id, IsSandbox FROM Organization"; org="$ROWS"
[[ "$(jq -r '.[0].IsSandbox' <<<"$org")" == "true" ]] || die "refused: $ORG is not a sandbox or scratch org"
echo "customer-owner: $ORG is a sandbox or scratch org"
query "SELECT Id FROM Profile WHERE Name = '$CUSTOMER_PROFILE'"; profile="$ROWS"
[[ "$(jq 'length' <<<"$profile")" == "1" ]] || die "profile $CUSTOMER_PROFILE not found; deploy it first (DEPLOY-ORDER.md)"
profile_id="$(jq -r '.[0].Id' <<<"$profile")"
query "SELECT Id FROM UserRole WHERE DeveloperName = '$OWNER_ROLE'"; role="$ROWS"
[[ "$(jq 'length' <<<"$role")" == "1" ]] || die "role $OWNER_ROLE not found; deploy it first (DEPLOY-ORDER.md)"
role_id="$(jq -r '.[0].Id' <<<"$role")"
[[ "$role_id" =~ ^00E[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || die "unexpected role Id"

# ─── 1. The guest default record owner gets the role ───────────────────────
query "SELECT Name, GuestRecordDefaultOwnerId FROM Site WHERE Name IN ($SITE_NAMES)"; sites="$ROWS"
jq -e 'any(.[]; .Name == "RutaCargo")' <<<"$sites" >/dev/null || die "site RutaCargo not found; deploy the site first"
if jq -e 'any(.[]; (.GuestRecordDefaultOwnerId // "") == "")' <<<"$sites" >/dev/null; then
    die "no guest default record owner is set on $(jq -r '[.[] | select((.GuestRecordDefaultOwnerId // "") == "") | .Name] | join(", ")' <<<"$sites"); set it in the site's guest user settings"
fi
owners="$(jq -r '[.[].GuestRecordDefaultOwnerId] | unique | .[]' <<<"$sites")"
[[ "$(wc -l <<<"$owners" | tr -d ' ')" == "1" ]] || die "the sites have different guest default record owners"
owner_id="$owners"
[[ "$owner_id" =~ ^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || die "unexpected owner Id"
query "SELECT Id, IsActive, UserRoleId, UserRole.DeveloperName FROM User WHERE Id = '$owner_id'"; owner="$ROWS"
[[ "$(jq -r '.[0].IsActive' <<<"$owner")" == "true" ]] || die "the guest default record owner is not an active user"
current_role="$(jq -r '.[0].UserRoleId // ""' <<<"$owner")"
if [[ "$current_role" == "$role_id" ]]; then
    echo "customer-owner: the guest default record owner already has the role $OWNER_ROLE"
elif [[ -z "$current_role" ]]; then
    out="$(sf data update record --sobject User --record-id "$owner_id" --values "UserRoleId=$role_id" --target-org "$ORG" --json 2>/dev/null || true)"
    [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" == "0" ]] || die "could not give the role $OWNER_ROLE to the guest default record owner: $(jq -r '.message // empty' <<<"$out" 2>/dev/null)"
    echo "customer-owner: gave the role $OWNER_ROLE to the guest default record owner"
else
    die "the guest default record owner already has the role $(jq -r '.[0].UserRole.DeveloperName // "unknown"' <<<"$owner"); refusing to replace it (give it $OWNER_ROLE or name another owner in Setup)"
fi

# ─── 2-3. Network: member first, then self-registration ────────────────────
[[ -f "$BOOTSTRAP" && -f "$NETWORK_FILE" ]] || die "network files not found"
strip() { grep -v -E '<selfReg(istration|Profile)>' "$1"; }
diff -q <(strip "$BOOTSTRAP") <(strip "$NETWORK_FILE") >/dev/null \
    || die "the bootstrap $BOOTSTRAP differs from $NETWORK_FILE beyond selfRegistration and selfRegProfile; update it"
grep -q '<selfRegistration>false</selfRegistration>' "$BOOTSTRAP" || die "the bootstrap must keep self-registration off"
grep -qiF "<profile>$CUSTOMER_PROFILE</profile>" "$BOOTSTRAP" || die "the bootstrap must list the profile $CUSTOMER_PROFILE as a member"

query "SELECT Id FROM Network WHERE Name = '$NETWORK_NAME'"; network="$ROWS"
[[ "$(jq 'length' <<<"$network")" == "1" ]] || die "Network $NETWORK_NAME not found; deploy the site first"
network_id="$(jq -r '.[0].Id' <<<"$network")"
[[ "$network_id" =~ ^0DB[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || die "unexpected Network Id"
is_member() {
    query "SELECT ParentId FROM NetworkMemberGroup WHERE NetworkId = '$network_id'"
    jq -e --arg p "$profile_id" 'any(.[]; .ParentId == $p)' <<<"$ROWS" >/dev/null
}
if is_member; then
    echo "customer-owner: the profile $CUSTOMER_PROFILE is already a member of $NETWORK_NAME"
else
    deploy_network "$BOOTSTRAP" 'member-only bootstrap'
    is_member || die "the profile $CUSTOMER_PROFILE is not a member after the bootstrap deploy"
fi
self_reg() {
    query "SELECT OptionsSelfRegistrationEnabled, SelfRegProfileId FROM Network WHERE Id = '$network_id'"
    jq -e --arg p "$profile_id" '.[0] | .OptionsSelfRegistrationEnabled == true and .SelfRegProfileId == $p' <<<"$ROWS" >/dev/null
}
if self_reg; then
    echo "customer-owner: self-registration is already on with the profile $CUSTOMER_PROFILE"
else
    deploy_network "$NETWORK_FILE" 'force-app (self-registration)'
fi

# ─── 4. Read back ───────────────────────────────────────────────────────────
query "SELECT UserRole.DeveloperName FROM User WHERE Id = '$owner_id'"
owner_role="$(jq -r '.[0].UserRole.DeveloperName // ""' <<<"$ROWS")"
[[ "$owner_role" == "$OWNER_ROLE" ]] || die "the guest default record owner does not have the role $OWNER_ROLE after the setup"
is_member || die "the profile $CUSTOMER_PROFILE is not a member of $NETWORK_NAME after the setup"
self_reg || die "self-registration is not on with the profile $CUSTOMER_PROFILE after the setup"
query "SELECT Id FROM NetworkSelfRegistration WHERE NetworkId = '$network_id'"
[[ "$(jq 'length' <<<"$ROWS")" == "0" ]] \
    || die "Network $NETWORK_NAME has a default self-registration account; remove it in Setup (Login & Registration)"
echo "customer-owner: done in $ORG: owner role, member, self-registration with $CUSTOMER_PROFILE, no default account"
