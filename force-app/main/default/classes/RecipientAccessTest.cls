/**
 * @description Recipient verification and lockout of odd/tasks/req-002-003-recipient-delivery.md
 *              (T1, S1): AC-002.1 (the right values open the details with the
 *              postal code and the code typed loosely; every failure returns the
 *              same outcome and message and costs the same hash work, E2),
 *              AC-002.1b (5 counted failures lock the shipment for 15 minutes;
 *              failures are returned, never thrown; one guard row per shipment;
 *              a success resets the counter; a wrong postal code is not counted;
 *              no failure changes the shipment) and AC-002.7 (sharing keywords).
 *              Attempts go through RecipientDeliveryController, as the
 *              acceptance states; the seams T2 reuses (verifyBeforeCallout,
 *              resetAttempts) are called on RecipientAccess directly. Each test
 *              inserts its own shipment because the clear access code exists only
 *              in the transaction that inserts it.
 */
@IsTest
private with sharing class RecipientAccessTest {

    private static final String POSTAL_CODE = '64000';
    private static final String OTHER_POSTAL_CODE = '64001';
    private static final String UNKNOWN_TRACKING_NUMBER = 'RC000000000';
    private static final String MALFORMED_CODE = 'abc';
    private static final String ACCOUNT_NAME = 'Recipient Access Customer';
    private static final Integer MAX_FAILURES = 5;
    private static final Integer LOCK_MINUTES = 15;

    // A saved shipment with its tracking number and its clear access code.
    private with sharing class Fixture {
        Id shipmentId;
        String trackingNumber;
        String code;
    }

    private static Fixture insertShipment(String postalCode) {
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        Shipment__c shipment = TestDataFactory.newShipment(customer.Id);
        shipment.Destination_Postal_Code__c = postalCode;
        shipment.Estimated_Delivery__c = Date.newInstance(2026, 12, 10);
        Map<Id, String> codes = TestDataFactory.insertShipmentsWithCodes(new List<Shipment__c>{ shipment });
        Fixture fixture = new Fixture();
        fixture.shipmentId = shipment.Id;
        fixture.code = codes.get(shipment.Id);
        fixture.trackingNumber = [SELECT Name FROM Shipment__c WHERE Id = :shipment.Id WITH SYSTEM_MODE].Name;
        return fixture;
    }

    // A code of the right format that is not the shipment's code.
    private static String wrongCode(String code) {
        return (code.startsWith('A') ? 'B' : 'A') + code.substring(1);
    }

    private static String hyphenated(String code) {
        return code.substring(0, 4) + '-' + code.substring(4, 8) + '-' + code.substring(8);
    }

    private static List<Recipient_Access_Guard__c> guardsOf(Id shipmentId) {
        return [
            SELECT Id, Shipment__c, Shipment_Key__c, Failed_Attempts__c, Locked_Until__c
            FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :String.valueOf(shipmentId)
            WITH SYSTEM_MODE
        ];
    }

    private static Decimal failedAttemptsOf(Id shipmentId) {
        List<Recipient_Access_Guard__c> guards = guardsOf(shipmentId);
        return guards.isEmpty() ? null : guards[0].Failed_Attempts__c;
    }

    // One getDeliveryDetails call that must return, never throw (AC-002.1b).
    private static RecipientDeliveryController.DeliveryResponse details(Fixture fixture, String postalCode, String code) {
        RecipientDeliveryController.DeliveryResponse response;
        try {
            response = RecipientDeliveryController.getDeliveryDetails(fixture.trackingNumber, postalCode, code);
        } catch (Exception unexpected) {
            Assert.fail('A failed verification must be returned, not thrown: ' + unexpected.getTypeName());
        }
        return response;
    }

    // One failed attempt through rescheduleDelivery that must return, never throw.
    private static RecipientDeliveryController.DeliveryResponse reschedule(Fixture fixture, String code) {
        RecipientDeliveryController.DeliveryResponse response;
        try {
            response = RecipientDeliveryController.rescheduleDelivery(
                fixture.trackingNumber, POSTAL_CODE, code, '2026-12-12', 'Leave with the doorman');
        } catch (Exception unexpected) {
            Assert.fail('A failed verification must be returned, not thrown: ' + unexpected.getTypeName());
        }
        return response;
    }

    private static Integer hashWorkOf(String trackingNumber, String postalCode, String code) {
        Integer before = DeliveryAccessCode.hashesComputed;
        RecipientDeliveryController.getDeliveryDetails(trackingNumber, postalCode, code);
        return DeliveryAccessCode.hashesComputed - before;
    }

    // ─── AC-002.1: the right values, typed loosely ────────────────────────

    @IsTest
    static void shouldOpenDetails_WhenPostalCodeHasSpacesAndCodeIsHyphenatedLowerCase() {
        // AC-002.1: " 64000 " and K with hyphens, in lower case.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response =
            details(fixture, ' 64000 ', hyphenated(fixture.code).toLowerCase());
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The right values must open the details');
        Assert.isNotNull(response.details, 'A verified request must return the details');
    }

    @IsTest
    static void shouldOpenDetails_WhenCodeHasSpacesAndPostalCodeHasInnerSpaceAndOtherCase() {
        // AC-002.1, a second input: another shipment, code typed with spaces, postal code "c 1 0 0" vs "C100".
        Fixture fixture = insertShipment('C100');
        String spaced = fixture.code.substring(0, 6) + ' ' + fixture.code.substring(6);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, 'c 1 0 0', spaced);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'Spaces and case must be ignored');
    }

    // ─── AC-002.1: every failure looks the same ──────────────────────────

    @IsTest
    static void shouldReturnNotMatched_WhenTrackingNumberIsUnknown() {
        // AC-002.1: unknown tracking number.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response =
            RecipientDeliveryController.getDeliveryDetails(UNKNOWN_TRACKING_NUMBER, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Unknown tracking number: not matched');
        Assert.areEqual('The details do not match this shipment', response.message, 'Unknown tracking number: the shared message');
        Assert.isNull(response.details, 'No details without verification');
    }

    @IsTest
    static void shouldReturnNotMatched_WhenPostalCodeIsWrong() {
        // AC-002.1: postal code "64001" with the right code.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, OTHER_POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Wrong postal code: not matched');
        Assert.areEqual('The details do not match this shipment', response.message, 'Wrong postal code: the shared message');
        Assert.isNull(response.details, 'No details without verification');
    }

    @IsTest
    static void shouldReturnNotMatched_WhenCodeIsWrong() {
        // AC-002.1: the right postal code and a wrong code; postal code alone never opens the details.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Wrong code: not matched');
        Assert.areEqual('The details do not match this shipment', response.message, 'Wrong code: the shared message');
        Assert.isNull(response.details, 'No details without verification');
    }

    @IsTest
    static void shouldReturnNotMatched_WhenCodeIsMalformed() {
        // AC-002.1: a malformed code.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, POSTAL_CODE, MALFORMED_CODE);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Malformed code: not matched');
        Assert.areEqual('The details do not match this shipment', response.message, 'Malformed code: the shared message');
        Assert.isNull(response.details, 'No details without verification');
    }

    @IsTest
    static void shouldReturnNotMatched_WhenCodeIsBlank() {
        // AC-002.1: a blank code.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, POSTAL_CODE, '   ');
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Blank code: not matched');
        Assert.areEqual('The details do not match this shipment', response.message, 'Blank code: the shared message');
        Assert.isNull(response.details, 'No details without verification');
    }

    @IsTest
    static void shouldDoOneHashForEveryFailureAndForSuccess_WhenAnyValueIsWrong() {
        // AC-002.1, E2: unknown tracking number, wrong postal code, wrong, malformed and
        // blank code each cost exactly the hash work of a success (one stored value).
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        Integer unknown = hashWorkOf(UNKNOWN_TRACKING_NUMBER, POSTAL_CODE, fixture.code);
        Integer wrongPostal = hashWorkOf(fixture.trackingNumber, OTHER_POSTAL_CODE, fixture.code);
        Integer wrong = hashWorkOf(fixture.trackingNumber, POSTAL_CODE, wrongCode(fixture.code));
        Integer malformed = hashWorkOf(fixture.trackingNumber, POSTAL_CODE, MALFORMED_CODE);
        Integer blank = hashWorkOf(fixture.trackingNumber, POSTAL_CODE, '');
        Integer success = hashWorkOf(fixture.trackingNumber, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(1, success, 'A success computes one stored value');
        Assert.areEqual(success, unknown, 'An unknown tracking number must cost the same hash work');
        Assert.areEqual(success, wrongPostal, 'A wrong postal code must cost the same hash work');
        Assert.areEqual(success, wrong, 'A wrong code must cost the same hash work');
        Assert.areEqual(success, malformed, 'A malformed code must cost the same hash work');
        Assert.areEqual(success, blank, 'A blank code must cost the same hash work');
    }

    // ─── AC-002.1b: lockout ──────────────────────────────────────────────

    @IsTest
    static void shouldCountEachFailureAndLockFor15Minutes_WhenFiveFailuresWithRightPostalCode() {
        // AC-002.1b: 5 failures with the right postal code and a wrong code, returned not thrown;
        // the guard is read after each call.
        Fixture fixture = insertShipment(POSTAL_CODE);
        List<Decimal> counts = new List<Decimal>();

        Test.startTest();
        Datetime before = Datetime.now();
        for (Integer attempt = 1; attempt < MAX_FAILURES; attempt++) {
            details(fixture, POSTAL_CODE, wrongCode(fixture.code));
            counts.add(failedAttemptsOf(fixture.shipmentId));
        }
        RecipientDeliveryController.DeliveryResponse fifth = details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        Datetime after = Datetime.now();
        Test.stopTest();

        Assert.areEqual(new List<Decimal>{ 1, 2, 3, 4 }, counts, 'Each counted failure must add one to the guard');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, fifth.outcome, 'The fifth failure itself is a plain failure');
        Recipient_Access_Guard__c guard = guardsOf(fixture.shipmentId)[0];
        Assert.areEqual(MAX_FAILURES, guard.Failed_Attempts__c, 'The counter stays at 5 while locked (CODE-001)');
        Assert.isTrue(guard.Locked_Until__c >= before.addMinutes(LOCK_MINUTES).addSeconds(-1)
            && guard.Locked_Until__c <= after.addMinutes(LOCK_MINUTES).addSeconds(1),
            'The shipment must be locked for 15 minutes, was ' + guard.Locked_Until__c);
    }

    @IsTest
    static void shouldNotCountFurther_WhenGuardIsLockedWhenTheFailureIsCounted() {
        // AC-002.1b (X16, CODE-001): a failure that passed the lock check before a parallel
        // lock committed reaches countFailure on a row that is already locked; it is not
        // counted again: the counter stays at 5 and the running lock is not moved.
        Fixture fixture = insertShipment(POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, MAX_FAILURES, Datetime.now().addMinutes(10))
        });
        Recipient_Access_Guard__c before = guardsOf(fixture.shipmentId)[0];

        Test.startTest();
        RecipientAccess.countFailure(fixture.shipmentId);
        Test.stopTest();

        Recipient_Access_Guard__c after = guardsOf(fixture.shipmentId)[0];
        Assert.areEqual(MAX_FAILURES, after.Failed_Attempts__c, 'A locked guard is not counted further');
        Assert.areEqual(before.Locked_Until__c, after.Locked_Until__c, 'The running lock is not moved');
    }

    @IsTest
    static void shouldRefuseWithoutVerifying_WhenSixthAttemptHasRightValues() {
        // AC-002.1b: after 5 failures, the right values get the lock message and no hash work.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        for (Integer attempt = 0; attempt < MAX_FAILURES; attempt++) {
            details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        }
        Integer hashesBefore = DeliveryAccessCode.hashesComputed;
        RecipientDeliveryController.DeliveryResponse sixth = details(fixture, POSTAL_CODE, fixture.code);
        Integer hashWork = DeliveryAccessCode.hashesComputed - hashesBefore;
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, sixth.outcome, 'A locked shipment must be refused');
        Assert.areEqual('Too many attempts. Please try again in 15 minutes.', sixth.message, 'The lock message');
        Assert.isNull(sixth.details, 'A locked shipment returns no details');
        Assert.areEqual(0, hashWork, 'No verification is made while locked');
    }

    @IsTest
    static void shouldLockTheSameShipment_WhenFailuresComeThroughDetailsAndReschedule() {
        // AC-002.1b: failures through getDeliveryDetails and rescheduleDelivery count toward one lock
        // (downloadProof joins in T2).
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        reschedule(fixture, wrongCode(fixture.code));
        reschedule(fixture, wrongCode(fixture.code));
        Decimal afterFour = failedAttemptsOf(fixture.shipmentId);
        RecipientDeliveryController.DeliveryResponse fifth = reschedule(fixture, wrongCode(fixture.code));
        RecipientDeliveryController.DeliveryResponse sixth = details(fixture, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(4, afterFour, 'Both methods must count toward the same guard');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, fifth.outcome, 'A failed reschedule is returned as not matched');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, sixth.outcome, 'The fifth failure must lock the shipment');
    }

    @IsTest
    static void shouldOpenDetailsAndResetCounter_WhenLockHasExpired() {
        // AC-002.1b: Locked_Until__c in the past, the right values open the details, counter reset.
        Fixture fixture = insertShipment(POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, 3, Datetime.now().addMinutes(-1))
        });

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'An expired lock no longer refuses');
        Assert.areEqual(0, failedAttemptsOf(fixture.shipmentId), 'A success resets the counter');
    }

    @IsTest
    static void shouldRefuse_WhenLockIsStillActive() {
        // AC-002.1b: a lock in the future refuses the right values.
        Fixture fixture = insertShipment(POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, 0, Datetime.now().addMinutes(1))
        });

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, response.outcome, 'An active lock refuses the right values');
    }

    @IsTest
    static void shouldResetCounterToZero_WhenSuccessComesBeforeFifthFailure() {
        // AC-002.1b: 4 failures, a success resets to 0, so a fifth failure does not lock.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        for (Integer attempt = 1; attempt < MAX_FAILURES; attempt++) {
            details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        }
        details(fixture, POSTAL_CODE, fixture.code);
        Decimal afterSuccess = failedAttemptsOf(fixture.shipmentId);
        details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        Test.stopTest();

        Assert.areEqual(0, afterSuccess, 'A success must reset the counter to 0');
        Recipient_Access_Guard__c guard = guardsOf(fixture.shipmentId)[0];
        Assert.areEqual(1, guard.Failed_Attempts__c, 'The next failure starts again from 1');
        Assert.isNull(guard.Locked_Until__c, 'The shipment must not be locked');
    }

    @IsTest
    static void shouldNotCount_WhenPostalCodeIsWrong() {
        // AC-002.1b: failures with a wrong postal code are not counted.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        for (Integer attempt = 0; attempt <= MAX_FAILURES; attempt++) {
            details(fixture, OTHER_POSTAL_CODE, wrongCode(fixture.code));
        }
        RecipientDeliveryController.DeliveryResponse response = details(fixture, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(0, guardsOf(fixture.shipmentId).size(), 'A wrong postal code must not create or change a guard');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The shipment must not be locked');
    }

    @IsTest
    static void shouldKeepOneGuardRow_WhenTwoFirstFailuresArrive() {
        // AC-002.1b: two first failures never create two guard rows (upsert on Shipment_Key__c).
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        Test.stopTest();

        List<Recipient_Access_Guard__c> guards = guardsOf(fixture.shipmentId);
        Assert.areEqual(1, guards.size(), 'One guard row per shipment');
        Assert.areEqual(2, guards[0].Failed_Attempts__c, 'Both failures counted on the same row');
        Assert.areEqual(fixture.shipmentId, guards[0].Shipment__c, 'The guard looks up its shipment');
        Assert.areEqual(String.valueOf(fixture.shipmentId), guards[0].Shipment_Key__c, 'The key is the 18-character shipment Id');
    }

    @IsTest
    static void shouldNotChangeShipment_WhenGuestFailsFiveTimes() {
        // AC-002.1b: no failure changes the Shipment__c row, as the real site guest user.
        Fixture fixture = insertShipment(POSTAL_CODE);
        Shipment__c before = [
            SELECT LastModifiedDate, LastModifiedById, SystemModstamp FROM Shipment__c
            WHERE Id = :fixture.shipmentId WITH SYSTEM_MODE
        ];

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            for (Integer attempt = 0; attempt < MAX_FAILURES; attempt++) {
                details(fixture, POSTAL_CODE, wrongCode(fixture.code));
            }
        }
        Test.stopTest();

        Shipment__c after = [
            SELECT LastModifiedDate, LastModifiedById, SystemModstamp FROM Shipment__c
            WHERE Id = :fixture.shipmentId WITH SYSTEM_MODE
        ];
        Assert.areEqual(before.LastModifiedDate, after.LastModifiedDate, 'LastModifiedDate must not change');
        Assert.areEqual(before.LastModifiedById, after.LastModifiedById, 'LastModifiedById must not change');
        Assert.areEqual(before.SystemModstamp, after.SystemModstamp, 'SystemModstamp must not change');
        Assert.isNotNull(guardsOf(fixture.shipmentId)[0].Locked_Until__c, 'The guest failures are counted on the guard');
    }

    // ─── Seam for T2 (downloadProof): no DML before a callout ────────────

    @IsTest
    static void shouldMakeNoDml_WhenVerifiedBeforeCallout() {
        // AC-002.1b / S3 seam: a successful check before a callout is DML-free; resetAttempts resets after.
        Fixture fixture = insertShipment(POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, 2, null)
        });

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        RecipientAccess.Verification verification =
            RecipientAccess.verifyBeforeCallout(fixture.trackingNumber, POSTAL_CODE, fixture.code);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Decimal beforeReset = failedAttemptsOf(fixture.shipmentId);
        RecipientAccess.resetAttempts(verification);
        Test.stopTest();

        Assert.isTrue(verification.isVerified(), 'The right values verify');
        Assert.areEqual(0, dmlUsed, 'No DML before the callout');
        Assert.areEqual(2, beforeReset, 'The counter is untouched before the callout');
        Assert.areEqual(0, failedAttemptsOf(fixture.shipmentId), 'resetAttempts resets the counter after the callout');
    }

    @IsTest
    static void shouldCountFailure_WhenVerifiedBeforeCalloutFails() {
        // AC-002.1b / S3 seam: a failed check before a callout is counted.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        RecipientAccess.Verification verification =
            RecipientAccess.verifyBeforeCallout(fixture.trackingNumber, POSTAL_CODE, wrongCode(fixture.code));
        Test.stopTest();

        Assert.isFalse(verification.isVerified(), 'A wrong code does not verify');
        Assert.areEqual(RecipientAccess.Outcome.NOT_MATCHED, verification.outcome, 'Not matched');
        Assert.areEqual(1, failedAttemptsOf(fixture.shipmentId), 'The failure is counted');
    }

    // ─── AC-002.7: sharing keywords ──────────────────────────────────────

    @IsTest
    static void shouldDeclareSharingAndJustification_WhenClassesAreDeployed() {
        // AC-002.7 (P11): RecipientAccess is without sharing with a SECURITY-JUSTIFICATION;
        // RecipientDeliveryController and RecipientDeliveryDetails are with sharing.
        Map<String, String> bodies = new Map<String, String>();
        for (ApexClass apexClass : [
            SELECT Name, Body FROM ApexClass
            WHERE Name IN ('RecipientAccess', 'RecipientDeliveryController', 'RecipientDeliveryDetails')
            WITH SYSTEM_MODE
        ]) {
            bodies.put(apexClass.Name, apexClass.Body);
        }

        Assert.isTrue(bodies.get('RecipientAccess').contains('public without sharing class RecipientAccess'),
            'RecipientAccess must be without sharing');
        Assert.isTrue(bodies.get('RecipientAccess').contains('// SECURITY-JUSTIFICATION:'),
            'RecipientAccess must carry a SECURITY-JUSTIFICATION comment');
        Assert.isTrue(bodies.get('RecipientDeliveryController').contains('public with sharing class RecipientDeliveryController'),
            'The controller must be with sharing');
        Assert.isTrue(bodies.get('RecipientDeliveryDetails').contains('public with sharing class RecipientDeliveryDetails'),
            'The DTO must be with sharing');
    }
}
