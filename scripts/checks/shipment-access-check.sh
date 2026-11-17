#!/usr/bin/env bash
# Org check for AC-F.14 (odd/tasks/foundation.md): who can access Shipment__c.
# Read-only: SOQL queries and a metadata retrieve into a temporary folder.
#
# Exits non-zero unless:
#   1. Shipment__c object permissions come only from the System Administrator
#      profile, the RutaCargo_Support_Agent permission set and the
#      platform-locked Analytics Cloud Integration User profile (assumption A9);
#   2. RutaCargo_Support_Agent grants exactly Read, Create and Edit (no Delete,
#      no View All, no Modify All);
#   3. no profile or permission set other than System Administrator and the
#      locked Analytics Cloud Integration User profile has View All or Modify
#      All on Shipment__c, and that profile has nothing beyond Read and View All;
#   4. the Analytics Cloud Integration User profile has 0 field permissions on
#      Shipment__c and no active user but the platform's own Integration User
#      (username integration@<lower-case 18-character org id>.com);
#   5. no one but System Administrator can read Delivery_Access_Code_Hash__c;
#   6. the deployed sharing rules share every shipment and the customer accounts
#      (Customer_Type__c Individual or Business) with the RutaCargo_Support_Agents
#      group, Read/Write (Edit), with no opportunity or case access.
#
# Usage: scripts/checks/shipment-access-check.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ADMIN_PROFILE='System Administrator'
ANALYTICS_PROFILE='Analytics Cloud Integration User'
AGENT_SET='RutaCargo_Support_Agent'
AGENT_GROUP='RutaCargo_Support_Agents'
HASH_FIELD='Shipment__c.Delivery_Access_Code_Hash__c'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }

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

# ─── 1-3. Object permissions on Shipment__c ─────────────────────────────────
perms="$(query "SELECT Parent.Name, Parent.IsOwnedByProfile, Parent.Profile.Name, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords FROM ObjectPermissions WHERE SobjectType = 'Shipment__c'")"

rows="$(jq -c --arg admin "$ADMIN_PROFILE" --arg analytics "$ANALYTICS_PROFILE" --arg agent "$AGENT_SET" '
  .[] | {
    who: (if .Parent.IsOwnedByProfile then "profile:" + .Parent.Profile.Name else "permset:" + .Parent.Name end),
    r: .PermissionsRead, c: .PermissionsCreate, e: .PermissionsEdit, d: .PermissionsDelete,
    va: .PermissionsViewAllRecords, ma: .PermissionsModifyAllRecords
  } | select(.r or .c or .e or .d or .va or .ma)' <<<"$perms")"

agent_seen=0
while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    who="$(jq -r .who <<<"$row")"
    flags="$(jq -r '"read=\(.r) create=\(.c) edit=\(.e) delete=\(.d) viewAll=\(.va) modifyAll=\(.ma)"' <<<"$row")"
    case "$who" in
        "profile:$ADMIN_PROFILE")
            pass "$who ($flags)" ;;
        "profile:$ANALYTICS_PROFILE")
            if jq -e '.c or .e or .d or .ma' <<<"$row" >/dev/null; then
                fail "$who has more than the platform-locked Read/View All ($flags)"
            else
                pass "$who, accepted platform exception A9 ($flags)"
            fi ;;
        "permset:$AGENT_SET")
            agent_seen=1
            if jq -e '.r and .c and .e and (.d | not) and (.va | not) and (.ma | not)' <<<"$row" >/dev/null; then
                pass "$who grants Read/Create/Edit only ($flags)"
            else
                fail "$who must grant exactly Read, Create and Edit ($flags)"
            fi ;;
        *)
            if jq -e '.va or .ma' <<<"$row" >/dev/null; then
                fail "$who has View All or Modify All on Shipment__c ($flags)"
            fi
            fail "$who grants access to Shipment__c ($flags)" ;;
    esac
done <<<"$rows"
[[ "$agent_seen" == 1 ]] || fail "permission set $AGENT_SET grants no access to Shipment__c"

# ─── 4. The locked Analytics Cloud Integration User profile ────────────────
analytics_fls="$(query "SELECT Field FROM FieldPermissions WHERE SobjectType = 'Shipment__c' AND Parent.Profile.Name = '$ANALYTICS_PROFILE'")"
count="$(jq 'length' <<<"$analytics_fls")"
if [[ "$count" == "0" ]]; then
    pass "$ANALYTICS_PROFILE has 0 field permissions on Shipment__c"
