#!/usr/bin/env bash
# Schedules the daily purge of stale recipient attempt guards
# (RecipientAccessGuardPurge, hardening-1 S2, AC-H2.1). Idempotent: when the job
# "RecipientAccessGuardPurge daily" exists, running it again changes nothing
# (RecipientAccessGuardPurge.scheduleDaily returns the existing job), so there is
# never a duplicate CronTrigger.
#
# The job runs daily at 03:00 in the time zone of the user this script runs as,
# and as that user: run it as an admin who can see every guard row.
# Run it after force-app is deployed (scripts/setup/DEPLOY-ORDER.md).
#
# P7 / H3 (sf-security-auditor note 2): RecipientAccessGuardPurge is `with
# sharing`, so it deletes only the guard rows its running user can see. The
# script refuses (exit 1, nothing scheduled) unless the user it runs as holds
# View All Data (PermissionsViewAllData, through the profile or a permission
# set; read-only query on PermissionSetAssignment), and, when the job exists
# already, unless the job's owner (the user it runs as) holds it too.
# Test seam: GUARD_PURGE_ALSO_CHECK_USERNAME=<username> checks that user as well,
# so the refusal can be shown without changing any user; it can only add a
# refusal, never remove one.
#
# Usage: scripts/setup/schedule-guard-purge.sh <org-alias>
set -euo pipefail

ORG="${1:-}"
if [[ -z "$ORG" ]]; then
    echo "Usage: $0 <org-alias>" >&2
    exit 2
fi

# Must equal RecipientAccessGuardPurge.JOB_NAME.
JOB_NAME='RecipientAccessGuardPurge daily'

# Prints the scheduled purge jobs as JSON; stops the script on an error.
purge_jobs() {
    local out
    out="$(sf data query --target-org "$ORG" --json \
        --query "SELECT Id, CronExpression, State, NextFireTime FROM CronTrigger WHERE CronJobDetail.Name = '$JOB_NAME'" \
        2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "schedule-guard-purge: CronTrigger query failed in $ORG" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 1
    fi
    jq -c '.result.records' <<<"$out"
}

# Exits 1 unless the active user matching the SOQL condition holds View All Data.
# $1: a label for the messages; $2: a condition on Assignee (a quoted username or an Id).
require_view_all_data() {
    local label="$1" condition="$2" out
    out="$(sf data query --target-org "$ORG" --json \
        --query "SELECT COUNT() FROM PermissionSetAssignment WHERE $condition AND Assignee.IsActive = true AND PermissionSet.PermissionsViewAllData = true" \
        2>/dev/null || true)"
    if [[ "$(jq -r '.status // 1' <<<"$out" 2>/dev/null)" != "0" ]]; then
        echo "schedule-guard-purge: View All Data query failed for $label in $ORG" >&2
        jq -r '.message // empty' <<<"$out" >&2 2>/dev/null || true
        exit 1
    fi
    if [[ "$(jq -r '.result.totalSize // 0' <<<"$out")" -lt 1 ]]; then
        echo "schedule-guard-purge: refused: $label has no View All Data in $ORG; the purge is with sharing and would not see every guard row. Run it as an admin with View All Data." >&2
        exit 1
    fi
    echo "schedule-guard-purge: $label holds View All Data"
}

# A username for a SOQL string literal: only the characters of a username.
quoted_username() {
    if [[ ! "$1" =~ ^[A-Za-z0-9._%+@-]+$ ]]; then
        echo "schedule-guard-purge: not a username: refusing to query it" >&2
        exit 1
    fi
    printf "'%s'" "$1"
}

RUN_AS="$(sf org display --target-org "$ORG" --json 2>/dev/null | jq -r '.result.username // empty' 2>/dev/null || true)"
if [[ -z "$RUN_AS" ]]; then
    echo "schedule-guard-purge: could not read the user of $ORG" >&2
    exit 1
fi
# Assigned first, so a refused username stops the script (set -e).
run_as_literal="$(quoted_username "$RUN_AS")"
require_view_all_data "the user this script runs as ($RUN_AS)" "Assignee.Username = $run_as_literal"
if [[ -n "${GUARD_PURGE_ALSO_CHECK_USERNAME:-}" ]]; then
    also_literal="$(quoted_username "$GUARD_PURGE_ALSO_CHECK_USERNAME")"
    require_view_all_data "the user to check ($GUARD_PURGE_ALSO_CHECK_USERNAME)" "Assignee.Username = $also_literal"
fi

existing="$(purge_jobs)"
owner_id="$(sf data query --target-org "$ORG" --json \
    --query "SELECT OwnerId FROM CronTrigger WHERE CronJobDetail.Name = '$JOB_NAME'" 2>/dev/null \
    | jq -r '.result.records[0].OwnerId // empty' 2>/dev/null || true)"
if [[ "$(jq 'length' <<<"$existing")" != "0" ]]; then
    if [[ ! "$owner_id" =~ ^005[A-Za-z0-9]{12}([A-Za-z0-9]{3})?$ ]]; then
        echo "schedule-guard-purge: could not read the owner of the scheduled job in $ORG" >&2
        exit 1
    fi
    require_view_all_data "the owner of the scheduled job ($owner_id)" "AssigneeId = '$owner_id'"
fi

before="$(jq 'length' <<<"$existing")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
printf '%s\n' 'Id jobId = RecipientAccessGuardPurge.scheduleDaily();' > "$work/schedule.apex"

out="$(sf apex run --file "$work/schedule.apex" --target-org "$ORG" --json 2>/dev/null || true)"
compiled="$(jq -r '.result.compiled // false' <<<"$out" 2>/dev/null || echo false)"
success="$(jq -r '.result.success // false' <<<"$out" 2>/dev/null || echo false)"
if [[ "$compiled" != "true" || "$success" != "true" ]]; then
    echo "schedule-guard-purge: scheduling failed in $ORG" >&2
    jq -r '.result.compileProblem // empty, .result.exceptionMessage // empty, .message // empty' <<<"$out" >&2 2>/dev/null || true
    exit 1
fi

jobs="$(purge_jobs)"
after="$(jq 'length' <<<"$jobs")"
if [[ "$after" != "1" ]]; then
    echo "schedule-guard-purge: expected exactly 1 job named '$JOB_NAME' in $ORG, found $after" >&2
    exit 1
fi
if [[ "$before" == "1" ]]; then
    echo "schedule-guard-purge: already scheduled in $ORG; nothing changed"
else
    echo "schedule-guard-purge: scheduled in $ORG"
fi
jq -r '.[0] | "schedule-guard-purge: \(.CronExpression) state \(.State), next run \(.NextFireTime)"' <<<"$jobs"
