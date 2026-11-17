#!/usr/bin/env bash
# Org check for AC-004.5 (odd/tasks/req-004-carrier-status.md, S3): the EntregaYa
# integration access is least privilege (BR-04, BR-09, P4).
# Read-only: SOQL queries, one describe and a metadata retrieve into a temporary
# folder.
#
# Exits non-zero unless:
#   1. Apex class EntregaYaStatusResource is granted only through the permission
#      set RutaCargo_EntregaYa_Integration and the System Administrator profile
#      (and the permission set does grant it);
#   2. custom permission RutaCargo_EntregaYa_Sender is granted only through
#      RutaCargo_EntregaYa_Integration (and it does grant it);
#   2b. the permission set's setup entity access (SetupEntityAccess: Apex
#      classes, Visualforce pages, custom permissions, apps, connected apps...) is
#      exactly ApexClass EntregaYaStatusResource and CustomPermission
#      RutaCargo_EntregaYa_Sender, and it has no tab visibility
#      (PermissionSetTabSetting);
#   3. among all the system permissions of the permission set (every boolean
#      Permissions* field of PermissionSet), exactly API Enabled and Apex REST
#      Services are enabled;
#   4. the permission set's only object permission is Shipment__c, exactly Read
#      and Edit (no Create, Delete, View All, Modify All, View All Fields);
#   5. its field permissions are exactly read+edit on Shipment__c.Status__c,
#      Last_Location__c, Last_Update__c, Delivered_At__c and Proof_Id__c, and
#      nothing on Delivery_Access_Code_Hash__c, Recipient_*, Price__c,
#      Carrier_Cost__c or Internal_Notes__c;
#   6. the public group RutaCargo_EntregaYa_Integration exists (no bosses) and the
#      deployed sharing rules (retrieved, not the local file) share every
#      shipment (Name notEqual '') with it, Read/Write (Edit).
# And, for AC-004.6 (S4, D2, P4, P5):
#   7. exactly one active user holds RutaCargo_EntregaYa_Integration; its profile
#      is "Minimum Access - API Only Integrations", it holds the "Salesforce API
#      Integration" permission set license, RutaCargo_EntregaYa_Integration is its
#      only assigned permission set (no other set, no group), it is a member of
#      the group RutaCargo_EntregaYa_Integration and nobody else is;
#   8. the External Client App EntregaYa_Status exists; its OAuth scopes are
#      exactly Api; its OAuth policies enable the client credentials flow with
#      that user as the execution user, permitted users "Admin approved users are
#      pre-authorized", IP restrictions enforced, no token exchange and no guest
#      code-credential flow; the pre-authorized permission set is exactly
#      RutaCargo_EntregaYa_Integration;
#   8b. the versioned app settings in force-app (the deployed global OAuth
#      settings are not exposed by any data or Tooling object, and a retrieve
#      would bring the consumer credentials): EntregaYa_Status_glbloauth enables
#      the client credentials flow and no device, token exchange, code-credential
#      or JWT flow, requires PKCE and the secret, rotates nothing and carries no
#      consumer key, secret or certificate; EntregaYa_Status_oauth has the scope
#      Api only;
#   9. no consumer key, consumer secret, access token or org-specific
#      integration username is in the repository: the working tree (tracked and
#      untracked, not ignored files) and the whole git history.
# The consumer secret is never read: the configuration comes from the
# ExternalClientApplication, ExtlClntAppOauthSettings and ExtlClntAppOauthPlcyCnfg
# records, not from the ExtlClntAppGlobalOauthSettings metadata (which carries the
# consumer credentials).
# Any failed query, describe or retrieve stops the script with exit code 3.
#
# Usage: scripts/checks/entregaya-access-check.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ADMIN_PROFILE='System Administrator'
PERMSET='RutaCargo_EntregaYa_Integration'
GROUP_NAME='RutaCargo_EntregaYa_Integration'
CLASS_NAME='EntregaYaStatusResource'
CUSTOM_PERMISSION='RutaCargo_EntregaYa_Sender'
EXPECTED_USER_PERMS='PermissionsApexRestServices,PermissionsApiEnabled'
STATUS_FIELDS='Shipment__c.Delivered_At__c,Shipment__c.Last_Location__c,Shipment__c.Last_Update__c,Shipment__c.Proof_Id__c,Shipment__c.Status__c'
INTEGRATION_PROFILE='Minimum Access - API Only Integrations'
API_INTEGRATION_PSL='SalesforceAPIIntegrationPsl'
ECA_NAME='EntregaYa_Status'
PERMITTED_USERS='AdminApprovedPreAuthorized'
IP_ENFORCED='Enforce'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
abort() { echo "ERROR: $*" >&2; exit 3; }

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

