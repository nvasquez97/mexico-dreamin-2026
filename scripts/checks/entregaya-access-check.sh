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
# apps (TabSet), connected apps and the other setup entities: exactly the class
# and the custom permission are allowed.
entities="$(query "SELECT SetupEntityType, SetupEntityId FROM SetupEntityAccess WHERE ParentId = '$permset_id'")"
expected_entities="$(printf '%s\n' "ApexClass:$class_id" "CustomPermission:$cp_id" | sort | paste -sd, -)"
actual_entities="$(jq -r '[.[] | "\(.SetupEntityType):\(.SetupEntityId)"] | sort | join(",")' <<<"$entities")"
if [[ "$actual_entities" == "$expected_entities" ]]; then
    pass "$PERMSET grants only ApexClass $CLASS_NAME and CustomPermission $CUSTOM_PERMISSION (setup entities)"
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

if [[ "$violations" -gt 0 ]]; then
    echo "entregaya-access-check: $violations violation(s) in $ORG"
    exit 1
fi
echo "entregaya-access-check: passed in $ORG"
