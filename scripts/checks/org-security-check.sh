#!/usr/bin/env bash
# Org check for AC-H3.1 (odd/tasks/hardening-1.md, SEC-003, policy X10):
# multi-factor authentication is required for every direct UI login.
# Read-only: one metadata retrieve into a temporary folder outside the project
# and constant SOQL queries. It deploys nothing and writes nothing to the repo.
#
# Exits non-zero unless:
#   1. source: force-app/main/default/settings/Security.settings-meta.xml holds
#      ONLY <sessionSettings><enableMFADirectUILoginOptIn>true</...></...>.
#      Any other element fails: a copied full Security settings file carries
#      <networkAccess/>, which would wipe the org's login IP ranges on deploy;
#   2. org: the Security settings retrieved from the org (Settings:Security)
#      show sessionSettings.enableMFADirectUILoginOptIn = true;
#   3. org: the Health Check row "MFA Enabled" (Tooling
#      SecurityHealthCheckRisks, group Identity) has RiskType MEETS_STANDARD:
#      it is the row that follows enableMFADirectUILoginOptIn;
#   4. org: no customer profile or permission set grants "Multi-Factor
#      Authentication for User Interface Logins" (PermissionsForceTwoFactor).
#      The org setting covers direct logins of internal users; MFA for
#      Experience Cloud customers is a separate opt-in through that user
#      permission (hardening-1 H2), and granting it would force customers into
#      MFA at the site login. Checked: the profile "RutaCargo Customer" and the
#      permission set RutaCargo_Customer (both must exist and not grant it),
#      every profile whose UserType is not Standard, and every permission set
#      assigned to an active user whose UserType is not Standard.
# Information only (never fails): the Health Check row "Require MFA for all
# direct UI logins". It reports Salesforce-side MFA enforcement, which no
# SecuritySettings field controls: it stayed "Not Enforced" for 16 minutes
# after the setting was deployed (hardening-1 AC-H3.1, T3 evidence). Owner item.
#
# Exit codes: 0 passed, 1 violations, 2 usage, 3 a query or the retrieve failed.
# Usage: scripts/checks/org-security-check.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_FILE="$REPO_ROOT/force-app/main/default/settings/Security.settings-meta.xml"
MFA_ROW='MFA Enabled'
MFA_INFO_ROW='Require MFA for all direct UI logins'
CUSTOMER_PROFILE='RutaCargo Customer'
CUSTOMER_PERMSET='RutaCargo_Customer'

violations=0
fail() { echo "FAIL: $*"; violations=$((violations + 1)); }
pass() { echo "ok:   $*"; }
info() { echo "info: $*"; }
abort() { echo "ERROR: $*" >&2; exit 3; }

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/org-security-check.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

# Runs a SOQL query (add --use-tooling-api as $2) and prints the records as
# JSON; stops the script with exit 3 on any error.
query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" ${2:-} 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        abort "query failed: $1"
    fi
    jq -c '.result.records' <<<"$out"
}

# ─── 1. Source file: only enableMFADirectUILoginOptIn = true ─────────────────
if [[ ! -f "$SOURCE_FILE" ]]; then
    fail "source: ${SOURCE_FILE#"$REPO_ROOT"/} does not exist"
else
    source_result="$(python3 -I - "$SOURCE_FILE" <<'PY'
import sys
import xml.etree.ElementTree as ET
NS = '{http://soap.sforce.com/2006/04/metadata}'
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception as error:  # unreadable or malformed XML
    print(f'not well-formed XML ({error})')
    sys.exit(0)
if root.tag != NS + 'SecuritySettings':
    print(f'root element is {root.tag}, expected SecuritySettings')
    sys.exit(0)
children = [child.tag.replace(NS, '') for child in root]
if children != ['sessionSettings']:
    print(f'top-level elements are {children}, expected only [sessionSettings]')
    sys.exit(0)
session = [child.tag.replace(NS, '') for child in root[0]]
if session != ['enableMFADirectUILoginOptIn']:
    print(f'sessionSettings holds {session}, expected only [enableMFADirectUILoginOptIn]')
    sys.exit(0)
value = (root[0][0].text or '').strip()
if value != 'true':
    print(f'enableMFADirectUILoginOptIn is "{value}", expected "true"')
    sys.exit(0)
print('OK')
PY
)" || abort "could not run the source check (python3)"
    if [[ "$source_result" == "OK" ]]; then
        pass "source: Security.settings-meta.xml holds only enableMFADirectUILoginOptIn = true"
    else
        fail "source: Security.settings-meta.xml: $source_result"
    fi
fi

# ─── 2. Org: retrieved Security settings show the setting true ──────────────
# Metadata format into a temporary folder: the project source is not touched.
retrieve_out="$(cd "$REPO_ROOT" && sf project retrieve start --metadata Settings:Security \
    --target-org "$ORG" --target-metadata-dir "$WORK_DIR/retrieve" --unzip --json 2>/dev/null || true)"
if [[ "$(jq -r '.status // 1' <<<"$retrieve_out" 2>/dev/null)" != "0" \
    || "$(jq -r '.result.status // empty' <<<"$retrieve_out" 2>/dev/null)" != "Succeeded" ]]; then
    jq -r '.message // empty' <<<"$retrieve_out" >&2 2>/dev/null || true
    abort "retrieve of Settings:Security from $ORG failed"
