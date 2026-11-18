#!/usr/bin/env bash
# Live check for AC-003.5 (odd/tasks/req-002-003-recipient-delivery.md, S2's
# history paragraph, assumption E8): a reschedule writes field history that a
# support agent sees on the Shipment__c record page.
#
# Writes data: each run reschedules ONE seeded shipment once through
# RecipientDeliveryController.rescheduleDelivery (anonymous Apex, as the
# running admin; the guest attribution is not provable here, E8), so it
# consumes one of that shipment's 2 reschedules (accepted).
#
# The access code comes from the local, git-ignored
# .seed-output/access-codes.csv and is never printed: it is written only into
# a temporary anonymous Apex file in a private directory under .seed-output/
# (removed afterwards), the CLI output that echoes it is never shown, any text
# shown from that output has the code replaced, and the debug logs the run
# creates (they echo the Apex source) are deleted. The cleanup is installed as
# an EXIT trap before the first `sf apex run`.
#
# Exits non-zero unless:
#   1. the org is a sandbox or scratch org;
#   2. the Shipment__c page layout in force-app carries the field history
#      related list (RelatedEntityHistoryList), and so does the layout in the
#      org (Tooling API Layout.Metadata);
#   3. a seeded shipment (RC000001001-RC000001120) qualifies: Picked up or In
#      transit, Reschedule_Count__c below 2, an open window (today + 1 in
#      America/Mexico_City <= Original_Estimated_Delivery__c + 7), a date in
#      that window other than its current estimate, and a code in the file;
#      when none qualifies it says so and exits non-zero;
#   4. rescheduleDelivery answers SUCCESS with the new date;
#   5. Shipment__c then holds the new date, the new instructions and
#      Reschedule_Count__c + 1;
#   6. Shipment__History has exactly one NEW row for Estimated_Delivery__c and
#      one for Delivery_Instructions__c on that shipment, each with a
#      CreatedDate and CreatedById equal to the running user; the date row
#      carries the new date (Delivery_Instructions__c is a Long Text Area,
#      whose history rows record the change, its time and author, without the
#      old and new values).
#
# Usage: scripts/checks/reschedule-history-check.sh <org-alias>
set -uo pipefail
export LC_ALL=C
# A debug-level sf CLI log could record the anonymous Apex body, which holds
# the access code: every sf call here runs at the CLI's default log level.
unset SF_LOG_LEVEL SFDX_LOG_LEVEL

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODES_FILE="$ROOT/.seed-output/access-codes.csv"
LAYOUT_FILE="$ROOT/force-app/main/default/layouts/Shipment__c-Shipment Layout.layout-meta.xml"
HISTORY_LIST='RelatedEntityHistoryList'
FIELDS="('Estimated_Delivery__c','Delivery_Instructions__c')"
SEEDED="Name >= 'RC000001001' AND Name <= 'RC000001120' AND Account__r.Name IN ('Abarrotes Acme','Globex Farma')"

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
finish() {
    echo
    if (( violations > 0 )); then
        echo "reschedule-history-check: $violations check(s) failed in $ORG"
        exit 1
    fi
    echo "reschedule-history-check: all checks passed in $ORG"
    exit 0
}

# Runs a SOQL query (data API, or Tooling with a second argument "tooling") and
# stores its records as JSON in REPLY; on an error REPLY is null.
query() {
    local out flags=()
    [[ "${2:-}" == "tooling" ]] && flags=(--use-tooling-api)
    out="$(sf data query ${flags[@]+"${flags[@]}"} --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        fail "query failed: $(jq -r '.message // "no response"' <<<"$out" 2>/dev/null | tr '\n' ' ' | cut -c1-200)"
        REPLY=null
        return 1
    fi
    REPLY="$(jq -c '.result.records' <<<"$out")"
}

# ─── 1. Development org only ────────────────────────────────────────────────
query "SELECT IsSandbox FROM Organization" || finish
if [[ "$(jq -r '.[0].IsSandbox // false' <<<"$REPLY")" != "true" ]]; then
    echo "ERROR: $ORG is not a sandbox or scratch org; this check writes data and only runs on development orgs." >&2
    exit 3
fi

# ─── 2. The history related list on the page layout ────────────────────────
if [[ -f "$LAYOUT_FILE" ]] && grep -qE "<relatedList>$HISTORY_LIST</relatedList>" "$LAYOUT_FILE"; then
    pass "force-app Shipment__c-Shipment Layout carries the field history related list ($HISTORY_LIST)"
else
    fail "force-app Shipment__c-Shipment Layout does not carry the field history related list ($HISTORY_LIST)"
