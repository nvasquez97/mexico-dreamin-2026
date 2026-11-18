#!/usr/bin/env bash
# Org check for the access of registered customers (odd/tasks/
# req-005-customer-signup.md, S1): the T1 part of AC-005.7 and the profile
# policy part of AC-005.4. Read-only: constant SOQL queries and one metadata
# retrieve into a temporary folder.
#
# Exits non-zero unless:
#   1. the profile "RutaCargo Customer" exists once, is custom, has the
#      Customer Community license and grants neither View All Data, Modify All
#      Data nor View All Users; it enables no user permission beyond
#      LICENSE_DEFAULT_USER_PERMISSIONS (the profile file revokes every one the
#      license would add) and never API Enabled; and it has no tab setting
#      beyond LICENSE_DEFAULT_TABS and no DefaultOn tab (the file hides them);
#   2. the profile has no object permission beyond the license defaults
#      (LICENSE_DEFAULT_OBJECTS, empty: the profile file revokes every object
#      the license would add), none on Account, Contact or Shipment__c, no View
#      All or Modify All on any object, no field permission on Shipment__c or
#      on the internal Account fields Credit_Limit__c and Credit_Risk__c, and
#      no field permission at all beyond LICENSE_DEFAULT_FIELDS (the profile
#      file revokes every field the license would add);
#   3. the permission set RutaCargo_Customer exists once and grants no object
#      permission and no field permission (REQ-006/007 add Shipment__c access
#      together with the sharing set), nor View All Data, Modify All Data or
#      View All Users;
#   4. the Network "RutaCargo" has the profile as a member
#      (NetworkMemberGroup), self-registration on, the profile as its
#      self-registration profile, and no default self-registration account
#      (no NetworkSelfRegistration row): a user can be created only by code
#      that names the account;
#   5. both sites RutaCargo and RutaCargo1 exist and the guest default record
#      owner of each (Site.GuestRecordDefaultOwnerId) is set and has the role
#      RutaCargo_Customer_Owner (an account that owns external users must be
#      owned by a user with a role);
#   6. the profile's password policy (ProfilePasswordPolicy, retrieved: SOQL
#      cannot read it) exists once and has minimum length 10, complexity 1
#      (letters and numbers), lockout after 5 invalid attempts for 15 minutes,
#      expiration 90 days, history 3 and no password question restriction;
#   7. (T2 part) the guest Apex class allow-list GUEST_CLASSES of
#      scripts/checks/guest-access-check.sh is exactly the guest classes of
#      REQ-001, REQ-002+003 and REQ-005 (EXPECTED_GUEST_CLASSES), and the Apex
#      classes enabled in the org for the guest profile "RutaCargo Profile" and
#      every permission set assigned to its users are exactly that list: the
#      system-mode helper CustomerRegistration and the CustomerPermissionAssigner
#      job are never guest entry points.
#
# A failed query or retrieve stops the check with exit code 3; violations exit 1.
#
# Usage: scripts/checks/customer-access-check.sh <org-alias>
set -uo pipefail
export LC_ALL=C

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CUSTOMER_PROFILE='RutaCargo Customer'
CUSTOMER_LICENSE='Customer Community'
CUSTOMER_PERMSET='RutaCargo_Customer'
OWNER_ROLE='RutaCargo_Customer_Owner'
NETWORK_NAME='RutaCargo'
SITE_NAMES="'RutaCargo','RutaCargo1'"
EXPECTED_SITES='RutaCargo RutaCargo1'
# Object permissions the platform keeps on the profile although its file does
# not grant them. Empty: any object permission row is a violation.
LICENSE_DEFAULT_OBJECTS=''
# User permissions (API names without the "Permissions" prefix), field
# permissions (FieldPermissions.Field) and tab settings the platform keeps on
# the profile although its file revokes every other license default. Anything
# else enabled, any other field permission row and any tab setting row is a
# violation.
#   EnableNotifications ("Send Outbound Messages"): the deploy refuses to turn
#     it off ("You may not turn off permission Send Outbound Messages for this
#     License Type"); the profile file declares it enabled.
#   Event.LocationId: the Metadata API has no such field ("no CustomField named
#     Event.LocationId found"), so the file cannot revoke it; Event has no
#     object permission on the profile.
#   ContactPointTypeConsent: a FieldPermissions row on ContactPointConsent with
#     no Object.Field name; the Metadata API refuses the name ("Need to specify
#     full name") and the describe has no such field; ContactPointConsent has
#     no object permission on the profile.
LICENSE_DEFAULT_USER_PERMISSIONS='EnableNotifications'
LICENSE_DEFAULT_FIELDS='ContactPointTypeConsent Event.LocationId'
LICENSE_DEFAULT_TABS=''
# Objects and fields a customer must never reach through the profile or the
# permission set in this requirement.
SENSITIVE_OBJECTS='Account Contact Shipment__c'
SENSITIVE_FIELDS="'Account.Credit_Limit__c','Account.Credit_Risk__c'"
# Guest Apex classes (req-001 S1, req-002-003 S2, req-005 S2 and S3), sorted.
GUEST_PROFILE='RutaCargo Profile'
EXPECTED_GUEST_CLASSES='CustomerLoginController,CustomerSignUpController,PublicTrackingController,RecipientDeliveryController'
GUEST_CHECK="$REPO_ROOT/scripts/checks/guest-access-check.sh"
# Expected password policy (S1).
EXPECTED_POLICY='minimumPasswordLength=10
passwordComplexity=1
maxLoginAttempts=5
lockoutInterval=15
passwordExpiration=90
passwordHistory=3
passwordQuestion=0'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
finish() {
    if [[ "$violations" -gt 0 ]]; then
        echo "customer-access-check: $violations violation(s) in $ORG"
        exit 1
    fi
    echo "customer-access-check: passed in $ORG"
    exit 0
}

