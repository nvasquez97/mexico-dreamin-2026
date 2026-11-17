#!/usr/bin/env bash
# Verifies the RutaCargo test data loaded by scripts/seed/seed.sh
# (AC-F.11 and assumption A10, odd/tasks/foundation.md; design "Test data and
# definition of done", docs/functional-design.md).
#
# Read-only on the data: SOQL through the data API, a read of the local,
# git-ignored .seed-output/access-codes.csv and, when that file exists,
# anonymous Apex that only calls DeliveryAccessCode.verify. It never prints a
# hash or a code, and deletes the debug logs its anonymous Apex creates (they
# echo the codes of the file).
#
# Exits non-zero unless:
#   1. Abarrotes Acme (Business, Low, 500,000) and Globex Farma (Business, High,
#      150,000) exist once each, with exactly one contact each (Ana López,
#      Marta Ruiz);
#   2. each has 60 shipments, with tracking numbers RC000001001-RC000001060
#      (Acme) and RC000001061-RC000001120 (Globex), and no other shipment uses a
#      number of that range;
#   3. each customer has all six statuses and at least 10 Delivered shipments
#      with Proof_Id__c and Delivered_At__c;
#   4. every shipment has Price__c (BR-08 rate), Carrier_Cost__c below the price,
#      Internal_Notes__c, a weight of at most 30 kg, a declared value of at most
#      50,000, and Last_Location__c unless it is Requested;
#   5. the delivery access codes written by seed.sh (when .seed-output/
#      access-codes.csv is on this machine) cover exactly the 120 tracking
#      numbers, one distinct 12-character code each from the code alphabet, and
#      every one of them verifies on its shipment through
#      DeliveryAccessCode.verify (AC-F.18; anonymous Apex in batches of
#      $VERIFY_BATCH codes, one query per code, counts only). When the file is
#      absent this check is skipped (seed.sh --reissue-codes writes a new one);
#   6. every seeded shipment has a Shipment__Share row with RowCause Rule to the
#      RutaCargo_Support_Agents group, and both accounts an AccountShare row with
#      RowCause Rule to that group (the criteria-based sharing rules, A10).
#
# The running user needs read access to the custom fields: seed.sh assigns the
# RutaCargo_Support_Agent permission set to it (assumption A12).
#
# Usage: scripts/seed/verify.sh <org-alias>
set -uo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

VERIFY_BATCH=50

ACME='Abarrotes Acme'
GLOBEX='Globex Farma'
GROUP='RutaCargo_Support_Agents'
NAMES="('$ACME','$GLOBEX')"

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }

# Runs a SOQL query and stores its records as JSON in REPLY. On an error it
# records a failure and stores "null", so the remaining checks still run.
query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        fail "query failed: $(jq -r '.message // "no response"' <<<"$out" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-200)"
        REPLY=null
        return 0
    fi
    REPLY="$(jq -c '.result.records' <<<"$out")"
}

# Prints the length of a JSON array, 0 for null.
count() { jq '. // [] | length' <<<"$1"; }

# Prints the expected tracking numbers RC<9 digits> from $1 to $2, as JSON.
range_json() {
    jq -nc --argjson from "$1" --argjson to "$2" \
        '[range($from; $to + 1) | "RC" + (("000000000" + tostring)[-9:])]'
}

# ─── 0. The org is not production ──────────────────────────────────────────
query "SELECT IsSandbox FROM Organization"; org="$REPLY"
if [[ "$(jq -r '.[0].IsSandbox // false' <<<"$org" 2>/dev/null)" != "true" ]]; then
    echo "ERROR: $ORG is not a sandbox or scratch org; verify.sh only runs on development orgs." >&2
    exit 3
fi

# ─── 1. Accounts and contacts ──────────────────────────────────────────────
query "SELECT Id, Name, Customer_Type__c, Credit_Risk__c, Credit_Limit__c FROM Account WHERE Name IN $NAMES"; accounts="$REPLY"
check_account() {
    local name="$1" risk="$2" limit="$3" rows
    rows="$(jq -c --arg n "$name" '[.[]? | select(.Name == $n)]' <<<"$accounts")"
    if [[ "$(jq 'length' <<<"$rows")" != "1" ]]; then
        fail "account $name: expected exactly 1, found $(jq 'length' <<<"$rows")"
        return
    fi
    if jq -e --arg r "$risk" --argjson l "$limit" \
        '.[0] | .Customer_Type__c == "Business" and .Credit_Risk__c == $r and .Credit_Limit__c == $l' <<<"$rows" >/dev/null; then
        pass "account $name (Business, $risk, $limit)"
    else
        fail "account $name has $(jq -c '.[0] | {Customer_Type__c, Credit_Risk__c, Credit_Limit__c}' <<<"$rows"), expected Business, $risk, $limit"
    fi
}
check_account "$ACME" Low 500000
check_account "$GLOBEX" High 150000