fi
retrieved_file="$(find "$WORK_DIR/retrieve" -type f -name 'Security.settings' | head -n 1)"
[[ -n "$retrieved_file" ]] || abort "retrieve succeeded but returned no Security.settings file"
org_value="$(python3 -I - "$retrieved_file" <<'PY'
import sys
import xml.etree.ElementTree as ET
NS = '{http://soap.sforce.com/2006/04/metadata}'
values = [(node.text or '').strip() for node in
          ET.parse(sys.argv[1]).getroot().findall(f'{NS}sessionSettings/{NS}enableMFADirectUILoginOptIn')]
print(values[0] if len(values) == 1 else f'{len(values)} values')
PY
)" || abort "could not parse the retrieved Security.settings"
if [[ "$org_value" == "true" ]]; then
    pass "org: retrieved sessionSettings.enableMFADirectUILoginOptIn = true"
else
    fail "org: retrieved sessionSettings.enableMFADirectUILoginOptIn = $org_value, expected true"
fi

# ─── 3. Org: Health Check row meets the standard ────────────────────────────
health="$(query "SELECT Setting, OrgValue, StandardValue, RiskType FROM SecurityHealthCheckRisks WHERE SettingGroup = 'Identity' AND Setting IN ('$MFA_ROW', '$MFA_INFO_ROW')" --use-tooling-api)"
mfa_rows="$(jq --arg s "$MFA_ROW" '[.[] | select(.Setting == $s)]' <<<"$health")"
if [[ "$(jq 'length' <<<"$mfa_rows")" -ne 1 ]]; then
    fail "Health Check: expected one row \"$MFA_ROW\", found $(jq 'length' <<<"$mfa_rows")"
else
    risk="$(jq -r '.[0].RiskType' <<<"$mfa_rows")"
    detail="$(jq -r '.[0] | "OrgValue=\(.OrgValue), StandardValue=\(.StandardValue), RiskType=\(.RiskType)"' <<<"$mfa_rows")"
    if [[ "$risk" == "MEETS_STANDARD" ]]; then
        pass "Health Check \"$MFA_ROW\": $detail"
    else
        fail "Health Check \"$MFA_ROW\": $detail, expected RiskType=MEETS_STANDARD"
    fi
fi
info_rows="$(jq -r --arg s "$MFA_INFO_ROW" '.[] | select(.Setting == $s) | "OrgValue=\(.OrgValue), StandardValue=\(.StandardValue), RiskType=\(.RiskType)"' <<<"$health")"
info "Health Check \"$MFA_INFO_ROW\": ${info_rows:-no row} (Salesforce-side enforcement, owner item)"

# ─── 4. Org: customers are not opted into MFA by permission ─────────────────
customer_sets="$(query "SELECT Name, IsOwnedByProfile, Profile.Name, PermissionsForceTwoFactor FROM PermissionSet WHERE Profile.Name = '$CUSTOMER_PROFILE' OR Name = '$CUSTOMER_PERMSET'")"
for label in "profile:$CUSTOMER_PROFILE" "permission set:$CUSTOMER_PERMSET"; do
    kind="${label%%:*}"
    name="${label#*:}"
    if [[ "$kind" == "profile" ]]; then
        row="$(jq -c --arg n "$name" '[.[] | select(.IsOwnedByProfile == true and .Profile.Name == $n)]' <<<"$customer_sets")"
    else
        row="$(jq -c --arg n "$name" '[.[] | select(.IsOwnedByProfile == false and .Name == $n)]' <<<"$customer_sets")"
    fi
    if [[ "$(jq 'length' <<<"$row")" -ne 1 ]]; then
        fail "$kind \"$name\" not found"
    elif [[ "$(jq -r '.[0].PermissionsForceTwoFactor' <<<"$row")" == "false" ]]; then
        pass "$kind \"$name\" does not grant Multi-Factor Authentication for User Interface Logins"
    else
        fail "$kind \"$name\" grants Multi-Factor Authentication for User Interface Logins: customers would be forced into MFA at the site login"
    fi
done
external_profiles="$(query "SELECT Profile.Name, Profile.UserType FROM PermissionSet WHERE IsOwnedByProfile = true AND Profile.UserType != 'Standard' AND PermissionsForceTwoFactor = true")"
if [[ "$(jq 'length' <<<"$external_profiles")" -eq 0 ]]; then
    pass "no profile with a UserType other than Standard grants Multi-Factor Authentication for User Interface Logins"
else
    fail "profiles with a UserType other than Standard grant Multi-Factor Authentication for User Interface Logins: $(jq -r '[.[] | "\(.Profile.Name) (\(.Profile.UserType))"] | join(", ")' <<<"$external_profiles")"
fi
external_assignments="$(query "SELECT Assignee.Username, Assignee.UserType, PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.IsActive = true AND Assignee.UserType != 'Standard' AND PermissionSet.PermissionsForceTwoFactor = true")"
if [[ "$(jq 'length' <<<"$external_assignments")" -eq 0 ]]; then
    pass "no active user with a UserType other than Standard holds Multi-Factor Authentication for User Interface Logins"
else
    fail "active users with a UserType other than Standard hold Multi-Factor Authentication for User Interface Logins: $(jq -r '[.[] | "\(.PermissionSet.Name) -> \(.Assignee.UserType)"] | unique | join(", ")' <<<"$external_assignments")"
fi

if [[ "$violations" -gt 0 ]]; then
    echo "org-security-check: $violations violation(s) in $ORG"
    exit 1
fi
echo "org-security-check: passed in $ORG"
exit 0