# Runs a SOQL query and stores the records as JSON in ROWS; stops the script
# (exit 3) on an error. Called directly, never in a $(...) subshell, so that
# the exit ends the script.
ROWS='[]'
query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "ERROR: query failed: $1" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 3
    fi
    ROWS="$(jq -c '.result.records' <<<"$out")"
}

# Prints the lines of $1 (newline-separated) that are not in the allow-list $2
# (space- or comma-separated).
beyond() {
    comm -23 <(printf '%s\n' "$1" | grep -v '^$' | sort -u || true) <(tr ' ,' '\n\n' <<<"$2" | grep -v '^$' | sort -u || true)
}

# ─── 1. The customer profile ────────────────────────────────────────────────
query "SELECT Id, Name, UserLicense.Name FROM Profile WHERE Name = '$CUSTOMER_PROFILE'"; profile="$ROWS"
if [[ "$(jq 'length' <<<"$profile")" -ne 1 ]]; then
    fail "profile $CUSTOMER_PROFILE not found"
    profile_id=''
else
    profile_id="$(jq -r '.[0].Id' <<<"$profile")"
    license="$(jq -r '.[0].UserLicense.Name // ""' <<<"$profile")"
    if [[ "$license" == "$CUSTOMER_LICENSE" ]]; then
        pass "profile $CUSTOMER_PROFILE has the $CUSTOMER_LICENSE license"
    else
        fail "profile $CUSTOMER_PROFILE has the license '$license', expected $CUSTOMER_LICENSE"
    fi
    query "SELECT IsCustom, PermissionsViewAllData, PermissionsModifyAllData, PermissionsViewAllUsers FROM PermissionSet WHERE Profile.Name = '$CUSTOMER_PROFILE'"; pset="$ROWS"
    if jq -e 'length == 1 and .[0].IsCustom == true' <<<"$pset" >/dev/null; then
        pass "profile $CUSTOMER_PROFILE is a custom profile"
    else
        fail "profile $CUSTOMER_PROFILE is not a custom profile"
    fi
    if jq -e '.[0] | .PermissionsViewAllData == false and .PermissionsModifyAllData == false and .PermissionsViewAllUsers == false' <<<"$pset" >/dev/null; then
        pass "profile $CUSTOMER_PROFILE has no View All Data, Modify All Data or View All Users"
    else
        fail "profile $CUSTOMER_PROFILE grants View All Data, Modify All Data or View All Users: $(jq -c '.[0] | del(.attributes)' <<<"$pset")"
    fi
    # Every user permission of the profile: the Permissions* fields of its
    # permission set, read from the describe and validated before the query.
    describe="$(sf sobject describe --sobject PermissionSet --target-org "$ORG" --json 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$describe" 2>/dev/null)" != "0" ]]; then
        echo "ERROR: describe of PermissionSet failed" >&2
        exit 3
    fi
    perm_fields="$(jq -r '[.result.fields[].name | select(startswith("Permissions"))] | join(",")' <<<"$describe")"
    [[ "$perm_fields" =~ ^Permissions[A-Za-z0-9_]+(,Permissions[A-Za-z0-9_]+)*$ ]] || { echo "ERROR: unexpected PermissionSet permission fields" >&2; exit 3; }
    [[ ",$perm_fields," == *",PermissionsApiEnabled,"* ]] || { echo "ERROR: PermissionSet has no PermissionsApiEnabled field" >&2; exit 3; }
    query "SELECT $perm_fields FROM PermissionSet WHERE Profile.Name = '$CUSTOMER_PROFILE'"; user_perms="$ROWS"
    [[ "$(jq 'length' <<<"$user_perms")" -eq 1 ]] || { echo "ERROR: expected one permission set for the profile" >&2; exit 3; }
    enabled="$(jq -r '.[0] | to_entries[] | select(.value == true) | .key | sub("^Permissions"; "")' <<<"$user_perms")"
    extra="$(beyond "$enabled" "$LICENSE_DEFAULT_USER_PERMISSIONS")"
    if [[ -z "$extra" ]]; then
        pass "profile $CUSTOMER_PROFILE: no user permission beyond the license defaults ($(grep -c . <<<"$enabled" || true) enabled)"
    else
        fail "profile $CUSTOMER_PROFILE: user permissions beyond the license defaults: $(tr '\n' ' ' <<<"$extra")"
    fi
    if jq -e '.[0].PermissionsApiEnabled == false' <<<"$user_perms" >/dev/null; then
        pass "profile $CUSTOMER_PROFILE: API Enabled is off"
    else
        fail "profile $CUSTOMER_PROFILE: API Enabled is on"
    fi
    # Tab settings: a hidden tab has no row; DefaultOn is never allowed.
    query "SELECT Name, Visibility FROM PermissionSetTabSetting WHERE Parent.Profile.Name = '$CUSTOMER_PROFILE'"; tabs="$ROWS"
    extra="$(beyond "$(jq -r '.[].Name' <<<"$tabs")" "$LICENSE_DEFAULT_TABS")"
    if [[ -z "$extra" ]]; then
        pass "profile $CUSTOMER_PROFILE: no tab setting beyond the license defaults ($(jq 'length' <<<"$tabs") row(s))"
    else
        fail "profile $CUSTOMER_PROFILE: $(grep -c . <<<"$extra") tab setting(s) beyond the license defaults, e.g. $(head -5 <<<"$extra" | tr '\n' ' ')"
    fi
    on_tabs="$(jq -r '[.[] | select(.Visibility == "DefaultOn")] | length' <<<"$tabs")"
    if [[ "$on_tabs" -eq 0 ]]; then
        pass "profile $CUSTOMER_PROFILE: no DefaultOn tab"
    else
        fail "profile $CUSTOMER_PROFILE: $on_tabs DefaultOn tab(s)"
    fi