query "SELECT Account.Name, FirstName, LastName, Email FROM Contact WHERE Account.Name IN $NAMES"; contacts="$REPLY"
check_contact() {
    local account="$1" first="$2" last="$3" rows
    rows="$(jq -c --arg a "$account" '[.[]? | select(.Account.Name == $a)]' <<<"$contacts")"
    if [[ "$(jq 'length' <<<"$rows")" != "1" ]]; then
        fail "contacts of $account: expected exactly 1, found $(jq 'length' <<<"$rows")"
    elif jq -e --arg f "$first" --arg l "$last" \
        '.[0] | .FirstName == $f and .LastName == $l and (.Email // "" | endswith("@example.com"))' <<<"$rows" >/dev/null; then
        pass "contact $first $last of $account (fictional example.com email)"
    else
        fail "contact of $account is $(jq -c '.[0] | {FirstName, LastName, Email}' <<<"$rows"), expected $first $last with an example.com email"
    fi
}
check_contact "$ACME" 'Ana' 'López'
check_contact "$GLOBEX" 'Marta' 'Ruiz'

# ─── 2-4. Shipments ────────────────────────────────────────────────────────
query "SELECT Name, Account__r.Name, Status__c, Service_Type__c, Weight_Kg__c, Declared_Value__c, Price__c, Carrier_Cost__c, Internal_Notes__c, Proof_Id__c, Delivered_At__c, Last_Location__c FROM Shipment__c WHERE Account__r.Name IN $NAMES ORDER BY Name"; shipments="$REPLY"
query "SELECT Name, Account__r.Name FROM Shipment__c WHERE Name >= 'RC000001001' AND Name <= 'RC000001120'"; in_range="$REPLY"

check_shipments() {
    local account="$1" from="$2" to="$3" rows expected
    rows="$(jq -c --arg a "$account" '[.[]? | select(.Account__r.Name == $a)]' <<<"$shipments")"
    expected="$(range_json "$from" "$to")"

    if [[ "$(jq 'length' <<<"$rows")" == "60" ]]; then
        pass "$account has 60 shipments"
    else
        fail "$account has $(jq 'length' <<<"$rows") shipments, expected 60"
    fi

    if jq -e --argjson e "$expected" '[.[].Name] | sort == $e' <<<"$rows" >/dev/null; then
        pass "$account tracking numbers are exactly $(jq -r '.[0]' <<<"$expected")-$(jq -r '.[-1]' <<<"$expected")"
    else
        fail "$account tracking numbers are not exactly $(jq -r '.[0]' <<<"$expected")-$(jq -r '.[-1]' <<<"$expected") (missing: $(jq -c --argjson e "$expected" '$e - [.[].Name] | .[0:5]' <<<"$rows"), extra: $(jq -c --argjson e "$expected" '[.[].Name] - $e | .[0:5]' <<<"$rows"))"
    fi

    local missing_statuses
    missing_statuses="$(jq -c '["Requested","Picked up","In transit","Out for delivery","Delivered","Exception"] - [.[].Status__c]' <<<"$rows")"
    if [[ "$missing_statuses" == "[]" ]]; then
        pass "$account has all six statuses ($(jq -c 'group_by(.Status__c) | map({(.[0].Status__c): length}) | add' <<<"$rows"))"
    else
        fail "$account is missing statuses $missing_statuses"
    fi

    local delivered
    delivered="$(jq '[.[] | select(.Status__c == "Delivered" and (.Proof_Id__c // "") != "" and .Delivered_At__c != null)] | length' <<<"$rows")"
    if (( delivered >= 10 )); then
        pass "$account has $delivered Delivered shipments with Proof_Id__c and Delivered_At__c"
    else
        fail "$account has $delivered Delivered shipments with Proof_Id__c and Delivered_At__c, expected at least 10"
    fi

    local bad
    bad="$(jq -c '[.[] | select(.Price__c == null or .Carrier_Cost__c == null or (.Internal_Notes__c // "") == "") | .Name]' <<<"$rows")"
    if [[ "$bad" == "[]" && "$(jq 'length' <<<"$rows")" != "0" ]]; then
        pass "every $account shipment has Price__c, Carrier_Cost__c and Internal_Notes__c"
    else
        fail "$account shipments without Price__c, Carrier_Cost__c or Internal_Notes__c: $bad"
    fi

    # BR-08: Standard 120 + 18/kg, Express 220 + 30/kg, plus 1.5% of the declared value.
    bad="$(jq -c '[.[] | select(
        (.Weight_Kg__c // 0) <= 0 or .Weight_Kg__c > 30
        or (.Declared_Value__c // -1) < 0 or .Declared_Value__c > 50000
        or .Price__c == null or .Carrier_Cost__c == null or .Carrier_Cost__c >= .Price__c
        or ((((if .Service_Type__c == "Express" then 220 + 30 * .Weight_Kg__c else 120 + 18 * .Weight_Kg__c end)
              + 0.015 * .Declared_Value__c) * 100 | round) / 100 - .Price__c | fabs) > 0.005
      ) | .Name]' <<<"$rows")"
    if [[ "$bad" == "[]" && "$(jq 'length' <<<"$rows")" != "0" ]]; then
        pass "every $account price follows BR-08, weight <= 30 kg, declared value <= 50,000, carrier cost below price"
    else
        fail "$account shipments off the BR-08 rate or limits: $bad"
    fi

    bad="$(jq -c '[.[] | select(.Status__c != "Requested" and (.Last_Location__c // "") == "") | .Name]' <<<"$rows")"
    if [[ "$bad" == "[]" && "$(jq 'length' <<<"$rows")" != "0" ]]; then
        pass "every non-Requested $account shipment has Last_Location__c"
    else
        fail "$account shipments past Requested without Last_Location__c: $bad"
    fi
}
check_shipments "$ACME" 1001 1060
check_shipments "$GLOBEX" 1061 1120