else
    fail "$ANALYTICS_PROFILE has $count field permissions on Shipment__c: $(jq -r '[.[].Field] | join(", ")' <<<"$analytics_fls")"
fi
# The only active user allowed on that profile is the platform's own Integration
# User, whose username is exactly integration@<lower-case 18-character org id>.com.
org_id="$(jq -r '.[0].Id' <<<"$(query "SELECT Id FROM Organization")")"
platform_user="integration@$(tr '[:upper:]' '[:lower:]' <<<"$org_id").com"
analytics_users="$(query "SELECT Username FROM User WHERE IsActive = true AND Profile.Name = '$ANALYTICS_PROFILE'")"
others="$(jq -r --arg allowed "$platform_user" '[.[].Username | select(. != $allowed)] | join(", ")' <<<"$analytics_users")"
if [[ -z "$others" ]]; then
    pass "$ANALYTICS_PROFILE has no active user but the platform Integration User ($platform_user)"
else
    fail "$ANALYTICS_PROFILE has active users other than the platform Integration User: $others"
fi

# ─── 5. Nobody but System Administrator reads the access code hash ─────────
hash_readers="$(query "SELECT Parent.Name, Parent.IsOwnedByProfile, Parent.Profile.Name FROM FieldPermissions WHERE SobjectType = 'Shipment__c' AND Field = '$HASH_FIELD' AND PermissionsRead = true")"
others="$(jq -r --arg admin "$ADMIN_PROFILE" '
  [.[] | (if .Parent.IsOwnedByProfile then "profile:" + .Parent.Profile.Name else "permset:" + .Parent.Name end)
       | select(. != "profile:" + $admin)] | join(", ")' <<<"$hash_readers")"
if [[ -z "$others" ]]; then
    pass "no one but $ADMIN_PROFILE can read $HASH_FIELD"
else
    fail "can read $HASH_FIELD: $others"
fi

# ─── 6. Deployed sharing rules (retrieved, not taken from the local files) ──
group_count="$(jq 'length' <<<"$(query "SELECT Id FROM Group WHERE DeveloperName = '$AGENT_GROUP' AND Type = 'Regular'")")"
[[ "$group_count" == "1" ]] && pass "public group $AGENT_GROUP exists" || fail "public group $AGENT_GROUP not found"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
retrieve="$(sf project retrieve start --metadata "SharingRules:Shipment__c" --metadata "SharingRules:Account" \
    --target-metadata-dir "$tmp/rules" --unzip --wait 10 --target-org "$ORG" --json 2>/dev/null || true)"
if [[ "$(jq -r '.status // 1' <<<"$retrieve" 2>/dev/null)" != "0" ]]; then
    echo "ERROR: retrieve of the sharing rules failed" >&2
    exit 3
fi

rule_report="$(python3 -I - "$tmp/rules" "$AGENT_GROUP" <<'PY'
import pathlib, sys
import xml.etree.ElementTree as ET

root_dir, group = pathlib.Path(sys.argv[1]), sys.argv[2]
ns = {"m": "http://soap.sforce.com/2006/04/metadata"}
expected = {
    "Shipment__c": [("Name", "notEqual", "")],
    "Account": [("Customer_Type__c", "equals", "Individual,Business")],
}

def text(node, path):
    found = node.find(path, ns)
    return (found.text or "").strip() if found is not None else ""

for obj, criteria in expected.items():
    files = list(root_dir.rglob(f"{obj}.sharingRules"))
    if not files:
        print(f"FAIL {obj}: no sharing rules retrieved")
        continue
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
        if obj == "Account":
            for sub in ("opportunityAccessLevel", "caseAccessLevel"):
                if text(rule, "m:accountSettings/m:" + sub) != "None":
                    problems.append(sub + " " + text(rule, "m:accountSettings/m:" + sub))
        matched.append((text(rule, "m:fullName"), problems))
    if not matched:
        print(f"FAIL {obj}: no criteria rule {criteria} sharing to group {group}")
    for name, problems in matched:
        if problems:
            print(f"FAIL {obj}.{name}: " + "; ".join(problems))
        else:
            print(f"OK {obj}.{name}: every matching record shared Read/Write with {group}")
PY
)"
while IFS= read -r line; do
    case "$line" in
        OK*) pass "${line#OK }" ;;
        FAIL*) fail "${line#FAIL }" ;;
    esac
done <<<"$rule_report"

if [[ "$violations" -gt 0 ]]; then
    echo "shipment-access-check: $violations violation(s) in $ORG"
    exit 1
fi
echo "shipment-access-check: passed in $ORG"
