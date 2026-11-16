#!/bin/bash
# Prepares the RutaCargo development org after `sf project deploy start`.
# Usage: scripts/setup-org.sh <org-alias>
# Steps: assign permission set to the running user, give it the owner role used for customer accounts,
# load the test data. Site users are created by scripts/apex/create-site-users.apex once the site sender
# address is verified (see README).
set -euo pipefail
ORG="${1:?Usage: scripts/setup-org.sh <org-alias>}"
USERNAME=$(sf org display --target-org "$ORG" --json | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['username'])")

sf org assign permset --name RutaCargo_Support_Agent --target-org "$ORG" || true

ROLE_ID=$(sf data query --query "SELECT Id FROM UserRole WHERE DeveloperName = 'RutaCargo_Customer_Owner'" --target-org "$ORG" --json | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['records'][0]['Id'])")
sf data update record --sobject User --where "Username='$USERNAME'" --values "UserRoleId=$ROLE_ID" --target-org "$ORG"

sf apex run --file scripts/apex/load-test-data.apex --target-org "$ORG"
echo "Done. Next: verify the site sender address, then run scripts/apex/create-site-users.apex."