fi
if query "SELECT Id FROM CustomObject WHERE DeveloperName = 'Shipment' AND NamespacePrefix = null" tooling; then
    object_id="$(jq -r '.[0].Id // empty' <<<"$REPLY")"
    if [[ -z "$object_id" ]]; then
        fail "Shipment__c not found in the org (Tooling CustomObject)"
    elif query "SELECT Metadata FROM Layout WHERE TableEnumOrId = '$object_id' AND Name = 'Shipment Layout'" tooling; then
        if jq -e --arg h "$HISTORY_LIST" 'length == 1 and any(.[0].Metadata.relatedLists[]?; .relatedList == $h)' <<<"$REPLY" >/dev/null; then
            pass "the org's Shipment__c-Shipment Layout carries the field history related list"
        else
            fail "the org's Shipment__c-Shipment Layout does not carry the field history related list (deploy force-app/main/default/layouts)"
        fi
    fi
fi

# ─── 3. A shipment that can be rescheduled, with its code ──────────────────
if [[ ! -f "$CODES_FILE" ]]; then
    fail "$CODES_FILE is not on this machine (written by scripts/seed/seed.sh or seed.sh --reissue-codes); no shipment can be verified"
    finish
fi
read -r tomorrow earliest_original < <(python3 -I - <<'PY'
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
tomorrow = datetime.now(ZoneInfo("America/Mexico_City")).date() + timedelta(days=1)
print(tomorrow.isoformat(), (tomorrow - timedelta(days=7)).isoformat())
PY
)
query "SELECT Id, Name, Status__c, Reschedule_Count__c, Original_Estimated_Delivery__c, Estimated_Delivery__c, Delivery_Instructions__c FROM Shipment__c WHERE $SEEDED AND Status__c IN ('Picked up','In transit') AND (Reschedule_Count__c = null OR Reschedule_Count__c < 2) AND Original_Estimated_Delivery__c >= $earliest_original ORDER BY Name" || finish
candidates="$REPLY"

shipment=''
new_date=''
while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    name="$(jq -r '.Name' <<<"$row")"
    grep -q "^$name," "$CODES_FILE" || continue
    new_date="$(python3 -I - "$tomorrow" "$(jq -r '.Original_Estimated_Delivery__c' <<<"$row")" "$(jq -r '.Estimated_Delivery__c // ""' <<<"$row")" <<'PY'
import sys
from datetime import date, timedelta
start = date.fromisoformat(sys.argv[1])
end = date.fromisoformat(sys.argv[2]) + timedelta(days=7)
current = sys.argv[3]
day = start
while day <= end:
    if day.isoformat() != current:
        print(day.isoformat())
        break
    day += timedelta(days=1)
PY
)"
    if [[ -n "$new_date" ]]; then
        shipment="$row"
        break
    fi
done < <(jq -c '.[]' <<<"$candidates")

if [[ -z "$shipment" ]]; then
    fail "no seeded shipment qualifies: Picked up or In transit, Reschedule_Count__c < 2, today+1 ($tomorrow, America/Mexico_City) <= Original_Estimated_Delivery__c + 7, a code in the file; reseed (scripts/seed/seed.sh) to get fresh shipments"
    finish
fi
shipment_id="$(jq -r '.Id' <<<"$shipment")"
name="$(jq -r '.Name' <<<"$shipment")"
count_before="$(jq -r '.Reschedule_Count__c // 0 | floor' <<<"$shipment")"
instructions="History check $(date -u +%Y-%m-%dT%H:%M:%SZ)"
pass "picked $name ($(jq -r '.Status__c' <<<"$shipment"), Reschedule_Count__c $count_before, original estimate $(jq -r '.Original_Estimated_Delivery__c' <<<"$shipment"), current $(jq -r '.Estimated_Delivery__c // "none"' <<<"$shipment")); new date $new_date"

username="$(sf org display --target-org "$ORG" --json 2>/dev/null | jq -r '.result.username // empty')"
query "SELECT Id FROM User WHERE Username = '$username'" || finish
user_id="$(jq -r '.[0].Id // empty' <<<"$REPLY")"
if [[ -z "$user_id" ]]; then
    fail "cannot identify the running user"
    finish
fi

query "SELECT Id FROM Shipment__History WHERE ParentId = '$shipment_id' AND Field IN $FIELDS" || finish
history_before="$(jq -c '[.[].Id]' <<<"$REPLY")"
query "SELECT Id FROM ApexLog WHERE LogUserId = '$user_id'" || finish
LOGS_BEFORE="$(jq -r '.[]?.Id' <<<"$REPLY")"

# ─── 4. The reschedule, from anonymous Apex (code never printed) ───────────
WORKDIR=''
CLEANED=false
clean_up() {
    $CLEANED && return 0
    CLEANED=true
    [[ -n "$WORKDIR" ]] && rm -rf "$WORKDIR"
    local after id deleted=0
    after="$(sf data query --target-org "$ORG" --json --query "SELECT Id FROM ApexLog WHERE LogUserId = '$user_id'" 2>/dev/null \
        | jq -r '.result.records[]?.Id' 2>/dev/null || true)"
    for id in $after; do
        if ! grep -qx "$id" <<<"$LOGS_BEFORE"; then
            if sf data delete record --sobject ApexLog --record-id "$id" --target-org "$ORG" --json >/dev/null 2>&1; then
                deleted=$((deleted + 1))
            else
                echo "WARNING: could not delete debug log $id (it echoes an access code); delete it in Setup > Debug Logs" >&2
            fi
        fi
    done
    echo "info: deleted $deleted debug log(s) of the reschedule"
}
trap clean_up EXIT
trap 'exit 130' INT TERM HUP