others="$(jq -c --arg a "$ACME" --arg g "$GLOBEX" '[.[]? | select(.Account__r.Name != $a and .Account__r.Name != $g) | .Name]' <<<"$in_range")"
if [[ "$others" == "[]" && "$in_range" != "null" ]]; then
    pass "no other shipment uses a tracking number in RC000001001-RC000001120"
else
    fail "shipments of other accounts in RC000001001-RC000001120: $others"
fi

# ─── 5. Delivery access codes from the seed (local file, never printed) ────

# Checks every code of the (well-formed) file with DeliveryAccessCode.verify on
# its shipment, in anonymous Apex batches of $VERIFY_BATCH (verify runs one query
# per code; 100 per transaction). The generated Apex holds codes, so it lives in
# a private directory under the git-ignored .seed-output/ and is removed, and the
# debug logs of these runs are deleted. Prints counts only.
verify_codes_in_org() {
    local username user_id logs_before workdir batch apex out result checked=0 passed=0 failed
    username="$(sf org display --target-org "$ORG" --json 2>/dev/null | jq -r '.result.username // empty')"
    query "SELECT Id FROM User WHERE Username = '$username'"
    user_id="$(jq -r '.[0].Id // empty' <<<"$REPLY" 2>/dev/null)"
    if [[ -z "$user_id" ]]; then
        fail "access codes not checked in the org: cannot identify the running user"
        return
    fi
    query "SELECT Id FROM ApexLog WHERE LogUserId = '$user_id'"
    logs_before="$(jq -r '.[]?.Id' <<<"$REPLY" 2>/dev/null)"
    workdir="$(umask 077; mktemp -d "$ROOT/.seed-output/.verify.XXXXXX")"
    tail -n +2 "$CODES_FILE" | split -l "$VERIFY_BATCH" - "$workdir/batch."
    for batch in "$workdir"/batch.*; do
        apex="$batch.apex"
        {
            echo "Map<String, String> codes = new Map<String, String>{"
            awk -F, '{ printf "%s    '\''%s'\'' => '\''%s'\''", (NR > 1 ? ",\n" : ""), $1, $2 } END { print "" }' "$batch"
            cat <<'APEX'
};
Map<String, Id> idByName = new Map<String, Id>();
for (Shipment__c shipment : [
    SELECT Id, Name FROM Shipment__c
    WHERE Name IN :codes.keySet() AND Account__r.Name IN ('Abarrotes Acme', 'Globex Farma')
    WITH USER_MODE
]) {
    idByName.put(shipment.Name, shipment.Id);
}
Integer passed = 0;
for (String name : codes.keySet()) {
    if (idByName.containsKey(name) && DeliveryAccessCode.verify(idByName.get(name), codes.get(name))) {
        passed++;
    }
}
System.debug('SEEDVERIFY:' + codes.size() + ':' + passed);
APEX
        } >"$apex"
        out="$(sf apex run --file "$apex" --target-org "$ORG" --json 2>/dev/null || true)"
        rm -f "$apex" "$batch"
        result="$(jq -r '.result.logs // ""' <<<"$out" 2>/dev/null | grep 'USER_DEBUG' | grep -oE 'SEEDVERIFY:[0-9]+:[0-9]+' | tail -1 || true)"
        if [[ "$(jq -r '.result.success // false' <<<"$out" 2>/dev/null)" != "true" || -z "$result" ]]; then
            fail "a batch of access codes could not be checked in the org: $(jq -r '.result.exceptionMessage // .result.compileProblem // .message // "no result"' <<<"$out" 2>/dev/null | cut -c1-200)"
            unset out
            continue
        fi
        unset out
        checked=$((checked + $(cut -d: -f2 <<<"$result")))
        passed=$((passed + $(cut -d: -f3 <<<"$result")))
    done
    rmdir "$workdir" 2>/dev/null || rm -rf "$workdir"

    local after id deleted=0
    after="$(sf data query --target-org "$ORG" --json --query "SELECT Id FROM ApexLog WHERE LogUserId = '$user_id'" 2>/dev/null \
        | jq -r '.result.records[]?.Id' 2>/dev/null || true)"
    for id in $after; do
        if ! grep -qx "$id" <<<"$logs_before"; then
            if sf data delete record --sobject ApexLog --record-id "$id" --target-org "$ORG" --json >/dev/null 2>&1; then
                deleted=$((deleted + 1))
            else
                echo "WARNING: could not delete debug log $id (it echoes access codes); delete it in Setup > Debug Logs" >&2
            fi
        fi
    done
    echo "info: deleted $deleted debug log(s) of the access-code check"

    failed=$((checked - passed))
    if [[ "$checked" == "120" && "$passed" == "120" ]]; then
        pass "120 of 120 access codes verify on their shipment through DeliveryAccessCode.verify"
    else
        fail "access codes that verify through DeliveryAccessCode.verify: $passed of 120 (checked $checked, failed $failed)"
    fi
}