fi

# Checks the ObjectPermissions and FieldPermissions rows of one permission set
# scope (a SOQL condition on Parent). $1 label, $2 condition, $3 allowed objects.
check_grants() {
    local label="$1" cond="$2" allowed="$3" rows objects extra sensitive vam fields
    query "SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords FROM ObjectPermissions WHERE $cond"; rows="$ROWS"
    objects="$(jq -r '.[].SobjectType' <<<"$rows" | sort -u)"
    extra="$(comm -23 <(printf '%s\n' "$objects" | grep -v '^$' || true) <(tr ' ,' '\n\n' <<<"$allowed" | grep -v '^$' | sort -u || true))"
    if [[ -z "$extra" ]]; then
        pass "$label: no object permission beyond the license defaults ($(jq 'length' <<<"$rows") row(s))"
    else
        fail "$label: object permissions beyond the license defaults: $(tr '\n' ' ' <<<"$extra")"
    fi
    for obj in $SENSITIVE_OBJECTS; do
        sensitive="$(jq -r --arg o "$obj" '[.[] | select(.SobjectType == $o)] | length' <<<"$rows")"
        if [[ "$sensitive" -eq 0 ]]; then
            pass "$label: no object permission on $obj"
        else
            fail "$label: has an object permission on $obj"
        fi
    done
    vam="$(jq -r '[.[] | select(.PermissionsViewAllRecords or .PermissionsModifyAllRecords) | .SobjectType] | join(" ")' <<<"$rows")"
    if [[ -z "$vam" ]]; then
        pass "$label: no View All or Modify All on any object"
    else
        fail "$label: View All or Modify All on $vam"
    fi
    query "SELECT Field, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE $cond AND (SobjectType = 'Shipment__c' OR Field IN ($SENSITIVE_FIELDS))"; fields="$ROWS"
    if [[ "$(jq 'length' <<<"$fields")" -eq 0 ]]; then
        pass "$label: no field permission on Shipment__c, Account.Credit_Limit__c or Account.Credit_Risk__c"
    else
        fail "$label: field permissions on $(jq -r '[.[].Field] | join(" ")' <<<"$fields")"
    fi
}

