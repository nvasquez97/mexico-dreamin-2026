#!/usr/bin/env bash
# Simulates EntregaYa sending one status change to Salesforce (REQ-004), the same way the
# carrier will: OAuth 2.0 client credentials with the EntregaYa_Status_Updates external client
# app, then POST /services/apexrest/entregaya/v1/shipment-status.
#
# Credentials come from the environment, never from this repository:
#   SF_MY_DOMAIN               e.g. https://your-domain.my.salesforce.com
#   ENTREGAYA_CLIENT_ID        consumer key of EntregaYa_Status_Updates
#   ENTREGAYA_CLIENT_SECRET    consumer secret of EntregaYa_Status_Updates
#
# Usage: scripts/entregaya/send-status.sh <trackingNumber> "<status>" "<location>" [timestamp] [proofId]
#   scripts/entregaya/send-status.sh RC000001042 "Out for delivery" "Monterrey, NL"
#   scripts/entregaya/send-status.sh RC000001042 "Delivered" "Monterrey, NL" 2026-11-20T13:30:00-06:00 PRF-88231
set -euo pipefail
: "${SF_MY_DOMAIN:?Set SF_MY_DOMAIN}" "${ENTREGAYA_CLIENT_ID:?Set ENTREGAYA_CLIENT_ID}" "${ENTREGAYA_CLIENT_SECRET:?Set ENTREGAYA_CLIENT_SECRET}"
TRACKING="${1:?trackingNumber}"; STATUS="${2:?status}"; LOCATION="${3:?location}"
TIMESTAMP="${4:-$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-6))).replace(microsecond=0).isoformat())')}"
PROOF="${5:-}"

TOKEN="$(curl -s -X POST "$SF_MY_DOMAIN/services/oauth2/token" \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode "client_id=$ENTREGAYA_CLIENT_ID" \
  --data-urlencode "client_secret=$ENTREGAYA_CLIENT_SECRET" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("access_token") or sys.exit("Token request failed: " + d.get("error_description", d.get("error", "unknown"))))')"

BODY="$(python3 -c 'import json,sys; t,s,l,ts,p=sys.argv[1:]; print(json.dumps({"trackingNumber":t,"status":s,"location":l,"timestamp":ts,"proofId":p or None}))' "$TRACKING" "$STATUS" "$LOCATION" "$TIMESTAMP" "$PROOF")"
curl -s -X POST "$SF_MY_DOMAIN/services/apexrest/entregaya/v1/shipment-status" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$BODY"
echo
