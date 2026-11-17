#!/usr/bin/env bash
# Org check for AC-F.6 (odd/tasks/foundation.md): field history, sharing models
# and the Apex settings of the deployed foundation schema.
# Read-only: constant SOQL and Tooling queries and a metadata retrieve into a
# temporary folder.
#
# Exits non-zero unless:
#   1. Shipment__c.Status__c, Estimated_Delivery__c and Delivery_Instructions__c
#      have IsFieldHistoryTracked = true (Tooling FieldDefinition, which, unlike
#      Apex, sees every field whatever the running user's field permissions);
#   2. Shipment__c, Account and Recipient_Access_Guard__c have
#      InternalSharingModel and ExternalSharingModel Private (EntityDefinition);
#   2b. Recipient_Access_Guard__c (req-002-003 S1): its four fields exist,
#      Shipment_Key__c is Text(18), External ID, unique and case-sensitive (one
#      guard per shipment, written by upsert on it), and the object has no tab;
#   3. the deployed Apex settings (Settings:Apex, retrieved from the org, not
#      taken from the local file) have enableGaplessTestAutoNum true: tests use
#      an independent Auto Number sequence, so they never consume tracking
#      numbers (BR-05).
# ShipmentSchemaTest proves 1 and 2 from Apex as well; 3 is not readable from Apex.
#
# Usage: scripts/checks/schema-check.sh <org-alias>
set -euo pipefail
export LC_ALL=C

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi
cd "$(dirname "$0")/../.."

TRACKED_FIELDS='Delivery_Instructions__c Estimated_Delivery__c Status__c'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }

# Runs a SOQL query (Tooling API when $2 is "tooling") and prints the records as
# JSON; stops the script on an error.
query() {
    local out
    if [[ "${2:-}" == "tooling" ]]; then
        out="$(sf data query --use-tooling-api --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    else
        out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    fi
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "ERROR: query failed: $1" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 3
    fi
    jq -c '.result.records' <<<"$out"
}

# ─── 1. Field history on the three fields ───────────────────────────────────
history="$(query "SELECT QualifiedApiName, IsFieldHistoryTracked FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Shipment__c' AND QualifiedApiName IN ('Delivery_Instructions__c', 'Estimated_Delivery__c', 'Status__c')" tooling)"
for field in $TRACKED_FIELDS; do
    tracked="$(jq -r --arg f "$field" '.[] | select(.QualifiedApiName == $f) | .IsFieldHistoryTracked' <<<"$history")"
    if [[ "$tracked" == "true" ]]; then
        pass "Shipment__c.$field is history tracked"
    else
        fail "Shipment__c.$field IsFieldHistoryTracked is '${tracked:-missing}', expected true"
    fi
done
count="$(jq '[.[] | select(.IsFieldHistoryTracked == true)] | length' <<<"$history")"
echo "info: $count of 3 fields history tracked"

# ─── 2. Sharing models ──────────────────────────────────────────────────────
entities="$(query "SELECT QualifiedApiName, DurableId, InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('Shipment__c', 'Account', 'Recipient_Access_Guard__c')")"
for object in Shipment__c Account Recipient_Access_Guard__c; do
    for kind in InternalSharingModel ExternalSharingModel; do
        model="$(jq -r --arg o "$object" --arg k "$kind" '.[] | select(.QualifiedApiName == $o) | .[$k]' <<<"$entities")"
        if [[ "$model" == "Private" ]]; then
            pass "$object $kind is Private"
        else
            fail "$object $kind is '${model:-missing}', expected Private"
        fi
    done
done

# ─── 2b. The recipient attempt guard ────────────────────────────────────────
GUARD_FIELDS='Failed_Attempts Locked_Until Shipment Shipment_Key'
guard_entity="$(jq -r '.[] | select(.QualifiedApiName == "Recipient_Access_Guard__c") | .DurableId // empty' <<<"$entities")"
if [[ ! "$guard_entity" =~ ^01I[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
    fail "Recipient_Access_Guard__c not found"
else
    # guard_entity is validated above as a CustomObject Id before it enters any query.
    guard_fields="$(query "SELECT DeveloperName FROM CustomField WHERE TableEnumOrId = '$guard_entity'" tooling \
        | jq -r '[.[].DeveloperName] | sort | join(" ")')"
    if [[ "$guard_fields" == "$GUARD_FIELDS" ]]; then
        pass "Recipient_Access_Guard__c has exactly the fields $GUARD_FIELDS"
    else
        fail "Recipient_Access_Guard__c fields are '$guard_fields', expected '$GUARD_FIELDS'"
    fi
    key="$(query "SELECT Metadata FROM CustomField WHERE TableEnumOrId = '$guard_entity' AND DeveloperName = 'Shipment_Key'" tooling \
        | jq -r '.[0].Metadata // {} | "\(.type) \(.length) externalId=\(.externalId) unique=\(.unique) caseSensitive=\(.caseSensitive)"')"
    if [[ "$key" == "Text 18 externalId=true unique=true caseSensitive=true" ]]; then
        pass "Recipient_Access_Guard__c.Shipment_Key__c is $key"
    else
        fail "Recipient_Access_Guard__c.Shipment_Key__c is '$key', expected Text 18, External ID, unique, case-sensitive"
    fi
fi
guard_tabs="$(query "SELECT Name FROM TabDefinition WHERE SobjectName = 'Recipient_Access_Guard__c'")"
if [[ "$(jq 'length' <<<"$guard_tabs")" -eq 0 ]]; then
    pass "Recipient_Access_Guard__c has no tab"
else
    fail "Recipient_Access_Guard__c has a tab: $(jq -r '[.[].Name] | join(", ")' <<<"$guard_tabs")"
fi

# ─── 3. Apex settings: independent Auto Number sequence in tests ────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
retrieve="$(sf project retrieve start --metadata "Settings:Apex" \
    --target-metadata-dir "$tmp/settings" --unzip --wait 10 --target-org "$ORG" --json 2>/dev/null || true)"
if [[ "$(jq -r '.status // 1' <<<"$retrieve" 2>/dev/null)" != "0" ]]; then
    echo "ERROR: retrieve of Settings:Apex failed" >&2
    exit 3
fi
settings_file="$(find "$tmp/settings" -name 'Apex.settings' | head -1)"
if [[ -z "$settings_file" ]]; then
    fail "the retrieve returned no Apex.settings"
else
    gapless="$(python3 -I - "$settings_file" <<'PY'
import sys
import xml.etree.ElementTree as ET

ns = {"m": "http://soap.sforce.com/2006/04/metadata"}
node = ET.parse(sys.argv[1]).getroot().find("m:enableGaplessTestAutoNum", ns)
print((node.text or "").strip() if node is not None else "missing")
PY
)"
    if [[ "$gapless" == "true" ]]; then
        pass "Settings:Apex enableGaplessTestAutoNum is true (independent Auto Number sequence in tests)"
    else
        fail "Settings:Apex enableGaplessTestAutoNum is '$gapless', expected true"
    fi
fi

if [[ "$violations" -gt 0 ]]; then
    echo "schema-check: $violations violation(s) in $ORG"
    exit 1
fi
echo "schema-check: passed in $ORG"