# Prints the only Id of a one-row query result after checking its key prefix.
single_id() {
    local records="$1" prefix="$2" what="$3" count id
    count="$(jq 'length' <<<"$records")"
    [[ "$count" == "1" ]] || abort "expected exactly 1 $what, found $count"
    id="$(jq -r '.[0].Id' <<<"$records")"
    [[ "$id" =~ ^${prefix}[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || abort "unexpected $what Id '$id'"
    echo "$id"
}

# Lists who holds a setup entity, from SetupEntityAccess records:
# "profile:<name>" or "permset:<name>", one per line.
holders() {
    jq -r '.[] | if .Parent.IsOwnedByProfile then "profile:" + .Parent.Profile.Name else "permset:" + .Parent.Name end' <<<"$1" | sort
}
ACCESS_FIELDS='Parent.Name, Parent.IsOwnedByProfile, Parent.Profile.Name'

# Every query result is assigned to a variable first, so a failed query (exit 3
# inside the command substitution) stops the script under set -e.
records="$(query "SELECT Id FROM PermissionSet WHERE Name = '$PERMSET' AND NamespacePrefix = null")"
permset_id="$(single_id "$records" 0PS "permission set $PERMSET")"

# ─── 1. Apex class access ──────────────────────────────────────────────────
records="$(query "SELECT Id FROM ApexClass WHERE Name = '$CLASS_NAME' AND NamespacePrefix = null")"
class_id="$(single_id "$records" 01p "Apex class $CLASS_NAME")"
access="$(query "SELECT $ACCESS_FIELDS FROM SetupEntityAccess WHERE SetupEntityId = '$class_id'")"
seen=0
while IFS= read -r who; do
    [[ -z "$who" ]] && continue
    case "$who" in
        "permset:$PERMSET") seen=1; pass "$CLASS_NAME granted to $who" ;;
        "profile:$ADMIN_PROFILE") pass "$CLASS_NAME granted to $who (allowed)" ;;
        *) fail "$CLASS_NAME granted to $who" ;;
    esac
done <<<"$(holders "$access")"
[[ "$seen" == 1 ]] || fail "$PERMSET does not grant access to $CLASS_NAME"

# ─── 2. Custom permission ──────────────────────────────────────────────────
records="$(query "SELECT Id FROM CustomPermission WHERE DeveloperName = '$CUSTOM_PERMISSION' AND NamespacePrefix = null")"
cp_id="$(single_id "$records" 0CP "custom permission $CUSTOM_PERMISSION")"
access="$(query "SELECT $ACCESS_FIELDS FROM SetupEntityAccess WHERE SetupEntityId = '$cp_id'")"
seen=0
while IFS= read -r who; do
    [[ -z "$who" ]] && continue
    if [[ "$who" == "permset:$PERMSET" ]]; then
        seen=1; pass "$CUSTOM_PERMISSION granted to $who"
    else
        fail "$CUSTOM_PERMISSION granted to $who"
    fi
done <<<"$(holders "$access")"
[[ "$seen" == 1 ]] || fail "$PERMSET does not grant $CUSTOM_PERMISSION"

# ─── 2b. Everything else the permission set grants ─────────────────────────
# SetupEntityAccess covers Apex classes, Visualforce pages, custom permissions,
# apps (TabSet), connected apps, External Client Apps and the other setup
# entities: exactly the class, the custom permission and, once the External
# Client App EntregaYa_Status is deployed, that app (its pre-authorization,
# AC-004.6) are allowed.
eca_rows="$(query "SELECT Id FROM ExternalClientApplication WHERE DeveloperName = '$ECA_NAME'")"
eca_entity=''
eca_label=''
if [[ "$(jq 'length' <<<"$eca_rows")" == "1" ]]; then
    eca_entity="ExternalClientApplication:$(jq -r '.[0].Id' <<<"$eca_rows")"
    eca_label=" and ExternalClientApplication $ECA_NAME"
