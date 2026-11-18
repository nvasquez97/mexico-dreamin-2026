#!/usr/bin/env bash
# Site users of the two seeded customers (odd/tasks/req-005-customer-signup.md,
# S5, AC-005.8). Run it after scripts/setup/customer-owner.sh (the accounts'
# owner needs its role) and after the seed (scripts/seed/seed.apex).
#
# Steps (idempotent: running it again changes nothing):
#   0. source check: scripts/setup/seed-customer-users.apex never sets, resets
#      or prints a password (F5: the owner resets the passwords in Setup);
#   1. runs scripts/setup/seed-customer-users.apex (it refuses an org that is
#      not a sandbox or scratch org): one user per seeded Contact with the
#      profile "RutaCargo Customer" and the permission set RutaCargo_Customer;
#   2. reads the result back and fails unless Ana López and Marta Ruiz each have
#      exactly one active user with the profile "RutaCargo Customer", linked to
#      their seeded Contact on their seeded Account, with RutaCargo_Customer
#      assigned and the username <email>.<18-character org Id in lower case>.
#
# Usage: scripts/setup/seed-customer-users.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APEX="$ROOT/scripts/setup/seed-customer-users.apex"
CUSTOMER_PROFILE='RutaCargo Customer'
CUSTOMER_PERMSET='RutaCargo_Customer'
# email|seeded Account name
CUSTOMERS='ana.lopez@example.com|Abarrotes Acme
marta.ruiz@example.com|Globex Farma'

die() { echo "seed-customer-users: $*" >&2; exit 1; }

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

# ─── 0. No password in the setup Apex ───────────────────────────────────────
[[ -f "$APEX" ]] || die "not found: $APEX"
if grep -inE 'setPassword|resetPassword|Password[[:space:]]*=|createExternalUser|debug\([^)]*password' "$APEX"; then
    die "the setup Apex must never set, reset or print a password"
fi
echo "seed-customer-users: the setup Apex sets, resets and prints no password"

# ─── 1. Users and permission set ───────────────────────────────────────────
out="$(sf apex run --file "$APEX" --target-org "$ORG" --json 2>/dev/null || true)"
if [[ "$(jq -r '.result.compiled // false' <<<"$out" 2>/dev/null)" != "true" \
   || "$(jq -r '.result.success // false' <<<"$out" 2>/dev/null)" != "true" ]]; then
    echo "seed-customer-users: the user setup failed in $ORG" >&2
    jq -r '.result.compileProblem // empty, .result.exceptionMessage // empty, .message // empty' <<<"$out" >&2 2>/dev/null || true
    exit 1
fi
jq -r '.result.logs // ""' <<<"$out" | grep 'USER_DEBUG' | grep -o 'seed-customer-users: .*' || true

# ─── 2. Read back ───────────────────────────────────────────────────────────
query "SELECT Id FROM Organization"
org_id="$(jq -r '.[0].Id' <<<"$ROWS")"
[[ "$org_id" =~ ^00D[A-Za-z0-9]{15}$ ]] || die "unexpected organization Id"
suffix=".$(tr '[:upper:]' '[:lower:]' <<<"$org_id")"
while IFS='|' read -r email account; do
    query "SELECT Id, Username, IsActive, Profile.Name, Contact.Email, Contact.Account.Name FROM User WHERE Contact.Email = '$email' AND Contact.Account.Name = '$account'"; users="$ROWS"
    [[ "$(jq 'length' <<<"$users")" == "1" ]] || die "$email: expected exactly 1 user on the seeded Contact of $account, found $(jq 'length' <<<"$users")"
    jq -e '.[0].IsActive == true' <<<"$users" >/dev/null || die "$email: the user is not active"
    profile="$(jq -r '.[0].Profile.Name // ""' <<<"$users")"
    [[ "$profile" == "$CUSTOMER_PROFILE" ]] || die "$email: the user has the profile '$profile', expected $CUSTOMER_PROFILE"
    username="$(jq -r '.[0].Username' <<<"$users")"
    [[ "$username" == "$email$suffix" ]] || die "$email: the username is '$username', expected $email$suffix"
    user_id="$(jq -r '.[0].Id' <<<"$users")"
    [[ "$user_id" =~ ^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]] || die "unexpected user Id"
    query "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$user_id' AND PermissionSet.Name = '$CUSTOMER_PERMSET'"
    [[ "$(jq 'length' <<<"$ROWS")" == "1" ]] \
        || die "$email: $CUSTOMER_PERMSET is not assigned"
    echo "seed-customer-users: ok $email: one active user $username, profile $CUSTOMER_PROFILE, Contact of $account, $CUSTOMER_PERMSET assigned"
done <<<"$CUSTOMERS"
echo "seed-customer-users: done in $ORG. No password was set or printed: reset it in Setup > Users for a manual test (F5)."