WORKDIR="$(umask 077; mktemp -d "$ROOT/.seed-output/.history-check.XXXXXX")"
code="$(awk -F, -v n="$name" '$1 == n { print $2; exit }' "$CODES_FILE")"
apex="$WORKDIR/reschedule.apex"
{
    printf "RecipientDeliveryController.DeliveryResponse r = RecipientDeliveryController.rescheduleDelivery('%s', [SELECT Destination_Postal_Code__c FROM Shipment__c WHERE Id = '%s' WITH USER_MODE].Destination_Postal_Code__c, '%s', '%s', '%s');\n" \
        "$name" "$shipment_id" "$code" "$new_date" "$instructions"
    echo "System.debug('RHCHECK:' + r.outcome + ':' + (r.details == null ? '' : r.details.estimatedDelivery));"
} >"$apex"
out="$(sf apex run --file "$apex" --target-org "$ORG" --json 2>/dev/null || true)"
rm -f "$apex"
marker="$(jq -r '.result.logs // ""' <<<"$out" 2>/dev/null | grep 'USER_DEBUG' | grep -oE 'RHCHECK:[A-Z_]+:[0-9-]*' | tail -1 || true)"
problem="$(jq -r '.result.exceptionMessage // .result.compileProblem // .message // ""' <<<"$out" 2>/dev/null || true)"
# The code is replaced in bash, never passed as a command argument (another
# local user could read it with ps while that command runs).
[[ -n "$code" ]] && problem="${problem//"$code"/<code>}"
problem="$(cut -c1-200 <<<"$problem")"
unset out code
clean_up

if [[ "$marker" == "RHCHECK:SUCCESS:$new_date" ]]; then
    pass "rescheduleDelivery answered SUCCESS with the new date $new_date"
else
    fail "rescheduleDelivery did not answer SUCCESS with $new_date (got '${marker:-no result}'${problem:+; $problem})"
    finish
fi

# ─── 5. The saved shipment ─────────────────────────────────────────────────
query "SELECT Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c FROM Shipment__c WHERE Id = '$shipment_id'" || finish
if jq -e --arg d "$new_date" --arg i "$instructions" --argjson c "$((count_before + 1))" \
    '.[0] | .Estimated_Delivery__c == $d and .Delivery_Instructions__c == $i and .Reschedule_Count__c == $c' <<<"$REPLY" >/dev/null; then
    pass "$name now has Estimated_Delivery__c $new_date, the new instructions and Reschedule_Count__c $((count_before + 1))"
else
    fail "$name holds $(jq -c '.[0]' <<<"$REPLY"), expected $new_date, '$instructions', $((count_before + 1))"
fi

# ─── 6. The new history rows ───────────────────────────────────────────────
query "SELECT Id, Field, OldValue, NewValue, CreatedDate, CreatedById FROM Shipment__History WHERE ParentId = '$shipment_id' AND Field IN $FIELDS ORDER BY CreatedDate" || finish
new_rows="$(jq -c --argjson before "$history_before" '[.[] | select(.Id as $id | $before | index($id) | not)]' <<<"$REPLY")"
# check_history <field> [expected NewValue]: no value is checked when none is
# given (a Long Text Area's history rows carry no values).
check_history() {
    local field="$1" expected="${2:-}" rows
    rows="$(jq -c --arg f "$field" '[.[] | select(.Field == $f)]' <<<"$new_rows")"
    if [[ "$(jq 'length' <<<"$rows")" != "1" ]]; then
        fail "Shipment__History: $(jq 'length' <<<"$rows") new row(s) for $field on $name, expected 1 (is field history on for $field?)"
        return
    fi
    if jq -e --arg u "$user_id" --arg v "$expected" \
        '.[0] | (.CreatedDate // "") != "" and .CreatedById == $u and ($v == "" or ((.NewValue // "") | tostring | startswith($v)))' <<<"$rows" >/dev/null; then
        pass "Shipment__History: a new $field row on $name, NewValue $(jq -c '.[0].NewValue' <<<"$rows"), CreatedDate $(jq -r '.[0].CreatedDate' <<<"$rows"), CreatedById $user_id (the running admin)"
    else
        fail "Shipment__History row for $field is $(jq -c '.[0] | {NewValue, CreatedDate, CreatedById}' <<<"$rows"), expected${expected:+ NewValue $expected,} a CreatedDate and CreatedById $user_id"
    fi
}
check_history Estimated_Delivery__c "$new_date"
check_history Delivery_Instructions__c

finish