fi
entities="$(query "SELECT SetupEntityType, SetupEntityId FROM SetupEntityAccess WHERE ParentId = '$permset_id'")"
expected_entities="$(printf '%s\n' "ApexClass:$class_id" "CustomPermission:$cp_id" "$eca_entity" | sed '/^$/d' | sort | paste -sd, -)"
actual_entities="$(jq -r '[.[] | "\(.SetupEntityType):\(.SetupEntityId)"] | sort | join(",")' <<<"$entities")"
if [[ "$actual_entities" == "$expected_entities" ]]; then
    pass "$PERMSET grants only ApexClass $CLASS_NAME, CustomPermission $CUSTOM_PERMISSION$eca_label (setup entities)"
else
    while IFS= read -r entity; do
        [[ -z "$entity" ]] && continue
        [[ ",$expected_entities," == *",$entity,"* ]] || fail "$PERMSET grants setup entity $entity"
    done <<<"$(tr ',' '\n' <<<"$actual_entities")"
    [[ ",$actual_entities," == *",ApexClass:$class_id,"* && ",$actual_entities," == *",CustomPermission:$cp_id,"* ]] \
        || fail "$PERMSET setup entities must be exactly $expected_entities, are: ${actual_entities:-nothing}"
fi
tabs="$(query "SELECT Name, Visibility FROM PermissionSetTabSetting WHERE ParentId = '$permset_id'")"
tab_list="$(jq -r '[.[] | "\(.Name)=\(.Visibility)"] | sort | join(", ")' <<<"$tabs")"
if [[ -z "$tab_list" ]]; then
    pass "$PERMSET has no tab visibility"
else
    fail "$PERMSET has tab visibility: $tab_list"
fi

# ─── 3. System permissions of the permission set ───────────────────────────
describe="$(sf sobject describe --sobject PermissionSet --target-org "$ORG" --json 2>/dev/null || true)"
[[ "$(jq -r '.status // 1' <<<"$describe" 2>/dev/null)" == "0" ]] || abort "describe of PermissionSet failed"
perm_fields=()
while IFS= read -r field; do perm_fields+=("$field"); done \
    < <(jq -r '.result.fields[] | select(.type == "boolean" and (.name | startswith("Permissions"))) | .name' <<<"$describe")