# ─── 2. No object or field permission on the profile ───────────────────────
if [[ -n "$profile_id" ]]; then
    check_grants "profile $CUSTOMER_PROFILE" "Parent.Profile.Name = '$CUSTOMER_PROFILE'" "$LICENSE_DEFAULT_OBJECTS"
    query "SELECT Field FROM FieldPermissions WHERE Parent.Profile.Name = '$CUSTOMER_PROFILE'"; profile_fields="$ROWS"
    extra="$(beyond "$(jq -r '.[].Field' <<<"$profile_fields")" "$LICENSE_DEFAULT_FIELDS")"
    if [[ -z "$extra" ]]; then
        pass "profile $CUSTOMER_PROFILE: no field permission beyond the license defaults ($(jq 'length' <<<"$profile_fields") row(s))"
    else
        fail "profile $CUSTOMER_PROFILE: $(grep -c . <<<"$extra") field permission(s) beyond the license defaults, e.g. $(head -5 <<<"$extra" | tr '\n' ' ')"
    fi
fi

# ─── 3. The actor permission set grants nothing yet ────────────────────────
query "SELECT Id, PermissionsViewAllData, PermissionsModifyAllData, PermissionsViewAllUsers FROM PermissionSet WHERE Name = '$CUSTOMER_PERMSET'"; permset="$ROWS"
if [[ "$(jq 'length' <<<"$permset")" -ne 1 ]]; then
    fail "permission set $CUSTOMER_PERMSET not found"
else
    check_grants "permission set $CUSTOMER_PERMSET" "Parent.Name = '$CUSTOMER_PERMSET'" ''
    query "SELECT Field FROM FieldPermissions WHERE Parent.Name = '$CUSTOMER_PERMSET'"; all_fields="$ROWS"
    if [[ "$(jq 'length' <<<"$all_fields")" -eq 0 ]]; then
        pass "permission set $CUSTOMER_PERMSET: no field permission at all"
    else
        fail "permission set $CUSTOMER_PERMSET: field permissions on $(jq -r '[.[].Field] | join(" ")' <<<"$all_fields")"
    fi
    if jq -e '.[0] | .PermissionsViewAllData == false and .PermissionsModifyAllData == false and .PermissionsViewAllUsers == false' <<<"$permset" >/dev/null; then
        pass "permission set $CUSTOMER_PERMSET has no View All Data, Modify All Data or View All Users"
    else
        fail "permission set $CUSTOMER_PERMSET grants View All Data, Modify All Data or View All Users"
    fi
