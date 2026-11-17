#!/usr/bin/env bash
# RutaCargo — reproducible setup of a development org (scratch or Developer Edition).
#
#   scripts/setup-org.sh <org-alias>
#
# Optional environment variables:
#   TEST_USER_PASSWORD   password for the test site users (Ana López, Marta Ruiz). Random if unset.
#   ENTREGAYA_API_KEY    EntregaYa API key, stored in the EntregaYa External Credential.
#
# Steps (each one is idempotent):
#   1. Enable Digital Experiences and create the "RutaCargo" LWR site if it does not exist.
#   2. Deploy the metadata (the Network is deployed twice the first time: self-registration can only
#      point at a profile that is already a member of the site).
#   3. Org configuration: admin role, settings, guest permission set.
#   4. Test data (2 customers, 120 shipments RC000001001..RC000001120) and test site users.
#   5. EntregaYa integration user + External Client App run-as user + API key.
#   6. Publish the site.
set -euo pipefail
ORG="${1:?usage: $0 <org-alias>}"
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
step() { printf '\n== %s\n' "$*"; }
apex() { sf apex run -o "$ORG" -f "$1" | grep -E 'USER_DEBUG|Error|Exception' || true; }

step "1. Digital Experiences and site"
sf project deploy start -o "$ORG" -d force-app/main/default/settings --wait 20 >/dev/null
if ! sf data query -o "$ORG" -q "SELECT Id FROM Network WHERE Name = 'RutaCargo'" --json | grep -q '"totalSize": 1'; then
  sf community create -o "$ORG" --name "RutaCargo" --template-name "Build Your Own (LWR)" \
    --url-path-prefix rutacargo --description "RutaCargo shipping and tracking site"
  echo "Waiting for the site to be created..."
  for _ in $(seq 1 60); do
    sf data query -o "$ORG" -q "SELECT Id FROM Network WHERE Name = 'RutaCargo'" --json | grep -q '"totalSize": 1' && break
    sleep 10
  done
fi

step "2. Deploy metadata"
NETWORK=force-app/main/default/networks/RutaCargo.network-meta.xml
cp "$NETWORK" "$TMP/network.xml"
sed -e 's#<selfRegistration>true</selfRegistration>#<selfRegistration>false</selfRegistration>#' -e '/<selfRegProfile>/d' "$TMP/network.xml" > "$NETWORK"
sf project deploy start -o "$ORG" -d force-app --wait 60 || { cp "$TMP/network.xml" "$NETWORK"; exit 1; }
cp "$TMP/network.xml" "$NETWORK"
sf project deploy start -o "$ORG" -d force-app/main/default/networks --wait 20

step "3. Org configuration"
sf org assign permset -o "$ORG" -n RutaCargo_Support_Agent >/dev/null 2>&1 || true
apex scripts/apex/configure-org.apex
apex scripts/apex/configure-settings.apex

step "4. Test data"
apex scripts/apex/load-test-data.apex
PASSWORD="${TEST_USER_PASSWORD:-Rc$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)7}"
sed "s/__TEST_USER_PASSWORD__/${PASSWORD}/" scripts/apex/create-test-users.apex > "$TMP/users.apex"
apex "$TMP/users.apex"
[[ -z "${TEST_USER_PASSWORD:-}" ]] && echo "Test site users password (shown once): ${PASSWORD}"

step "5. EntregaYa integration"
apex scripts/apex/create-integration-user.apex
RUNAS=$(sf data query -o "$ORG" -q "SELECT Username FROM User WHERE Username LIKE 'entregaya.integration@rutacargo-%'" --json |
  python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]["records"]; print(r[0]["Username"] if r else "")')
POLICY=force-app/main/default/extlClntAppOauthPolicies/EntregaYa_oauthPlcy.ecaOauthPlcy-meta.xml
cp "$POLICY" "$TMP/policy.xml"
sed "s#<isClientCredentialsFlowEnabled>false</isClientCredentialsFlowEnabled>#<clientCredentialsFlowUser>${RUNAS}</clientCredentialsFlowUser><isClientCredentialsFlowEnabled>true</isClientCredentialsFlowEnabled>#" \
  "$TMP/policy.xml" > "$POLICY"
sf project deploy start -o "$ORG" -d force-app/main/default/extlClntAppOauthPolicies --wait 20 >/dev/null || echo "WARN: could not enable client credentials (see README)"
cp "$TMP/policy.xml" "$POLICY"
if [[ -n "${ENTREGAYA_API_KEY:-}" ]]; then
  scripts/setup-entregaya-key.sh "$ORG"
else
  echo "ENTREGAYA_API_KEY not set: store the key later with scripts/setup-entregaya-key.sh"
fi

step "6. Publish"
sf community publish -o "$ORG" -n RutaCargo
echo "Done. Pending manual steps: see README.md"
