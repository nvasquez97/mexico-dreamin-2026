#!/usr/bin/env bash
# Loads the RutaCargo test data into a development org (AC-F.11,
# odd/tasks/foundation.md; design "Test data and definition of done"):
# Abarrotes Acme and Globex Farma, one contact each, and 120 shipments
# RC000001001-RC000001120 (scripts/seed/seed.apex).
#
# - Idempotent: when the data is already loaded it changes nothing and exits 0;
#   a partial state fails without changing anything. It never deletes data.
# - Refuses anything that is not a sandbox or scratch org.
# - Assigns the RutaCargo_Support_Agent permission set to the running user when
#   it is missing (assumption A12): at API 67 the anonymous Apex runs in user
#   mode and the administrator has no field permissions on the custom fields.
# - The clear delivery access codes leave the org once, in the debug output of
#   the load, and are written only to the git-ignored
#   .seed-output/access-codes.csv (owner-only permissions). They are never
#   printed. The debug logs this run creates in the org are deleted at the end.
#
# Run it after the foundation metadata is deployed. Check with
# scripts/seed/verify.sh <org-alias>.
#
# --reissue-codes (AC-F.18): when the 120 seeded shipments exist but
# .seed-output/access-codes.csv is not on this machine (the codes of the first
# load were lost), gives the 120 shipments new codes through
# DeliveryAccessCode.reissueCodes (scripts/seed/reissue.apex) and writes them to
# that file. The previous codes stop working. It loads nothing, refuses to
# overwrite an existing file and refuses unless all 120 seeded shipments exist.
#
# Usage: scripts/seed/seed.sh [--reissue-codes] <org-alias>
set -euo pipefail
umask 077

usage() { echo "Usage: $0 [--reissue-codes] <org-alias>" >&2; exit 2; }
ORG=''
REISSUE=false
for arg in "$@"; do
    case "$arg" in
        --reissue-codes) REISSUE=true ;;
        -*) usage ;;
        *) [[ -z "$ORG" ]] || usage; ORG="$arg" ;;
    esac
done
[[ -n "$ORG" ]] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT/.seed-output"
CODES_FILE="$OUT_DIR/access-codes.csv"
PERMSET='RutaCargo_Support_Agent'
EXPECTED_CODES=120

die() { echo "seed: FAIL: $*" >&2; exit 1; }

# Runs a SOQL query and prints its records as JSON; stops on an error.
soql() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        die "query failed: $1: $(jq -r '.message // "no response"' <<<"$out" 2>/dev/null | tr '\n' ' ')"
    fi
    jq -c '.result.records' <<<"$out"
}

# The debug lines of an anonymous Apex JSON response (stdin), without the echo
# of the Apex source; the platform writes "|" inside a debug message as "&#124;".
debug_lines() {
    jq -r '.result.logs // ""' | grep 'USER_DEBUG' | sed 's/&#124;/|/g' || true
}

# The SEED|<state>|... status line of a response (stdin).
status_from_output() {
    debug_lines | grep -o 'SEED|[a-z-]*|.*' | tail -1 || true
}

# The access codes of a response (stdin), as tracking_number,access_code lines.
codes_from_output() {
    debug_lines | grep -oE 'SEEDCODE[|]RC[0-9]{9}[|][A-Z0-9]{12}' | awk -F'|' '{ print $2 "," $3 }' || true
}

# The reissued access codes of a response (stdin), as tracking_number,access_code
# lines (reissue.apex prints SEEDCODE:<tracking>:<code>).
reissued_codes_from_output() {
    debug_lines | grep -oE 'SEEDCODE:RC[0-9]{9}:[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}' | awk -F: '{ print $2 "," $3 }' || true
}

# Writes tracking_number,access_code lines (stdin) to the codes file, never over
# an existing one.
write_codes_file() {
    local tmp
    mkdir -p "$OUT_DIR"
    tmp="$(mktemp "$OUT_DIR/.access-codes.XXXXXX")"
    { printf 'tracking_number,access_code\n'; cat; } >"$tmp"
    chmod 600 "$tmp"
    if [[ -e "$CODES_FILE" ]] || ! mv -n "$tmp" "$CODES_FILE" || [[ -e "$tmp" ]]; then
        rm -f "$tmp"
        die "${CODES_FILE#"$ROOT/"} appeared while running; it was not overwritten and the new codes were discarded"
    fi
}

if $REISSUE && [[ -e "$CODES_FILE" ]]; then
    die "${CODES_FILE#"$ROOT/"} already exists; --reissue-codes never overwrites it (move it away only if its codes are known to be lost)"
fi

# ─── 1. Development org only, and who is running ───────────────────────────
[[ "$(soql "SELECT IsSandbox FROM Organization" | jq -r '.[0].IsSandbox')" == "true" ]] \
    || die "$ORG is not a sandbox or scratch org; the seed only runs on development orgs"
username="$(sf org display --target-org "$ORG" --json 2>/dev/null | jq -r '.result.username // empty')"
[[ -n "$username" ]] || die "cannot read the username of $ORG"
user_id="$(soql "SELECT Id FROM User WHERE Username = '$username'" | jq -r '.[0].Id // empty')"
[[ -n "$user_id" ]] || die "user $username not found in $ORG"

