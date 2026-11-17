#!/usr/bin/env bash
# Simulates EntregaYa sending one status change to RutaCargo (REQ-004).
#
#   scripts/entregaya/send-status-update.sh <org-alias> <trackingNumber> "<status>" "<location>" [timestamp] [proofId]
#
# Authentication:
#   * With ENTREGAYA_CLIENT_ID and ENTREGAYA_CLIENT_SECRET set (External Client App "EntregaYa"),
#     it gets a token with OAuth 2.0 client credentials, exactly as EntregaYa will, and the call
#     runs as the EntregaYa integration user.
#   * Otherwise it uses the Salesforce CLI session of <org-alias> (handy for local testing only).
#
# Example:
#   scripts/entregaya/send-status-update.sh rutacargoaopus RC000001042 "Out for delivery" "Monterrey, NL" 2026-11-20T10:00:00-06:00
set -euo pipefail
ORG="${1:?org alias}"; TRACKING="${2:?tracking number}"; STATUS="${3:?status}"; LOCATION="${4:-}"
TIMESTAMP="${5:-$(TZ=America/Mexico_City date +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/')}"
PROOF="${6:-}"
PATH_REST="/services/apexrest/entregaya/v1/status-updates"
BODY=$(python3 -c 'import json,sys; t,s,l,ts,p=sys.argv[1:6]; print(json.dumps({"trackingNumber":t,"status":s,"location":l,"timestamp":ts,"proofId":p or None}))' \
  "$TRACKING" "$STATUS" "$LOCATION" "$TIMESTAMP" "$PROOF")

echo "POST $PATH_REST"
echo "$BODY"
if [[ -n "${ENTREGAYA_CLIENT_ID:-}" && -n "${ENTREGAYA_CLIENT_SECRET:-}" ]]; then
  INSTANCE=$(sf org display -o "$ORG" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["instanceUrl"])')
  TOKEN=$(curl -s -X POST "$INSTANCE/services/oauth2/token" \
    -d grant_type=client_credentials \
    --data-urlencode "client_id=$ENTREGAYA_CLIENT_ID" \
    --data-urlencode "client_secret=$ENTREGAYA_CLIENT_SECRET" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("access_token") or sys.exit("OAuth error: " + json.dumps(d)))')
  curl -s -w '\nHTTP %{http_code}\n' -X POST "$INSTANCE$PATH_REST" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$BODY"
else
  echo "(using the CLI session of $ORG; set ENTREGAYA_CLIENT_ID/ENTREGAYA_CLIENT_SECRET to test OAuth)"
  sf api request rest "$PATH_REST" --method POST --body "$BODY" -o "$ORG" 2>/dev/null; echo
fi