CODES_FILE="$ROOT/.seed-output/access-codes.csv"
if [[ ! -f "$CODES_FILE" ]]; then
    echo "skip: $CODES_FILE is not on this machine (written by the run of seed.sh that loads the data, or by seed.sh --reissue-codes)"
else
    expected_all="$(range_json 1001 1120)"
    if awk -F, 'NR == 1 { if ($0 != "tracking_number,access_code") bad = 1; next }
                { n++; if ($1 !~ /^RC[0-9]{9}$/ || $2 !~ /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$/ || NF != 2) bad = 1;
                  if (seen[$2]++) bad = 1 }
                END { exit (bad || n != 120) }' "$CODES_FILE" \
       && jq -e -R -s --argjson e "$expected_all" \
            '[split("\n")[1:][] | select(length > 0) | split(",")[0]] | sort == $e' "$CODES_FILE" >/dev/null; then
        pass "access-codes.csv holds one distinct 12-character code for each of RC000001001-RC000001120"
        verify_codes_in_org
    else
        fail "access-codes.csv does not hold exactly one distinct well-formed code for each of RC000001001-RC000001120; the codes were not checked in the org"
    fi
fi

# ─── 6. Sharing rule shares (A10) ──────────────────────────────────────────
query "SELECT Id FROM Group WHERE DeveloperName = '$GROUP' AND Type = 'Regular'"; group="$REPLY"
group_id="$(jq -r '.[0].Id // empty' <<<"$group" 2>/dev/null)"
if [[ -z "$group_id" ]]; then
    fail "group $GROUP not found"
else
    query "SELECT ParentId, AccessLevel FROM Shipment__Share WHERE RowCause = 'Rule' AND UserOrGroupId = '$group_id' AND ParentId IN (SELECT Id FROM Shipment__c WHERE Account__r.Name IN $NAMES)"; shares="$REPLY"
    shared="$(jq '[.[]? | select(.AccessLevel == "Edit") | .ParentId] | unique | length' <<<"$shares")"
    if [[ "$shared" == "120" ]]; then
        pass "120 of 120 seeded shipments have a Shipment__Share (RowCause Rule, Edit) to $GROUP"
    else
        fail "seeded shipments with a Shipment__Share (RowCause Rule, Edit) to $GROUP: $shared, expected 120"
    fi

    query "SELECT Account.Name, AccountAccessLevel FROM AccountShare WHERE RowCause = 'Rule' AND UserOrGroupId = '$group_id' AND Account.Name IN $NAMES"; account_shares="$REPLY"
    for name in "$ACME" "$GLOBEX"; do
        if jq -e --arg n "$name" 'any(.[]?; .Account.Name == $n and .AccountAccessLevel == "Edit")' <<<"$account_shares" >/dev/null; then
            pass "$name has an AccountShare (RowCause Rule, Edit) to $GROUP"
        else
            fail "$name has no AccountShare (RowCause Rule, Edit) to $GROUP"
        fi
    done
fi

echo
if (( violations > 0 )); then
    echo "verify: $violations check(s) failed in $ORG"
    exit 1
fi
echo "verify: all checks passed in $ORG"