# ─── 2. Field permissions for the running user (A12, idempotent) ───────────
assigned="$(soql "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$user_id' AND PermissionSet.Name = '$PERMSET'" | jq 'length')"
if [[ "$assigned" == "0" ]]; then
    assign="$(sf org assign permset --name "$PERMSET" --target-org "$ORG" --json 2>/dev/null || true)"
    [[ "$(jq -r '.status // 1' <<<"$assign" 2>/dev/null)" == "0" ]] \
        || die "could not assign $PERMSET to $username: $(jq -r '.message // "no response"' <<<"$assign" 2>/dev/null)"
    echo "seed: assigned permission set $PERMSET to $username (A12)"
else
    echo "seed: $username already has permission set $PERMSET"
fi

# ─── 3. Delete the debug logs this run creates, whatever happens ───────────
logs_before="$(soql "SELECT Id FROM ApexLog WHERE LogUserId = '$user_id'" | jq -r '.[].Id')"
delete_run_logs() {
    local after id deleted=0
    after="$(sf data query --target-org "$ORG" --json --query "SELECT Id FROM ApexLog WHERE LogUserId = '$user_id'" 2>/dev/null \
        | jq -r '.result.records[]?.Id' 2>/dev/null || true)"
    for id in $after; do
        if ! grep -qx "$id" <<<"$logs_before"; then
            if sf data delete record --sobject ApexLog --record-id "$id" --target-org "$ORG" --json >/dev/null 2>&1; then
                deleted=$((deleted + 1))
            else
                echo "seed: WARNING: could not delete debug log $id; delete it in Setup > Debug Logs" >&2
            fi
        fi
    done
    echo "seed: deleted $deleted debug log(s) of this run" >&2
}
trap delete_run_logs EXIT

# ─── 4a. Reissue the codes of the seeded shipments (--reissue-codes) ───────
if $REISSUE; then
    seeded="$(soql "SELECT Id FROM Shipment__c WHERE Account__r.Name IN ('Abarrotes Acme','Globex Farma') AND Name >= 'RC000001001' AND Name <= 'RC000001120'" | jq 'length')"
    [[ "$seeded" == "$EXPECTED_CODES" ]] \
        || die "found $seeded of $EXPECTED_CODES seeded shipments; load the data with $0 $ORG first"
    run="$(sf apex run --file "$ROOT/scripts/seed/reissue.apex" --target-org "$ORG" --json 2>/dev/null || true)"
    if [[ "$(jq -r '.result.success // false' <<<"$run" 2>/dev/null)" != "true" ]]; then
        reason="$(jq -r '.result.exceptionMessage // .result.compileProblem // .message // "no response"' <<<"$run" 2>/dev/null)"
        unset run
        die "reissue refused or failed, no code changed: $reason"
    fi
    reissued="$(debug_lines <<<"$run" | grep -oE 'SEEDREISSUE:reissued:[0-9]+' | tail -1 | cut -d: -f3 || true)"
    codes="$(reissued_codes_from_output <<<"$run")"
    unset run
    written="$(grep -c . <<<"$codes" || true)"
    distinct="$(cut -d, -f1 <<<"$codes" | sort -u | grep -c . || true)"
    if [[ "$reissued" != "$EXPECTED_CODES" || "$written" != "$EXPECTED_CODES" || "$distinct" != "$EXPECTED_CODES" ]]; then
        unset codes
        die "the codes were reissued ($reissued) but $written of $EXPECTED_CODES were read from the output; the file is not written, run $0 --reissue-codes $ORG again"
    fi
    write_codes_file <<<"$codes"
    unset codes
    echo "seed: reissued $written delivery access codes; the previous codes no longer work"
    echo "seed: wrote them to ${CODES_FILE#"$ROOT/"} (git-ignored; never commit or share it)"
    exit 0
fi

# ─── 4. Load ───────────────────────────────────────────────────────────────
run="$(sf apex run --file "$ROOT/scripts/seed/seed.apex" --target-org "$ORG" --json 2>/dev/null || true)"
if [[ "$(jq -r '.result.success // false' <<<"$run" 2>/dev/null)" != "true" ]]; then
    reason="$(jq -r '.result.exceptionMessage // .result.compileProblem // .message // "no response"' <<<"$run" 2>/dev/null)"
    unset run
    die "$reason"
fi
status_line="$(status_from_output <<<"$run")"
codes="$(codes_from_output <<<"$run")"
unset run
[[ -n "$status_line" ]] || { unset codes; die "the load ran but reported no status"; }
echo "seed: $(cut -d'|' -f2- <<<"$status_line" | tr '|' ' ')"

if [[ "$(cut -d'|' -f2 <<<"$status_line")" == "loaded" ]]; then
    written="$(grep -c . <<<"$codes" || true)"
    if [[ "$written" != "$EXPECTED_CODES" ]]; then
        unset codes
        die "the data was loaded but $written of $EXPECTED_CODES access codes were read from the output; they cannot be recovered (only their hashes are stored, D1)"
    fi
    mkdir -p "$OUT_DIR"
    tmp="$(mktemp "$OUT_DIR/.access-codes.XXXXXX")"
    printf 'tracking_number,access_code\n%s\n' "$codes" >"$tmp"
    unset codes
    mv "$tmp" "$CODES_FILE"
    chmod 600 "$CODES_FILE"
    echo "seed: wrote $written delivery access codes to ${CODES_FILE#"$ROOT/"} (git-ignored; never commit or share it)"
else
    unset codes
    if [[ -f "$CODES_FILE" ]]; then
        echo "seed: access codes of the first load stay in ${CODES_FILE#"$ROOT/"}"
    else
        echo "seed: note: ${CODES_FILE#"$ROOT/"} is not on this machine; the codes were shown only once, at the first load (D1). To get new ones (the old codes stop working): $0 --reissue-codes $ORG"
    fi
fi
