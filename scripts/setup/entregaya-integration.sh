#!/usr/bin/env bash
# Setup for AC-004.6 (odd/tasks/req-004-carrier-status.md, S4, B8): the EntregaYa
# integration user and the OAuth policies of the External Client App
# "EntregaYa Status". Run it after the force-app deploy (scripts/setup/
# DEPLOY-ORDER.md), which creates the app, the permission set and the group.
#
# Steps (idempotent: running it again changes nothing):
#   0. refuses an org that is not a sandbox or scratch org (Organization.IsSandbox
#      must be true) and stops if the app EntregaYa_Status is not deployed;
#   1-3. scripts/setup/entregaya-integration.apex: creates the user
#      entregaya-integration@<org id, lower case>.rutacargo.dev when missing
#      (profile "Minimum Access - API Only Integrations", Salesforce Integration
#      license) and, in the same transaction, assigns the "Salesforce API
#      Integration" permission set license (B8), then the permission set
#      RutaCargo_EntregaYa_Integration, and adds it to the group
#      RutaCargo_EntregaYa_Integration;
#   4. renders scripts/setup/templates/EntregaYa_Status_oauth_defaultPolicy.
#      ecaOauthPlcy.template with that username into a temporary folder and
#      deploys it: client credentials flow running as that user, permission set
#      RutaCargo_EntregaYa_Integration pre-authorized, IP restrictions enforced;
#   5. prints what it did. It never reads or prints the consumer key, the
#      consumer secret or a token.
#
# Usage: scripts/setup/entregaya-integration.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$ROOT/scripts/setup/templates/EntregaYa_Status_oauth_defaultPolicy.ecaOauthPlcy.template"
POLICY_NAME='EntregaYa_Status_oauth_defaultPolicy'
ECA_NAME='EntregaYa_Status'
API_VERSION='67.0'

die() { echo "entregaya-integration: $*" >&2; exit 1; }

query() {
    local out
    out="$(sf data query --target-org "$ORG" --json --query "$1" 2>/dev/null || true)"
    [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" == "0" ]] || die "query failed: $1"
    jq -c '.result.records' <<<"$out"
}

# ─── 0. Never a production org; the app must exist ──────────────────────────
org="$(query "SELECT Id, IsSandbox FROM Organization")"
[[ "$(jq -r '.[0].IsSandbox' <<<"$org")" == "true" ]] || die "refused: $ORG is not a sandbox or scratch org"
org_id="$(jq -r '.[0].Id' <<<"$org")"
[[ "$org_id" =~ ^00D[A-Za-z0-9]{15}$ ]] || die "unexpected organization Id"
username="entregaya-integration@$(tr '[:upper:]' '[:lower:]' <<<"$org_id").rutacargo.dev"
[[ "$username" =~ ^entregaya-integration@00d[a-z0-9]{15}\.rutacargo\.dev$ ]] || die "unexpected username"
[[ "$(jq 'length' <<<"$(query "SELECT Id FROM ExternalClientApplication WHERE DeveloperName = '$ECA_NAME'")")" == "1" ]] \
    || die "External Client App $ECA_NAME not found; deploy force-app first"
echo "entregaya-integration: $ORG is a sandbox or scratch org"

# ─── 1-3. User, permission set license, permission set, group ──────────────
out="$(sf apex run --file "$ROOT/scripts/setup/entregaya-integration.apex" --target-org "$ORG" --json 2>/dev/null || true)"
if [[ "$(jq -r '.result.compiled // false' <<<"$out" 2>/dev/null)" != "true" \
   || "$(jq -r '.result.success // false' <<<"$out" 2>/dev/null)" != "true" ]]; then
    echo "entregaya-integration: the user setup failed in $ORG" >&2
    jq -r '.result.compileProblem // empty, .result.exceptionMessage // empty, .message // empty' <<<"$out" >&2 2>/dev/null || true
    exit 1
fi
jq -r '.result.logs // ""' <<<"$out" | grep 'USER_DEBUG' | grep -o 'entregaya-integration: .*' || true
users="$(query "SELECT Id FROM User WHERE Username = '$username' AND IsActive = true")"
[[ "$(jq 'length' <<<"$users")" == "1" ]] || die "the integration user was not found after the setup"
echo "entregaya-integration: integration user is $username"

# ─── 4. OAuth policies from the template ────────────────────────────────────
[[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE"
[[ "$(grep -c '{{INTEGRATION_USERNAME}}' "$TEMPLATE")" == "1" ]] || die "the template must hold the username placeholder once"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/mdapi/extlClntAppOauthPolicies"
sed "s|{{INTEGRATION_USERNAME}}|$username|" "$TEMPLATE" > "$tmp/mdapi/extlClntAppOauthPolicies/$POLICY_NAME.ecaOauthPlcy"
cat > "$tmp/mdapi/package.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>$POLICY_NAME</members>
        <name>ExtlClntAppOauthConfigurablePolicies</name>
    </types>
    <version>$API_VERSION</version>
</Package>
EOF
deploy="$(sf project deploy start --metadata-dir "$tmp/mdapi" --target-org "$ORG" --wait 30 --json 2>/dev/null || true)"
if [[ "$(jq -r '.status // 1' <<<"$deploy" 2>/dev/null)" != "0" ]]; then
    echo "entregaya-integration: the OAuth policies deploy failed in $ORG" >&2
    jq -r '.message // empty, (.result.details.componentFailures // [] | if type == "array" then .[] else . end | .problem // empty)' <<<"$deploy" >&2 2>/dev/null || true
    exit 1
fi
# Reads the deployed policy back: the run fails unless the org now has it.
user_id="$(jq -r '.[0].Id' <<<"$users")"
policy="$(query "SELECT IsClientCredentialsFlowEnabled, ClientCredentialsFlowUser, PermittedUsersPolicyType, IpRelaxationPolicyType FROM ExtlClntAppOauthPlcyCnfg WHERE DeveloperName = '$POLICY_NAME'")"
[[ "$(jq 'length' <<<"$policy")" == "1" ]] || die "policy $POLICY_NAME not found after the deploy"
if ! jq -e --arg u "${user_id:0:15}" '.[0] | .IsClientCredentialsFlowEnabled == true
        and ((.ClientCredentialsFlowUser // "")[0:15] == $u)
        and .PermittedUsersPolicyType == "AdminApprovedPreAuthorized"
        and .IpRelaxationPolicyType == "Enforce"' <<<"$policy" >/dev/null; then
    die "policy $POLICY_NAME deployed but the org does not show it: $(jq -c '.[0] | {IsClientCredentialsFlowEnabled, PermittedUsersPolicyType, IpRelaxationPolicyType}' <<<"$policy")"
fi
echo "entregaya-integration: OAuth policies $POLICY_NAME deployed and read back: client credentials as the integration user, admin-approved users pre-authorized, IP restrictions enforced"
echo "entregaya-integration: done in $ORG. The consumer key and secret stay in the org: Setup > External Client App Manager > EntregaYa Status (README, EntregaYa integration)."
