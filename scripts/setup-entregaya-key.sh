#!/usr/bin/env bash
# Stores the EntregaYa API key in the EntregaYa External Credential (principal "EntregaYaApiKey",
# parameter "ApiKey"). The key is read from the environment and never written to source control.
#   ENTREGAYA_API_KEY=ey_sk_test_... scripts/setup-entregaya-key.sh <org-alias>
set -euo pipefail
ORG="${1:?usage: ENTREGAYA_API_KEY=... $0 <org-alias>}"
: "${ENTREGAYA_API_KEY:?Set ENTREGAYA_API_KEY}"
API="/services/data/v67.0/named-credentials/credential"
BODY=$(cat <<JSON
{"externalCredential":"EntregaYa","principalName":"EntregaYaApiKey","principalType":"NamedPrincipal",
 "credentials":{"ApiKey":{"value":"${ENTREGAYA_API_KEY}","encrypted":true}}}
JSON
)
# PUT updates an existing credential; POST creates it the first time.
if ! sf api request rest "$API" --method PUT --body "$BODY" -o "$ORG" >/dev/null 2>&1; then
  sf api request rest "$API" --method POST --body "$BODY" -o "$ORG" >/dev/null
fi
echo "EntregaYa API key stored in External Credential EntregaYa (principal EntregaYaApiKey)."