[[ "${#perm_fields[@]}" -gt 100 ]] || abort "describe of PermissionSet returned only ${#perm_fields[@]} Permissions fields"
enabled=()
for ((i = 0; i < ${#perm_fields[@]}; i += 80)); do
    chunk="$(IFS=,; echo "${perm_fields[*]:i:80}")"
    row="$(query "SELECT $chunk FROM PermissionSet WHERE Id = '$permset_id'")"
    while IFS= read -r name; do
        [[ -n "$name" ]] && enabled+=("$name")
    done <<<"$(jq -r '.[0] | to_entries[] | select(.value == true) | .key' <<<"$row")"
done
actual_perms="$(printf '%s\n' "${enabled[@]:-}" | sed '/^$/d' | sort | paste -sd, -)"
if [[ "$actual_perms" == "$EXPECTED_USER_PERMS" ]]; then
    pass "$PERMSET enables only ApiEnabled and ApexRestServices (of ${#perm_fields[@]} system permissions)"
else
    fail "$PERMSET must enable exactly $EXPECTED_USER_PERMS, enables: ${actual_perms:-nothing}"
fi

# ─── 4. Object permissions ─────────────────────────────────────────────────
objects="$(query "SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords, PermissionsViewAllFields FROM ObjectPermissions WHERE ParentId = '$permset_id'")"
shipment_seen=0
while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    object="$(jq -r .SobjectType <<<"$row")"
    flags="$(jq -r '"read=\(.PermissionsRead) create=\(.PermissionsCreate) edit=\(.PermissionsEdit) delete=\(.PermissionsDelete) viewAll=\(.PermissionsViewAllRecords) modifyAll=\(.PermissionsModifyAllRecords) viewAllFields=\(.PermissionsViewAllFields)"' <<<"$row")"
    if [[ "$object" == "Shipment__c" ]]; then
        shipment_seen=1
        if jq -e '.PermissionsRead and .PermissionsEdit and (.PermissionsCreate | not) and (.PermissionsDelete | not)
                  and (.PermissionsViewAllRecords | not) and (.PermissionsModifyAllRecords | not)
                  and (.PermissionsViewAllFields | not)' <<<"$row" >/dev/null; then
            pass "$PERMSET grants Shipment__c Read/Edit only ($flags)"
        else
            fail "$PERMSET must grant Shipment__c exactly Read and Edit ($flags)"
        fi
    else
        fail "$PERMSET grants access to $object ($flags)"
    fi
done <<<"$(jq -c '.[]' <<<"$objects")"
[[ "$shipment_seen" == 1 ]] || fail "$PERMSET grants no access to Shipment__c"

# ─── 5. Field permissions ──────────────────────────────────────────────────
fields="$(query "SELECT Field, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE ParentId = '$permset_id'")"
granted="$(jq -r '[.[] | select(.PermissionsRead or .PermissionsEdit) | .Field] | sort | join(",")' <<<"$fields")"
partial="$(jq -r '[.[] | select((.PermissionsRead or .PermissionsEdit) and ((.PermissionsRead and .PermissionsEdit) | not)) | .Field] | sort | join(", ")' <<<"$fields")"
if [[ "$granted" == "$STATUS_FIELDS" && -z "$partial" ]]; then
    pass "$PERMSET has read/edit FLS only on $STATUS_FIELDS"
else
    fail "$PERMSET must have read+edit FLS exactly on $STATUS_FIELDS; has: ${granted:-nothing}${partial:+ (not read+edit: $partial)}"
fi
# FieldPermissions.Field does not support LIKE in SOQL: the restricted fields
# are matched on the records already read.
forbidden="$(jq -r '[.[] | select((.PermissionsRead or .PermissionsEdit)
    and ((.Field | startswith("Shipment__c.Recipient_"))
         or (.Field | IN("Shipment__c.Delivery_Access_Code_Hash__c", "Shipment__c.Price__c",
                         "Shipment__c.Carrier_Cost__c", "Shipment__c.Internal_Notes__c")))) | .Field] | sort | join(", ")' <<<"$fields")"
if [[ -z "$forbidden" ]]; then
    pass "$PERMSET has nothing on Delivery_Access_Code_Hash__c, Recipient_*, Price__c, Carrier_Cost__c, Internal_Notes__c"
else
    fail "$PERMSET has access to restricted fields: $forbidden"
fi

# ─── 6. Group and deployed sharing rule ────────────────────────────────────
groups="$(query "SELECT Id, DoesIncludeBosses FROM Group WHERE DeveloperName = '$GROUP_NAME' AND Type = 'Regular'")"
if [[ "$(jq 'length' <<<"$groups")" != "1" ]]; then
    fail "public group $GROUP_NAME not found"
elif [[ "$(jq -r '.[0].DoesIncludeBosses' <<<"$groups")" != "false" ]]; then
    fail "public group $GROUP_NAME grants access to managers (DoesIncludeBosses)"
else
    pass "public group $GROUP_NAME exists, without managers"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
retrieve="$(sf project retrieve start --metadata "SharingRules:Shipment__c" \
    --target-metadata-dir "$tmp/rules" --unzip --wait 10 --target-org "$ORG" --json 2>/dev/null || true)"
[[ "$(jq -r '.status // 1' <<<"$retrieve" 2>/dev/null)" == "0" ]] || abort "retrieve of the Shipment__c sharing rules failed"

rule_report="$(python3 -I - "$tmp/rules" "$GROUP_NAME" <<'PY'
import pathlib, sys
import xml.etree.ElementTree as ET

root_dir, group = pathlib.Path(sys.argv[1]), sys.argv[2]
ns = {"m": "http://soap.sforce.com/2006/04/metadata"}
criteria = [("Name", "notEqual", "")]

def text(node, path):
    found = node.find(path, ns)
    return (found.text or "").strip() if found is not None else ""

files = list(root_dir.rglob("Shipment__c.sharingRules"))
if not files:
    print("FAIL Shipment__c: no sharing rules retrieved")
    sys.exit(0)
matched = []
for rule in ET.parse(files[0]).getroot().findall("m:sharingCriteriaRules", ns):
    items = [(text(i, "m:field"), text(i, "m:operation"), text(i, "m:value"))
             for i in rule.findall("m:criteriaItems", ns)]
    if text(rule, "m:sharedTo/m:group") != group or items != criteria:
        continue
    problems = []
    if text(rule, "m:accessLevel") != "Edit":
        problems.append("accessLevel " + text(rule, "m:accessLevel"))
    if text(rule, "m:booleanFilter"):
        problems.append("booleanFilter " + text(rule, "m:booleanFilter"))
    if text(rule, "m:includeRecordsOwnedByAll") != "true":
        problems.append("includeRecordsOwnedByAll " + text(rule, "m:includeRecordsOwnedByAll"))
    matched.append((text(rule, "m:fullName"), problems))
if not matched:
    print(f"FAIL Shipment__c: no criteria rule {criteria} sharing to group {group}")
for name, problems in matched:
    if problems:
        print(f"FAIL Shipment__c.{name}: " + "; ".join(problems))
    else:
        print(f"OK Shipment__c.{name}: every shipment shared Read/Write with {group}")
PY
)"
while IFS= read -r line; do
    case "$line" in
        OK*) pass "${line#OK }" ;;
        FAIL*) fail "${line#FAIL }" ;;
    esac
