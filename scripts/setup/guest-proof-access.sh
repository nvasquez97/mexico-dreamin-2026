#!/usr/bin/env bash
# Prepares the proof of delivery download for the RutaCargo site guest
# (req-002-003 S3, E11; AC-002.6). Idempotent: running it again changes nothing.
#
#   1. The Named Credential EntregaYa_API (password authentication, named
#      principal) must exist before force-app is deployed: the platform refuses
#      to CREATE a password-authenticated Named Credential whose metadata has no
#      password, and the repository never holds one. When it is missing, this
#      script creates it from force-app's file plus the non-secret placeholder
#      password "not-set-enter-the-key-in-setup", in a temporary folder that is
#      deleted afterwards. An existing credential is never touched, so the key
#      the owner entered in Setup is kept. force-app then updates it without a
#      password.
#   2. The guest holds no permission set besides its profile's own: the proof
#      callout needs none. A RutaCargo_Guest_Proof_Download assignment (the
#      discarded External Credential design) is removed; the assignment is data.
#
# Run it after the site exists and before force-app is deployed
# (scripts/setup/DEPLOY-ORDER.md); running it later is harmless.
#
# Usage: scripts/setup/guest-proof-access.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMED_CREDENTIAL='EntregaYa_API'
NC_FILE="$ROOT/force-app/main/default/namedCredentials/$NAMED_CREDENTIAL.namedCredential-meta.xml"
PLACEHOLDER_PASSWORD='not-set-enter-the-key-in-setup'
OLD_PERMISSION_SET='RutaCargo_Guest_Proof_Download'

# Runs a SOQL query and prints the records as JSON; stops the script on an error.
query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "guest-proof-access: query failed: $1" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 1
    fi
    jq -c '.result.records' <<<"$out"
}

# ─── 1. The Named Credential exists ─────────────────────────────────────────
existing_nc="$(query "SELECT Id FROM NamedCredential WHERE DeveloperName = '$NAMED_CREDENTIAL'" | jq 'length')"
if [[ "$existing_nc" -gt 0 ]]; then
    echo "guest-proof-access: $NAMED_CREDENTIAL exists; left unchanged (its password is the owner's)"
else
    if [[ ! -f "$NC_FILE" ]]; then
        echo "guest-proof-access: $NC_FILE not found" >&2
        exit 1
    fi
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/force-app/main/default/namedCredentials"
    printf '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"67.0"}\n' \
        >"$work/sfdx-project.json"
    sed "s#<namedCredentialType>Legacy</namedCredentialType>#<namedCredentialType>Legacy</namedCredentialType>\\
    <password>$PLACEHOLDER_PASSWORD</password>#" "$NC_FILE" \
        >"$work/force-app/main/default/namedCredentials/$NAMED_CREDENTIAL.namedCredential-meta.xml"
    out="$(cd "$work" && sf project deploy start --source-dir force-app/main/default/namedCredentials \
        --ignore-conflicts --target-org "$ORG" --wait 10 --json 2>/dev/null || true)"
    if [[ "$(jq -r '.result.status // empty' <<<"$out" 2>/dev/null)" != "Succeeded" ]]; then
        echo "guest-proof-access: could not create $NAMED_CREDENTIAL in $ORG" >&2
        jq -r '.message // empty, (.result.details.componentFailures // [] | if type == "array" then .[] else . end | .problem)' \
            <<<"$out" >&2 2>/dev/null || true
        exit 1
    fi
    echo "guest-proof-access: created $NAMED_CREDENTIAL with the placeholder password; the owner enters the key in Setup (README)"
fi

# ─── 2. No extra permission set on the guest ────────────────────────────────
# The guest user is found through the site, never by a hard-coded Id.
guest_id="$(query "SELECT GuestUserId FROM Site WHERE Name = 'RutaCargo' AND SiteType = 'ChatterNetwork'" \
    | jq -r '.[0].GuestUserId // empty')"
if [[ ! "$guest_id" =~ ^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
    echo "guest-proof-access: the RutaCargo site has no guest user in $ORG" >&2
    exit 1
fi
# guest_id is validated above before it enters a query.
assignments="$(query "SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '$guest_id' AND PermissionSet.Name = '$OLD_PERMISSION_SET'" \
    | jq -r '.[].Id')"
if [[ -z "$assignments" ]]; then
    echo "guest-proof-access: the site guest user has no $OLD_PERMISSION_SET assignment"
else
    while IFS= read -r assignment_id; do
        if [[ ! "$assignment_id" =~ ^0Pa[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
            echo "guest-proof-access: unexpected assignment Id '$assignment_id'" >&2
            exit 1
        fi
        out="$(sf data delete record --target-org "$ORG" --json --sobject PermissionSetAssignment \
            --record-id "$assignment_id" 2>/dev/null || true)"
        if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
            echo "guest-proof-access: could not remove the $OLD_PERMISSION_SET assignment in $ORG" >&2
            exit 1
        fi
    done <<<"$assignments"
    echo "guest-proof-access: removed the $OLD_PERMISSION_SET assignment from the site guest user"
fi
echo "guest-proof-access: done in $ORG"
