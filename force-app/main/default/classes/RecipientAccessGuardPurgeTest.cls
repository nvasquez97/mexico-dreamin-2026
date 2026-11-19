/**
 * @description The daily purge of stale attempt guards of odd/tasks/hardening-1.md
 *              (T2, S2): AC-H2.1 (guard rows without an active lock last touched
 *              more than a day ago are deleted, legacy per-shipment rows
 *              included, while active locks and recent rows stay; a row that is
 *              locked, or unlocked but touched, after the batch started is never
 *              deleted (one test per condition of the re-read); the
 *              scheduled job starts the batch; scheduling is idempotent).
 *              Rows are inserted now, so "more than a day ago" is reached through
 *              the purge's test clock (the asOf constructor); the recent-row tests
 *              use the real clock and a clock 23 hours ahead.
 */
@IsTest
private with sharing class RecipientAccessGuardPurgeTest {

    private static final Integer STALE_ROW_COUNT = 251;
    private static final Integer TEST_BATCH_SIZE = 2000;
    private static final String ACCOUNT_NAME = 'Guard Purge Customer';
    private static final String DAILY_CRON = '0 0 3 * * ?';

    @TestSetup
    static void setupShipment() {
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        TestDataFactory.insertShipmentsWithCodes(new List<Shipment__c>{ TestDataFactory.newShipment(customer.Id) });
    }

    private static Id shipmentId() {
        return [SELECT Id FROM Shipment__c WITH SYSTEM_MODE LIMIT 1].Id;
    }

    // count unsaved guard rows of distinct pairs, each with the given lock.
    private static List<Recipient_Access_Guard__c> newGuards(Integer count, String prefix, Datetime lockedUntil) {
        Id shipment = shipmentId();
        List<Recipient_Access_Guard__c> guards = new List<Recipient_Access_Guard__c>();
        for (Integer index = 0; index < count; index++) {
            guards.add(TestDataFactory.newRecipientAccessGuard(shipment, prefix + index, 1, lockedUntil));
        }
        return guards;
    }

    private static Set<Id> idsOf(List<Recipient_Access_Guard__c> guards) {
        return new Map<Id, Recipient_Access_Guard__c>(guards).keySet();
    }

    private static Integer remaining(Set<Id> guardIds) {
        return [SELECT COUNT() FROM Recipient_Access_Guard__c WHERE Id IN :guardIds WITH SYSTEM_MODE];
    }

    private static void runPurge(Datetime asOf) {
        Test.startTest();
        Database.executeBatch(new RecipientAccessGuardPurge(asOf), TEST_BATCH_SIZE);
        Test.stopTest();
    }

    @IsTest
    static void shouldDeleteStaleRows_WhenUnlockedAndLastTouchedMoreThanADayAgo() {
        // AC-H2.1: 251 rows with no lock, one with an expired lock and one legacy row keyed on the
        // shipment Id alone, all last touched two days before the purge's clock.
        Datetime asOf = Datetime.now().addDays(2);
        List<Recipient_Access_Guard__c> stale = newGuards(STALE_ROW_COUNT, 'N', null);
        stale.addAll(newGuards(1, 'E', Datetime.now().addMinutes(-1)));
        Recipient_Access_Guard__c legacy = TestDataFactory.newRecipientAccessGuard(shipmentId(), 'L', 5, null);
        legacy.Shipment_Key__c = String.valueOf(shipmentId());
        stale.add(legacy);
        TestDataFactory.insertRecipientAccessGuards(stale);

        runPurge(asOf);

        Assert.areEqual(0, remaining(idsOf(stale)), 'Every stale row without an active lock is deleted');
    }

    @IsTest
    static void shouldKeepActiveLock_WhenLastTouchedMoreThanADayAgo() {
        // AC-H2.1 (hard rule): a row locked beyond the purge's clock stays, even when last touched
        // two days before it; a stale unlocked row beside it is deleted, so the purge did run.
        Datetime asOf = Datetime.now().addDays(2);
        List<Recipient_Access_Guard__c> locked = newGuards(1, 'A', asOf.addMinutes(10));
        List<Recipient_Access_Guard__c> stale = newGuards(1, 'S', null);
        List<Recipient_Access_Guard__c> all = new List<Recipient_Access_Guard__c>(locked);
        all.addAll(stale);
        TestDataFactory.insertRecipientAccessGuards(all);

        runPurge(asOf);

        Assert.areEqual(1, remaining(idsOf(locked)), 'An active lock is never deleted');
        Assert.areEqual(0, remaining(idsOf(stale)), 'The stale unlocked row beside it is deleted');
    }

    @IsTest
    static void shouldKeepRecentRows_WhenLastTouchedNow() {
        // AC-H2.1: rows with no lock or an expired lock, last touched now, stay (real clock).
        List<Recipient_Access_Guard__c> recent = newGuards(STALE_ROW_COUNT, 'R', null);
        recent.addAll(newGuards(1, 'X', Datetime.now().addMinutes(-1)));
        TestDataFactory.insertRecipientAccessGuards(recent);

        runPurge(null);

        Assert.areEqual(STALE_ROW_COUNT + 1, remaining(idsOf(recent)), 'Recent rows stay');
    }

    @IsTest
    static void shouldKeepRecentRows_WhenLastTouched23HoursBeforeThePurge() {
        // AC-H2.1, a second input: the purge's clock is 23 hours ahead, so the rows are less than a
        // day old and stay.
        List<Recipient_Access_Guard__c> recent = newGuards(2, 'H', null);
        TestDataFactory.insertRecipientAccessGuards(recent);

        runPurge(Datetime.now().addHours(23));

        Assert.areEqual(2, remaining(idsOf(recent)), 'Rows less than a day old stay');
    }

    @IsTest
    static void shouldNotDelete_WhenScopeRowIsUnlockedButTouchedAfterTheBatchStarted() {
        // AC-H2.1 (hard rule): execute re-reads its scope; rows in the scope with no lock but
        // touched now (a guest failed on them after start) are not deleted on the real clock.
        // Only the date condition of the re-read keeps them.
        List<Recipient_Access_Guard__c> touchedSinceStart = newGuards(2, 'U', null);
        TestDataFactory.insertRecipientAccessGuards(touchedSinceStart);

        Test.startTest();
        new RecipientAccessGuardPurge().execute((Database.BatchableContext) null, touchedSinceStart);
        Test.stopTest();

        Assert.areEqual(2, remaining(idsOf(touchedSinceStart)), 'An unlocked row touched after the batch started is not deleted');
    }

    @IsTest
    static void shouldNotDelete_WhenScopeRowIsLockedAfterTheBatchStartedButOld() {
        // AC-H2.1 (hard rule): execute re-reads its scope; rows in the scope locked until
        // asOf + 10 minutes are not deleted by a purge whose clock is two days ahead, although
        // they were last touched more than a day before it. Only the lock condition keeps them.
        Datetime asOf = Datetime.now().addDays(2);
        List<Recipient_Access_Guard__c> lockedSinceStart = newGuards(2, 'T', asOf.addMinutes(10));
        TestDataFactory.insertRecipientAccessGuards(lockedSinceStart);

        Test.startTest();
        new RecipientAccessGuardPurge(asOf).execute((Database.BatchableContext) null, lockedSinceStart);
        Test.stopTest();

        Assert.areEqual(2, remaining(idsOf(lockedSinceStart)), 'A row locked after the batch started is never deleted');
    }

    @IsTest
    static void shouldStartThePurgeBatch_WhenTheScheduledJobRuns() {
        // AC-H2.1: the Schedulable entry point starts the purge as a batch.
        Test.startTest();
        new RecipientAccessGuardPurge().execute((SchedulableContext) null);
        Test.stopTest();

        Assert.areEqual(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'RecipientAccessGuardPurge' AND JobType = 'BatchApex'
            WITH SYSTEM_MODE
        ], 'The scheduled job starts one purge batch');
    }

    @IsTest
    static void shouldScheduleOnceDaily_WhenScheduleDailyRunsTwice() {
        // AC-H2.1: scheduling is idempotent: a second call returns the same job, no duplicate.
        Test.startTest();
        Id first = RecipientAccessGuardPurge.scheduleDaily();
        Id second = RecipientAccessGuardPurge.scheduleDaily();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, CronExpression FROM CronTrigger
            WHERE CronJobDetail.Name = :RecipientAccessGuardPurge.JOB_NAME
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(first, second, 'The second call returns the job already scheduled');
        Assert.areEqual(1, jobs.size(), 'One scheduled purge job');
        Assert.areEqual(DAILY_CRON, jobs[0].CronExpression, 'The purge runs daily at 03:00');
    }
}