done <<<"$rule_report"

# ─── 7. The integration user ───────────────────────────────────────────────
integration_username=''
integration_id=''
holders_rows="$(query "SELECT AssigneeId, Assignee.Username, Assignee.Profile.Name FROM PermissionSetAssignment WHERE PermissionSetId = '$permset_id' AND Assignee.IsActive = true")"
holder_count="$(jq 'length' <<<"$holders_rows")"
if [[ "$holder_count" != "1" ]]; then
    fail "$PERMSET must be held by exactly 1 active user, is held by $holder_count"
else
    integration_id="$(jq -r '.[0].AssigneeId' <<<"$holders_rows")"
    [[ "$integration_id" =~ ^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || abort "unexpected user Id '$integration_id'"
    integration_username="$(jq -r '.[0].Assignee.Username' <<<"$holders_rows")"
    pass "$PERMSET is held by exactly 1 active user (the integration user)"
    profile="$(jq -r '.[0].Assignee.Profile.Name // empty' <<<"$holders_rows")"
    if [[ "$profile" == "$INTEGRATION_PROFILE" ]]; then
        pass "integration user profile is $INTEGRATION_PROFILE"
    else
        fail "integration user profile is '$profile', expected '$INTEGRATION_PROFILE'"
    fi
    licenses="$(query "SELECT PermissionSetLicense.DeveloperName FROM PermissionSetLicenseAssign WHERE AssigneeId = '$integration_id'")"
    if jq -e --arg psl "$API_INTEGRATION_PSL" 'any(.[]; .PermissionSetLicense.DeveloperName == $psl)' <<<"$licenses" >/dev/null; then
        pass "integration user holds the permission set license $API_INTEGRATION_PSL"
    else
        fail "integration user does not hold the permission set license $API_INTEGRATION_PSL"
    fi
    assigned="$(query "SELECT PermissionSet.Name, PermissionSetGroupId FROM PermissionSetAssignment WHERE AssigneeId = '$integration_id' AND PermissionSet.IsOwnedByProfile = false")"
    assigned_list="$(jq -r '[.[] | if .PermissionSetGroupId then "group:" + .PermissionSetGroupId else .PermissionSet.Name end] | unique | join(",")' <<<"$assigned")"
    if [[ "$assigned_list" == "$PERMSET" ]]; then
        pass "integration user is assigned only $PERMSET"
    else
        fail "integration user must be assigned only $PERMSET, is assigned: ${assigned_list:-nothing}"
    fi
    members="$(query "SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = '$GROUP_NAME' AND Group.Type = 'Regular'")"
    member_list="$(jq -r '[.[].UserOrGroupId] | sort | join(",")' <<<"$members")"
    if [[ "$member_list" == "$integration_id" ]]; then
        pass "group $GROUP_NAME has exactly one member, the integration user"
    elif [[ ",$member_list," == *",$integration_id,"* ]]; then
        fail "group $GROUP_NAME has other members besides the integration user: $member_list"
    else
        fail "integration user is not a member of group $GROUP_NAME (members: ${member_list:-none})"
    fi
fi

# ─── 8. External Client App configuration ──────────────────────────────────
apps="$(query "SELECT Id FROM ExternalClientApplication WHERE DeveloperName = '$ECA_NAME'")"
if [[ "$(jq 'length' <<<"$apps")" != "1" ]]; then
    fail "External Client App $ECA_NAME not found"
else
    app_id="$(jq -r '.[0].Id' <<<"$apps")"
    pass "External Client App $ECA_NAME exists"
    scope_fields="$(sf sobject describe --sobject ExtlClntAppOauthSettings --target-org "$ORG" --json 2>/dev/null || true)"
    [[ "$(jq -r '.status // 1' <<<"$scope_fields" 2>/dev/null)" == "0" ]] || abort "describe of ExtlClntAppOauthSettings failed"
    scope_list="$(jq -r '[.result.fields[] | select(.type == "boolean" and (.name | startswith("OauthScopes"))) | .name] | join(",")' <<<"$scope_fields")"
    [[ -n "$scope_list" ]] || abort "ExtlClntAppOauthSettings has no OauthScopes fields"
    settings="$(query "SELECT $scope_list FROM ExtlClntAppOauthSettings WHERE ExternalClientApplicationId = '$app_id'")"
    if [[ "$(jq 'length' <<<"$settings")" != "1" ]]; then
        fail "$ECA_NAME has $(jq 'length' <<<"$settings") OAuth settings records, expected 1"
    else
        scopes="$(jq -r '[.[0] | to_entries[] | select(.value == true) | .key] | sort | join(",")' <<<"$settings")"
        if [[ "$scopes" == "OauthScopesAPI" ]]; then
            pass "$ECA_NAME OAuth scopes are exactly Api"
        else
            fail "$ECA_NAME OAuth scopes must be exactly Api, are: ${scopes:-none}"
        fi
    fi
    policies="$(query "SELECT Id, IsClientCredentialsFlowEnabled, ClientCredentialsFlowUser, PermittedUsersPolicyType, IpRelaxationPolicyType, IsTokenExchangeFlowEnabled, IsGuestCodeCredFlowEnabled FROM ExtlClntAppOauthPlcyCnfg WHERE ExternalClientApplicationId = '$app_id'")"
    if [[ "$(jq 'length' <<<"$policies")" != "1" ]]; then
        fail "$ECA_NAME has $(jq 'length' <<<"$policies") OAuth policy records, expected 1"
    else
        policy="$(jq -c '.[0]' <<<"$policies")"
        if [[ "$(jq -r '.IsClientCredentialsFlowEnabled' <<<"$policy")" == "true" ]]; then
            pass "$ECA_NAME enables the client credentials flow"
        else
            fail "$ECA_NAME does not enable the client credentials flow"
        fi
        # The platform stores the execution user as a User Id (ClientCredentialsFlowUser).
        run_as="$(jq -r '.ClientCredentialsFlowUser // empty' <<<"$policy")"
        if [[ -n "$integration_id" && "${run_as:0:15}" == "${integration_id:0:15}" ]]; then
            pass "$ECA_NAME client credentials flow runs as the integration user"
        elif [[ -z "$run_as" ]]; then
            fail "$ECA_NAME client credentials flow has no execution user"
        else
            fail "$ECA_NAME client credentials flow must run as the integration user, runs as $run_as"
        fi
        permitted="$(jq -r '.PermittedUsersPolicyType // empty' <<<"$policy")"
        if [[ "$permitted" == "$PERMITTED_USERS" ]]; then
            pass "$ECA_NAME permitted users: admin approved users are pre-authorized"
        else
            fail "$ECA_NAME permitted users is '$permitted', expected '$PERMITTED_USERS'"
        fi
        ip_policy="$(jq -r '.IpRelaxationPolicyType // empty' <<<"$policy")"
        if [[ "$ip_policy" == "$IP_ENFORCED" ]]; then
            pass "$ECA_NAME enforces IP restrictions ($ip_policy)"
        else
            fail "$ECA_NAME IP relaxation is '$ip_policy', expected '$IP_ENFORCED'"
        fi
        if [[ "$(jq -r '.IsTokenExchangeFlowEnabled' <<<"$policy")" == "false" && "$(jq -r '.IsGuestCodeCredFlowEnabled' <<<"$policy")" == "false" ]]; then
            pass "$ECA_NAME enables no token exchange and no guest code-credential flow"
        else
            fail "$ECA_NAME enables token exchange or the guest code-credential flow"
        fi
        preauth="$(query "SELECT Parent.Name, Parent.IsOwnedByProfile, Parent.Profile.Name FROM SetupEntityAccess WHERE SetupEntityId = '$app_id'")"
        preauth_list="$(holders "$preauth" | paste -sd, -)"
        if [[ "$preauth_list" == "permset:$PERMSET" ]]; then
            pass "$ECA_NAME is pre-authorized only through $PERMSET"
        else
            fail "$ECA_NAME must be pre-authorized only through $PERMSET, is through: ${preauth_list:-nothing}"
        fi
    fi
fi

# ─── 8b. Versioned app settings (force-app) ────────────────────────────────
settings_report="$(python3 -I - "$ROOT/force-app/main/default" <<'PY2'
import pathlib, sys
import xml.etree.ElementTree as ET

base = pathlib.Path(sys.argv[1])
ns = "{http://soap.sforce.com/2006/04/metadata}"
glbl = base / "extlClntAppGlobalOauthSets/EntregaYa_Status_glbloauth.ecaGlblOauth-meta.xml"
oauth = base / "extlClntAppOauthSettings/EntregaYa_Status_oauth.ecaOauth-meta.xml"
expected = {
    "externalClientApplication": "EntregaYa_Status",
    "isClientCredentialsFlowEnabled": "true",
    "isDeviceFlowEnabled": "false",
    "isTokenExchangeEnabled": "false",
    "isCodeCredFlowEnabled": "false",
    "isNamedUserJwtEnabled": "false",
    "isConsumerSecretOptional": "false",
    "isPkceRequired": "true",
    "isIntrospectAllTokens": "false",
    "shouldRotateConsumerKey": "false",
    "shouldRotateConsumerSecret": "false",
}
forbidden = ("consumerKey", "consumerSecret", "certificate")
for path in (glbl, oauth):
    if not path.is_file():
        print(f"FAIL {path.name} is missing")
        sys.exit(0)
root = ET.parse(glbl).getroot()
values = {child.tag.replace(ns, ""): (child.text or "").strip() for child in root}
problems = [f"{k}={values.get(k, 'absent')} (expected {v})" for k, v in expected.items() if values.get(k) != v]
problems += [f"{k} is present" for k in forbidden if k in values]
if problems:
    print("FAIL " + glbl.name + ": " + "; ".join(problems))
else:
    print("OK " + glbl.name + ": client credentials only, PKCE and secret required, no rotation, no consumer credentials")
scopes = (ET.parse(oauth).getroot().findtext(ns + "commaSeparatedOauthScopes") or "").strip()
if scopes == "Api":
    print("OK " + oauth.name + ": scope Api only")
else:
    print("FAIL " + oauth.name + ": scopes '" + scopes + "', expected 'Api'")
PY2
)"
while IFS= read -r line; do
    case "$line" in
        OK*) pass "${line#OK }" ;;
        FAIL*) fail "${line#FAIL }" ;;
    esac
