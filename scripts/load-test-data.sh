#!/usr/bin/env bash
# Loads the fictional test data (2 customers, 2 site users, 120 shipments) into an org.
# Usage: scripts/load-test-data.sh <org-alias>
set -euo pipefail
ORG="${1:?Usage: scripts/load-test-data.sh <org-alias>}"
cd "$(dirname "$0")/apex"
sf apex run -o "$ORG" -f assign-permission-sets.apex | grep -E "ASSIGNED|Error|error" || true
sf apex run -o "$ORG" -f setup-owner-role.apex | grep -E "Error|error" || true
sf apex run -o "$ORG" -f load-test-data-1-records.apex | grep -E "LOADED|Error|error" || true
sf apex run -o "$ORG" -f load-test-data-2-users.apex | grep -E "TESTUSER|Error|error" || true
