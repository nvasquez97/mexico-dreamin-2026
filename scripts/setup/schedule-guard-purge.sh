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

before="$(purge_jobs | jq 'length')"

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
