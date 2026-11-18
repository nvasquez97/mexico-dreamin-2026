/**
 * @description Daily purge of stale recipient attempt guards (hardening-1 S2,
 *              policy P3, X16): deletes Recipient_Access_Guard__c rows that have
 *              no active lock (Locked_Until__c null or not after now) and were last
 *              modified more than one day ago. This bounds the rows a guest can
 *              create through RecipientAccess and removes the legacy rows keyed on
 *              the shipment Id alone. An active lock is never deleted: execute
 *              re-reads its scope FOR UPDATE with the same conditions, so a row a
 *              guest locked or touched after start is kept. Scheduled daily by
 *              scheduleDaily (scripts/setup/schedule-guard-purge.sh), idempotently.
 */
// SECURITY-JUSTIFICATION: no user holds any object permission on
// Recipient_Access_Guard__c (it is written only by RecipientAccess in system
// mode), so the purge reads and deletes it in system mode. The class stays with
// sharing, so it deletes only rows its running user can see (the admin who
// scheduled it). Scope: Recipient_Access_Guard__c rows with no active lock, last
// modified more than one day ago; no other object, no field written, no input
// from any caller. Compensating control: the scope is re-read FOR UPDATE in
// execute with the same conditions, so an active lock is never deleted.
// (pending owner approval, 2026-11-18)
public with sharing class RecipientAccessGuardPurge implements Schedulable, Database.Batchable<SObject> {

    /** @description The name of the scheduled job; one job with this name at most. */
    public static final String JOB_NAME = 'RecipientAccessGuardPurge daily';
    /** @description Every day at 03:00 in the scheduling user's time zone. */
    public static final String DAILY_CRON = '0 0 3 * * ?';
    @TestVisible
    private static final Integer BATCH_SIZE = 200;
    private static final Integer STALE_AFTER_DAYS = 1;

    // The purge's clock; null means Datetime.now() at each step. Set only by tests.
    private final Datetime asOf;

    /** @description A purge on the real clock. */
    public RecipientAccessGuardPurge() {
        this(null);
    }

    @TestVisible
    private RecipientAccessGuardPurge(Datetime asOf) {
        this.asOf = asOf;
    }

    /**
     * @description Schedules the purge daily under JOB_NAME, unless a job with that
     *              name exists already: then it returns that job and changes nothing.
     * @return the Id of the CronTrigger of the purge
     */
    public static Id scheduleDaily() {
        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            WITH USER_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }
        return System.schedule(JOB_NAME, DAILY_CRON, new RecipientAccessGuardPurge());
    }

    /**
     * @description The scheduled run: starts the purge batch on the real clock.
     * @param context the schedulable context (unused)
     */
    public void execute(SchedulableContext context) {
        Database.executeBatch(new RecipientAccessGuardPurge(), BATCH_SIZE);
    }

    /**
     * @description The guard rows with no active lock, last modified more than a day ago.
     * @param context the batch context (unused)
     * @return the query locator of the stale rows
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime now = now();
        Datetime cutoff = now.addDays(-STALE_AFTER_DAYS);
        return Database.getQueryLocator([
            SELECT Id FROM Recipient_Access_Guard__c
            WHERE (Locked_Until__c = null OR Locked_Until__c <= :now)
                AND LastModifiedDate < :cutoff
            WITH SYSTEM_MODE
        ]);
    }

    /**
     * @description Re-reads the scope FOR UPDATE with the same conditions and deletes
     *              only the rows that are still stale and unlocked. A row that fails
     *              to delete (for example deleted meanwhile) is left to the next run.
     * @param context the batch context (unused)
     * @param scope the rows found by start
     */
    public void execute(Database.BatchableContext context, List<Recipient_Access_Guard__c> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        Set<Id> scopeIds = new Map<Id, Recipient_Access_Guard__c>(scope).keySet();
        Datetime now = now();
        Datetime cutoff = now.addDays(-STALE_AFTER_DAYS);
        List<Recipient_Access_Guard__c> stale = [
            SELECT Id FROM Recipient_Access_Guard__c
            WHERE Id IN :scopeIds
                AND (Locked_Until__c = null OR Locked_Until__c <= :now)
                AND LastModifiedDate < :cutoff
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
        if (!stale.isEmpty()) {
            Database.delete(stale, false, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * @description Nothing to do after the last chunk.
     * @param context the batch context (unused)
     */
    public void finish(Database.BatchableContext context) {
        return;
    }

    private Datetime now() {
        return asOf ?? Datetime.now();
    }
}