fi

# ─── 4. Network membership and self-registration ───────────────────────────
query "SELECT Id, OptionsSelfRegistrationEnabled, SelfRegProfileId FROM Network WHERE Name = '$NETWORK_NAME'"; network="$ROWS"
if [[ "$(jq 'length' <<<"$network")" -ne 1 ]]; then
    fail "Network $NETWORK_NAME not found"
else
    network_id="$(jq -r '.[0].Id' <<<"$network")"
    [[ "$network_id" =~ ^0DB[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || { echo "ERROR: unexpected Network Id" >&2; exit 3; }
    query "SELECT ParentId FROM NetworkMemberGroup WHERE NetworkId = '$network_id'"; members="$ROWS"
    if [[ -n "$profile_id" ]] && jq -e --arg p "$profile_id" 'any(.[]; .ParentId == $p)' <<<"$members" >/dev/null; then
        pass "Network $NETWORK_NAME has the profile $CUSTOMER_PROFILE as a member"
    else
        fail "Network $NETWORK_NAME does not have the profile $CUSTOMER_PROFILE as a member"
    fi
    if [[ "$(jq -r '.[0].OptionsSelfRegistrationEnabled' <<<"$network")" == "true" ]]; then
        pass "Network $NETWORK_NAME has self-registration on"
    else
        fail "Network $NETWORK_NAME has self-registration off"
    fi
    if [[ -n "$profile_id" && "$(jq -r '.[0].SelfRegProfileId // ""' <<<"$network")" == "$profile_id" ]]; then
        pass "Network $NETWORK_NAME self-registers users with the profile $CUSTOMER_PROFILE"
    else
        fail "Network $NETWORK_NAME self-registration profile is '$(jq -r '.[0].SelfRegProfileId // "none"' <<<"$network")', expected $CUSTOMER_PROFILE (${profile_id:-missing})"
    fi
    query "SELECT Id, AccountId FROM NetworkSelfRegistration WHERE NetworkId = '$network_id'"; default_account="$ROWS"
    if [[ "$(jq 'length' <<<"$default_account")" -eq 0 ]]; then
        pass "Network $NETWORK_NAME has no default self-registration account"
    else
        fail "Network $NETWORK_NAME has a default self-registration account: $(jq -r '[.[].AccountId] | join(" ")' <<<"$default_account")"
    fi
fi

# ─── 5. The guest default record owner has the owner role ──────────────────
query "SELECT Name, GuestRecordDefaultOwnerId FROM Site WHERE Name IN ($SITE_NAMES)"; sites="$ROWS"
missing_sites="$(beyond "$(tr ' ' '\n' <<<"$EXPECTED_SITES")" "$(jq -r '[.[].Name] | join(" ")' <<<"$sites")")"
if [[ -n "$missing_sites" ]]; then
    fail "site(s) not found: $(tr '\n' ' ' <<<"$missing_sites")"
fi
if [[ "$(jq 'length' <<<"$sites")" -gt 0 ]]; then
    while IFS=$'\t' read -r site_name owner_id; do
        if [[ ! "$owner_id" =~ ^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
            fail "site $site_name has no guest default record owner"
            continue
        fi
        query "SELECT UserRole.DeveloperName FROM User WHERE Id = '$owner_id'"; owner="$ROWS"
        role="$(jq -r '.[0].UserRole.DeveloperName // "none"' <<<"$owner")"
        if [[ "$role" == "$OWNER_ROLE" ]]; then
            pass "site $site_name: the guest default record owner has the role $OWNER_ROLE"
        else
            fail "site $site_name: the guest default record owner has the role '$role', expected $OWNER_ROLE"
        fi
    done < <(jq -r '.[] | [.Name, (.GuestRecordDefaultOwnerId // "")] | @tsv' <<<"$sites")
fi

# ─── 6. The profile's password policy (retrieved) ──────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
retrieve="$(cd "$REPO_ROOT" && sf project retrieve start --metadata 'ProfilePasswordPolicy:*' --target-metadata-dir "$tmp/policies" --unzip --target-org "$ORG" --json 2>/dev/null || true)"
if [[ "$(jq -r '.status // 1' <<<"$retrieve" 2>/dev/null)" != "0" ]]; then
    echo "ERROR: retrieve of ProfilePasswordPolicy failed" >&2
    jq -r '.message // empty' <<<"$retrieve" >&2 2>/dev/null || true
    exit 3
fi
policy_files=()
while IFS= read -r f; do
    [[ -n "$f" ]] && policy_files+=("$f")
done < <(grep -rliF "<profile>$CUSTOMER_PROFILE</profile>" "$tmp/policies" --include='*.profilePasswordPolicy' 2>/dev/null || true)
if [[ "${#policy_files[@]}" -ne 1 ]]; then
    fail "profile $CUSTOMER_PROFILE has ${#policy_files[@]} password policies, expected exactly 1"
else
    actual=''
    before="$violations"
    while IFS='=' read -r key expected; do
        value="$(grep -oE "<$key>[^<]*</$key>" "${policy_files[0]}" | sed -E "s#</?$key>##g")"
        actual+="$key=$value "
        if [[ "$value" != "$expected" ]]; then
            fail "password policy of $CUSTOMER_PROFILE: $key is '${value:-missing}', expected $expected"
        fi
    done <<<"$EXPECTED_POLICY"
    if [[ "$violations" -eq "$before" ]]; then
        pass "password policy of $CUSTOMER_PROFILE matches S1: $actual"
    fi
fi

# ─── 7. Guest Apex classes (T2 part) ───────────────────────────────────────
# The allow-list in guest-access-check.sh (source) ...
script_classes="$(grep -E "^GUEST_CLASSES=" "$GUEST_CHECK" 2>/dev/null | head -1 | sed -E "s/^GUEST_CLASSES='([^']*)'.*/\1/" | tr ',' '\n' | sed '/^$/d' | sort | paste -sd ',' -)"
if [[ "$script_classes" == "$EXPECTED_GUEST_CLASSES" ]]; then
    pass "guest-access-check.sh allows exactly the guest classes $EXPECTED_GUEST_CLASSES"
else
    fail "guest-access-check.sh allows '${script_classes:-nothing}', expected $EXPECTED_GUEST_CLASSES"
fi
# ... and the classes the org enables for the guest profile and every permission
# set assigned to its users (the profile's own permission set included).
query "SELECT SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'ApexClass' AND Parent.Profile.Name = '$GUEST_PROFILE'"; profile_classes="$ROWS"
query "SELECT SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'ApexClass' AND ParentId IN (SELECT PermissionSetId FROM PermissionSetAssignment WHERE Assignee.Profile.Name = '$GUEST_PROFILE')"; permset_classes="$ROWS"
class_ids="$(jq -s -r '[.[][].SetupEntityId] | unique | .[]' <<<"$profile_classes $permset_classes")"
org_classes=''
if [[ -n "$class_ids" ]]; then
    id_list=''
    while IFS= read -r class_id; do
        # Every Id is validated as an ApexClass Id before it enters the query.
        [[ "$class_id" =~ ^01p[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || { echo "ERROR: unexpected ApexClass Id" >&2; exit 3; }
        id_list="${id_list:+$id_list,}'$class_id'"
    done <<<"$class_ids"
    query "SELECT Name, NamespacePrefix FROM ApexClass WHERE Id IN ($id_list)"; classes="$ROWS"
    org_classes="$(jq -r '[.[] | (if .NamespacePrefix then .NamespacePrefix + "__" else "" end) + .Name] | sort | join(",")' <<<"$classes")"
fi
if [[ "$org_classes" == "$EXPECTED_GUEST_CLASSES" ]]; then
    pass "the guest profile $GUEST_PROFILE enables exactly the Apex classes $EXPECTED_GUEST_CLASSES"
else
    fail "the guest profile $GUEST_PROFILE enables the Apex classes '${org_classes:-none}', expected $EXPECTED_GUEST_CLASSES"
fi

finish