done <<<"$settings_report"

# ─── 9. No consumer credentials, tokens or org usernames in the repository ──
# Consumer keys start with 3MVG; access tokens are "<org Id>!<opaque>"; the
# consumer key and secret elements of ExtlClntAppGlobalOauthSettings must never
# carry a value; integration usernames are derived from the org Id at run time.
secret_patterns=(
    '3MVG[0-9A-Za-z._]{20,}'
    '00D[0-9A-Za-z]{12,15}![0-9A-Za-z._]{20,}'
    '<consumer(Key|Secret)>[0-9A-Za-z.]{20,}<'
    '"(consumer_?[Ss]ecret|client_secret|access_token)"[[:space:]]*:[[:space:]]*"[^"$<{]'
    'ENTREGAYA_CLIENT_(ID|SECRET)=[A-Za-z0-9]'
    'entregaya-integration@00[dD][0-9A-Za-z]{12,15}'
)
if [[ -n "$integration_username" ]]; then
    secret_patterns+=("$(sed 's/[][\.*^$+?(){}|/]/\\&/g' <<<"$integration_username")")
fi
grep_args=()
for pattern in "${secret_patterns[@]}"; do grep_args+=(-e "$pattern"); done
tree_hits="$(git grep -I -l -E --untracked "${grep_args[@]}" -- . || true)"
history_hits="$(git log --all -p --no-color | grep -c -E "${grep_args[@]}" || true)"
if [[ -z "$tree_hits" && "${history_hits:-0}" == "0" ]]; then
    pass "no consumer key, secret, token or org-specific integration username in the repository (tree and history)"
else
    [[ -z "$tree_hits" ]] || fail "possible credential or org-specific username in: $(paste -sd, - <<<"$tree_hits")"
    [[ "${history_hits:-0}" == "0" ]] || fail "possible credential or org-specific username in the git history ($history_hits line(s))"
fi

if [[ "$violations" -gt 0 ]]; then
    echo "entregaya-access-check: $violations violation(s) in $ORG"
    exit 1
fi
echo "entregaya-access-check: passed in $ORG"
