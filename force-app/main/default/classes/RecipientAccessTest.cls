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
 *              hardening-1 T1 (S1) keys the guard on the pair (shipment, typed
 *              postal code normalized): AC-H1.1 (the recipient's postal code and
 *              another one answer the same, NOT_MATCHED five times then LOCKED,
 *              with the same hash work), AC-H1.2 (failures with other postal
 *              codes never lock the recipient's pair) and AC-H1.3 (space and case
 *              variants share one pair and its 5-attempt limit; the lock expires
 *              on the clock seam; an existing pair row is read FOR UPDATE before
 *              the code comparison; a success makes no DML). The guard tests of
 *              AC-002.1b now read the pair of the typed postal code.
 *              hardening-1 T2 (S2): AC-H2.1 (typed postal codes longer than 10
 *              characters after normalization share one per-shipment malformed
 *              row, with the same response and hash work; a value of 10
 *              characters keeps its own pair; a recipient whose stored code has
 *              punctuation is still granted access after over-long failures)
 *              and T1's Low CODE-001 (X16): the postal code is compared exactly,
 *              so a Kelvin-sign variant of a stored "K" does not match.
 */
@IsTest
private with sharing class RecipientAccessTest {

    private static final String POSTAL_CODE = '64000';
    private static final String OTHER_POSTAL_CODE = '64001';
    private static final String MADRID_POSTAL_CODE = '28001';
    private static final String LETTER_POSTAL_CODE = 'K1A0B1';
    private static final String UNKNOWN_TRACKING_NUMBER = 'RC000000000';
    private static final String MALFORMED_CODE = 'abc';
    private static final String ACCOUNT_NAME = 'Recipient Access Customer';
    private static final Integer MAX_FAILURES = 5;
    private static final Integer LOCK_MINUTES = 15;
    private static final String DEFAULT_RECIPIENT = 'Test Recipient';
    private static final Date TODAY_IN_MEXICO = Date.newInstance(2026, 12, 5);
    private static final String VALID_NEW_DATE = '2026-12-12';
    private static final String DOORMAN = 'Leave with the doorman';
    private static final String ELEVEN_CHARACTERS = '12345678901';
    private static final String PUNCTUATED_POSTAL_CODE = '28-001';
    // U+212A KELVIN SIGN, written as an escape: Apex == folds it to "K".
    private static final String KELVIN_SIGN = '\u212A';

    // A saved shipment with its tracking number and its clear access code.
    private with sharing class Fixture {
        Id shipmentId;
        String trackingNumber;
        String code;
    }

    private static Fixture insertShipment(String postalCode) {
        return insertShipment(postalCode, DEFAULT_RECIPIENT);
    }

    private static Fixture insertShipment(String postalCode, String recipientName) {
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        Shipment__c shipment = TestDataFactory.newShipment(customer.Id);
        shipment.Destination_Postal_Code__c = postalCode;
        shipment.Recipient_Name__c = recipientName;
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

    // The guard rows of one (shipment, typed postal code) pair.
    private static List<Recipient_Access_Guard__c> guardsOf(Id shipmentId, String typedPostalCode) {
        return [
            SELECT Id, Shipment__c, Shipment_Key__c, Failed_Attempts__c, Locked_Until__c
            FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :TestDataFactory.recipientAccessGuardKey(shipmentId, typedPostalCode)
            WITH SYSTEM_MODE
        ];
    }

    // Every guard row of a shipment, whatever its key.
    private static List<Recipient_Access_Guard__c> allGuardsOf(Id shipmentId) {
        return [
            SELECT Id, Shipment_Key__c, Failed_Attempts__c, Locked_Until__c
            FROM Recipient_Access_Guard__c
            WHERE Shipment__c = :shipmentId
            WITH SYSTEM_MODE
        ];
    }

    // The counter of the recipient's pair (POSTAL_CODE), or null without a row.
    private static Decimal failedAttemptsOf(Id shipmentId) {
        List<Recipient_Access_Guard__c> guards = guardsOf(shipmentId, POSTAL_CODE);
        return guards.isEmpty() ? null : guards[0].Failed_Attempts__c;
    }

    // One getDeliveryDetails call, as "outcome|message|hash work".
    private static String answerOf(String trackingNumber, String postalCode, String code) {
        Integer before = DeliveryAccessCode.hashesComputed;
        RecipientDeliveryController.DeliveryResponse response =
            RecipientDeliveryController.getDeliveryDetails(trackingNumber, postalCode, code);
        return response.outcome + '|' + response.message + '|' + (DeliveryAccessCode.hashesComputed - before);
    }

    // Six requests with a wrong code and the given postal code.
    private static List<String> sixWrongCodeAnswers(Fixture fixture, String postalCode) {
        List<String> answers = new List<String>();
        for (Integer attempt = 0; attempt < MAX_FAILURES + 1; attempt++) {
            answers.add(answerOf(fixture.trackingNumber, postalCode, wrongCode(fixture.code)));
        }
        return answers;
    }

    // AC-H1.1: NOT_MATCHED with one hash five times, then LOCKED with no hash work.
    private static List<String> fiveNotMatchedThenLocked() {
        List<String> expected = new List<String>();
        for (Integer attempt = 0; attempt < MAX_FAILURES; attempt++) {
            expected.add(RecipientDeliveryController.OUTCOME_NOT_MATCHED + '|' + RecipientAccess.NOT_MATCHED_MESSAGE + '|1');
        }
        expected.add(RecipientDeliveryController.OUTCOME_LOCKED + '|' + RecipientAccess.LOCKED_MESSAGE + '|0');
        return expected;
    }

    // Five failures, each with one of the variants of the postal code and a wrong code.
    private static void failWithVariants(Fixture fixture, List<String> variants) {
        for (String variant : variants) {
            details(fixture, variant, wrongCode(fixture.code));
        }
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
                fixture.trackingNumber, POSTAL_CODE, code, VALID_NEW_DATE, DOORMAN);
        } catch (Exception unexpected) {
            Assert.fail('A failed verification must be returned, not thrown: ' + unexpected.getTypeName());
        }
        return response;
    }

    private static Shipment__c rescheduleFieldsOf(Id shipmentId) {
        return [
            SELECT Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c
            FROM Shipment__c WHERE Id = :shipmentId WITH SYSTEM_MODE
        ];
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
        Assert.areEqual(DEFAULT_RECIPIENT, response.details.recipientName, 'The details are the verified shipment\'s');
    }

    @IsTest
    static void shouldOpenDetails_WhenCodeHasSpacesAndPostalCodeHasInnerSpaceAndOtherCase() {
        // AC-002.1, a second input: another shipment, code typed with spaces, postal code "c 1 0 0" vs "C100".
        Fixture fixture = insertShipment('C100', 'Maria Lopez');
        String spaced = fixture.code.substring(0, 6) + ' ' + fixture.code.substring(6);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, 'c 1 0 0', spaced);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'Spaces and case must be ignored');
        Assert.areEqual('Maria Lopez', response.details.recipientName, 'The details are the verified shipment\'s');
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
    static void shouldReturnNotMatchedWithOneHash_WhenTrackingNumberIsBlank() {
        // AC-002.1 (E2): a blank tracking number is not matched and costs one hash, like any failure.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        Integer hashesBefore = DeliveryAccessCode.hashesComputed;
        RecipientDeliveryController.DeliveryResponse response =
            RecipientDeliveryController.getDeliveryDetails('   ', POSTAL_CODE, fixture.code);
        Integer hashWork = DeliveryAccessCode.hashesComputed - hashesBefore;
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Blank tracking number: not matched');
        Assert.areEqual(RecipientAccess.NOT_MATCHED_MESSAGE, response.message, 'Blank tracking number: the shared message');
        Assert.areEqual(1, hashWork, 'A blank tracking number costs the same hash work as a success');
    }

    @IsTest
    static void shouldReturnNotMatchedWithOneHash_WhenTrackingNumberIsOver80Characters() {
        // AC-002.1 (E2): a tracking number over 80 characters is not matched and costs one hash.
        Fixture fixture = insertShipment(POSTAL_CODE);
        String tooLong = fixture.trackingNumber + 'X'.repeat(81 - fixture.trackingNumber.length());

        Test.startTest();
        Integer hashesBefore = DeliveryAccessCode.hashesComputed;
        RecipientDeliveryController.DeliveryResponse response =
            RecipientDeliveryController.getDeliveryDetails(tooLong, POSTAL_CODE, fixture.code);
        Integer hashWork = DeliveryAccessCode.hashesComputed - hashesBefore;
        Test.stopTest();

        Assert.areEqual(81, tooLong.length(), 'Fixture: 81 characters');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Over 80 characters: not matched');
        Assert.areEqual(RecipientAccess.NOT_MATCHED_MESSAGE, response.message, 'Over 80 characters: the shared message');
        Assert.areEqual(1, hashWork, 'An over-long tracking number costs the same hash work as a success');
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
        Recipient_Access_Guard__c guard = guardsOf(fixture.shipmentId, POSTAL_CODE)[0];
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
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, POSTAL_CODE, MAX_FAILURES, Datetime.now().addMinutes(10))
        });
        Recipient_Access_Guard__c before = guardsOf(fixture.shipmentId, POSTAL_CODE)[0];

        Test.startTest();
        RecipientAccess.countFailure(fixture.shipmentId, TestDataFactory.recipientAccessGuardKey(fixture.shipmentId, POSTAL_CODE));
        Test.stopTest();

        Recipient_Access_Guard__c after = guardsOf(fixture.shipmentId, POSTAL_CODE)[0];
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
    static void shouldLockTheSamePair_WhenFailuresComeThroughDetailsAndReschedule() {
        // AC-002.1b: failures through getDeliveryDetails and rescheduleDelivery count toward the
        // lock of one pair (downloadProof joins in T2).
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

        Assert.areEqual(4, afterFour, 'Both methods must count toward the same pair');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, fifth.outcome, 'A failed reschedule is returned as not matched');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, sixth.outcome, 'The fifth failure must lock the pair');
    }

    @IsTest
    static void shouldRefuseRescheduleWithoutVerifyingOrWriting_WhenSixthAttemptHasRightValues() {
        // AC-002.1b: after 5 failures, a reschedule with the right values and a date inside the
        // window gets the lock message, makes no verification and does not change the shipment.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(POSTAL_CODE);
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixture.shipmentId, Status__c = 'In transit')
        });
        Shipment__c before = rescheduleFieldsOf(fixture.shipmentId);

        Test.startTest();
        for (Integer attempt = 0; attempt < MAX_FAILURES; attempt++) {
            reschedule(fixture, wrongCode(fixture.code));
        }
        Integer hashesBefore = DeliveryAccessCode.hashesComputed;
        RecipientDeliveryController.DeliveryResponse sixth = reschedule(fixture, fixture.code);
        Integer hashWork = DeliveryAccessCode.hashesComputed - hashesBefore;
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, sixth.outcome, 'A locked shipment must refuse the reschedule');
        Assert.areEqual(RecipientAccess.LOCKED_MESSAGE, sixth.message, 'The lock message');
        Assert.isNull(sixth.details, 'A locked shipment returns no details');
        Assert.areEqual(0, hashWork, 'No verification is made while locked');
        Shipment__c after = rescheduleFieldsOf(fixture.shipmentId);
        Assert.areEqual(before.Estimated_Delivery__c, after.Estimated_Delivery__c, 'The date must not change');
        Assert.areEqual(before.Delivery_Instructions__c, after.Delivery_Instructions__c, 'The instructions must not change');
        Assert.areEqual(before.Reschedule_Count__c, after.Reschedule_Count__c, 'The count must not change');
    }

    @IsTest
    static void shouldOpenDetailsAndResetCounter_WhenLockHasExpired() {
        // AC-002.1b: Locked_Until__c in the past, the right values open the details, counter reset.
        Fixture fixture = insertShipment(POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, POSTAL_CODE, 3, Datetime.now().addMinutes(-1))
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
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, POSTAL_CODE, 0, Datetime.now().addMinutes(1))
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
        Recipient_Access_Guard__c guard = guardsOf(fixture.shipmentId, POSTAL_CODE)[0];
        Assert.areEqual(1, guard.Failed_Attempts__c, 'The next failure starts again from 1');
        Assert.isNull(guard.Locked_Until__c, 'The shipment must not be locked');
    }

    @IsTest
    static void shouldKeepOneGuardRow_WhenTwoFirstFailuresArrive() {
        // AC-002.1b: two first failures never create two guard rows (upsert on Shipment_Key__c);
        // AC-H1.3: the key is the pair's (shipment Id + ":" + SHA-256 of the normalized postal code).
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        details(fixture, POSTAL_CODE, wrongCode(fixture.code));
        Test.stopTest();

        List<Recipient_Access_Guard__c> guards = allGuardsOf(fixture.shipmentId);
        String expectedKey = String.valueOf(fixture.shipmentId) + ':'
            + EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf('64000')));
        Assert.areEqual(1, guards.size(), 'One guard row per pair');
        Assert.areEqual(2, guards[0].Failed_Attempts__c, 'Both failures counted on the same row');
        Assert.areEqual(expectedKey, guards[0].Shipment_Key__c,
            'The key is the 18-character shipment Id, ":" and the hex SHA-256 of the normalized postal code');
        Assert.areEqual(83, guards[0].Shipment_Key__c.length(), 'The key is 18 + 1 + 64 characters');
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
        Assert.isNotNull(guardsOf(fixture.shipmentId, POSTAL_CODE)[0].Locked_Until__c, 'The guest failures are counted on the guard');
    }

    // ─── AC-H1.1: the right postal code cannot be told apart ─────────────

    @IsTest
    static void shouldAnswerTheSame_WhenSixWrongCodesComeWithRightAndWithOtherPostalCode() {
        // AC-H1.1 (SEC-002, X16): 6 wrong codes with the recipient's "28001", then 6 with "64000".
        Fixture fixture = insertShipment(MADRID_POSTAL_CODE);

        Test.startTest();
        List<String> withRight = sixWrongCodeAnswers(fixture, MADRID_POSTAL_CODE);
        List<String> withOther = sixWrongCodeAnswers(fixture, POSTAL_CODE);
        Test.stopTest();

        Assert.areEqual(fiveNotMatchedThenLocked(), withRight, 'The right postal code: NOT_MATCHED five times, then LOCKED');
        Assert.areEqual(withRight, withOther, 'Another postal code answers exactly like the right one');
    }

    @IsTest
    static void shouldAnswerTheSame_WhenGuestSendsOtherPostalCodeFirstThenTheRightOne() {
        // AC-H1.1 (SEC-002, X16), a second input as the site guest: 6 wrong codes with "C101"
        // first, then 6 with the recipient's "C100" typed as "c 100".
        Fixture fixture = insertShipment('C100', 'Maria Lopez');
        List<String> withOther;
        List<String> withRight;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            withOther = sixWrongCodeAnswers(fixture, 'C101');
            withRight = sixWrongCodeAnswers(fixture, 'c 100');
        }
        Test.stopTest();

        Assert.areEqual(fiveNotMatchedThenLocked(), withOther, 'Another postal code: NOT_MATCHED five times, then LOCKED');
        Assert.areEqual(withOther, withRight, 'The right postal code answers exactly like another one');
    }

    // ─── AC-H1.2: a guest without the postal code cannot lock the recipient ─

    @IsTest
    static void shouldOpenDetails_WhenGuestFailedSixTimesWithTwoOtherPostalCodes() {
        // AC-H1.2 (SEC-002): the guest fails 6 times with "11111" and 6 with " 99 999"; the
        // recipient then sends "64000" and the right code.
        Fixture fixture = insertShipment(POSTAL_CODE);
        RecipientDeliveryController.DeliveryResponse response;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            sixWrongCodeAnswers(fixture, '11111');
            sixWrongCodeAnswers(fixture, ' 99 999');
        }
        response = details(fixture, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The recipient is granted access');
        Assert.areEqual(DEFAULT_RECIPIENT, response.details.recipientName, 'The details are returned');
        Assert.areEqual(0, guardsOf(fixture.shipmentId, POSTAL_CODE).size(), 'The recipient\'s pair has no failure recorded');
        Assert.isNotNull(guardsOf(fixture.shipmentId, '11111')[0].Locked_Until__c, 'The guest\'s "11111" pair is locked');
        Assert.isNotNull(guardsOf(fixture.shipmentId, '99999')[0].Locked_Until__c, 'The guest\'s "99999" pair is locked');
    }

    @IsTest
    static void shouldOpenDetails_WhenGuestFailedFiveTimesWithBlankPostalCode() {
        // AC-H1.2 (SEC-002), a second input: 5 failures with a blank postal code (the fixed
        // token's pair) and the right code; the recipient then sends "k1a 0b1" and the right code.
        Fixture fixture = insertShipment(LETTER_POSTAL_CODE, 'Maria Lopez');

        Test.startTest();
        for (Integer attempt = 0; attempt < MAX_FAILURES; attempt++) {
            details(fixture, '   ', fixture.code);
        }
        RecipientDeliveryController.DeliveryResponse response = details(fixture, 'k1a 0b1', fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The recipient is granted access');
        Assert.areEqual('Maria Lopez', response.details.recipientName, 'The details are returned');
        Assert.areEqual(0, guardsOf(fixture.shipmentId, LETTER_POSTAL_CODE).size(), 'The recipient\'s pair has no failure recorded');
        Assert.areEqual(MAX_FAILURES, guardsOf(fixture.shipmentId, '')[0].Failed_Attempts__c, 'The blank pair counted the five');
    }

    @IsTest
    static void shouldNotCreateGuard_WhenTrackingNumberIsUnknown() {
        // S1 (decided): tracking numbers are public; an unknown one never creates a guard row.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        for (Integer attempt = 0; attempt <= MAX_FAILURES; attempt++) {
            RecipientDeliveryController.getDeliveryDetails(UNKNOWN_TRACKING_NUMBER, POSTAL_CODE, fixture.code);
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Recipient_Access_Guard__c WITH SYSTEM_MODE], 'No guard row for an unknown tracking number');
    }

    @IsTest
    static void shouldIgnoreLegacyShipmentKeyedGuard_WhenRecipientVerifies() {
        // S1: a guard row keyed on the shipment Id alone (written before hardening-1) matches no
        // pair key, so even a running lock on it does not refuse the recipient.
        Fixture fixture = insertShipment(POSTAL_CODE);
        Recipient_Access_Guard__c legacy = TestDataFactory.newRecipientAccessGuard(
            fixture.shipmentId, POSTAL_CODE, MAX_FAILURES, Datetime.now().addMinutes(10));
        legacy.Shipment_Key__c = String.valueOf(fixture.shipmentId);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{ legacy });

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'A per-shipment legacy row no longer locks');
    }

    // ─── AC-H1.3: the 5-attempt limit per pair ───────────────────────────

    @IsTest
    static void shouldLock_WhenFiveFailuresUseSpaceVariantsOfTheRightPostalCode() {
        // AC-H1.3 (SEC-011): " 28001", "28 001", "28001 ", "28001" and " 2 8 0 0 1" with wrong
        // codes, then the right code within 15 minutes.
        Fixture fixture = insertShipment(MADRID_POSTAL_CODE);

        Test.startTest();
        failWithVariants(fixture, new List<String>{ ' 28001', '28 001', '28001 ', '28001', ' 2 8 0 0 1' });
        RecipientDeliveryController.DeliveryResponse sixth = details(fixture, MADRID_POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, sixth.outcome, 'The variants share one pair: locked');
        Assert.areEqual(RecipientAccess.LOCKED_MESSAGE, sixth.message, 'The lock message');
        Assert.areEqual(1, allGuardsOf(fixture.shipmentId).size(), 'One guard row for all the variants');
    }

    @IsTest
    static void shouldLock_WhenFiveFailuresUseCaseAndSpaceVariantsOfTheRightPostalCode() {
        // AC-H1.3 (SEC-011), a second input: "k1a0b1", "K1A 0B1", " k1A0b1 ", "K1A0B1 " and
        // "k 1 a 0 b 1" with wrong codes, then the right code within 15 minutes.
        Fixture fixture = insertShipment(LETTER_POSTAL_CODE);

        Test.startTest();
        failWithVariants(fixture, new List<String>{ 'k1a0b1', 'K1A 0B1', ' k1A0b1 ', 'K1A0B1 ', 'k 1 a 0 b 1' });
        RecipientDeliveryController.DeliveryResponse sixth = details(fixture, LETTER_POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, sixth.outcome, 'The variants share one pair: locked');
        Assert.areEqual(1, allGuardsOf(fixture.shipmentId).size(), 'One guard row for all the variants');
    }

    @IsTest
    static void shouldOpenDetailsAndResetPair_WhenTheLockExpiresOnTheClock() {
        // AC-H1.3: 5 variant failures lock the pair; at +14 minutes the right code is still
        // LOCKED, at +16 minutes (clock seam) it works and resets the pair.
        Fixture fixture = insertShipment(MADRID_POSTAL_CODE);

        Test.startTest();
        failWithVariants(fixture, new List<String>{ ' 28001', '28 001', '28001 ', '28001', ' 2 8 0 0 1' });
        RecipientAccess.nowOverride = Datetime.now().addMinutes(LOCK_MINUTES - 1);
        RecipientDeliveryController.DeliveryResponse beforeExpiry = details(fixture, MADRID_POSTAL_CODE, fixture.code);
        RecipientAccess.nowOverride = Datetime.now().addMinutes(LOCK_MINUTES + 1);
        RecipientDeliveryController.DeliveryResponse afterExpiry = details(fixture, MADRID_POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, beforeExpiry.outcome, 'Still locked at 14 minutes');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, afterExpiry.outcome, 'The right code works after the lock');
        Assert.areEqual(0, guardsOf(fixture.shipmentId, MADRID_POSTAL_CODE)[0].Failed_Attempts__c, 'The success resets the pair');
    }

    @IsTest
    static void shouldReadThePairForUpdateBeforeTheCodeAndMakeNoDml_WhenVerifiedWithAnExistingRow() {
        // AC-H1.3 (SEC-011): with an existing pair row (2 failures), the row is read FOR UPDATE
        // before the code comparison and the successful verification makes no DML.
        Fixture fixture = insertShipment(MADRID_POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, MADRID_POSTAL_CODE, 2, null)
        });
        RecipientAccess.trace = new List<String>();

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        RecipientAccess.Verification verification =
            RecipientAccess.verifyBeforeCallout(fixture.trackingNumber, ' 28 001', fixture.code);
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.isTrue(verification.isVerified(), 'The right values verify');
        Assert.areEqual(new List<String>{ 'pairReadForUpdate:row', 'codeCompared' }, RecipientAccess.trace,
            'The existing pair row is read FOR UPDATE before the code comparison');
        Assert.areEqual(0, dmlUsed, 'A successful verification makes no DML');
        Assert.areEqual(2, guardsOf(fixture.shipmentId, MADRID_POSTAL_CODE)[0].Failed_Attempts__c, 'The counter is untouched');
    }

    @IsTest
    static void shouldReadThePairForUpdateBeforeTheCode_WhenTheCodeIsWrong() {
        // AC-H1.3 (SEC-011), a second input: a wrong code with "k1a 0b1" and an existing pair row;
        // the row is read FOR UPDATE before the comparison, then the failure is counted.
        Fixture fixture = insertShipment(LETTER_POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, LETTER_POSTAL_CODE, 1, null)
        });
        RecipientAccess.trace = new List<String>();

        Test.startTest();
        RecipientAccess.Verification verification =
            RecipientAccess.verifyBeforeCallout(fixture.trackingNumber, 'k1a 0b1', wrongCode(fixture.code));
        Test.stopTest();

        Assert.areEqual(RecipientAccess.Outcome.NOT_MATCHED, verification.outcome, 'A wrong code is not matched');
        Assert.areEqual(new List<String>{ 'pairReadForUpdate:row', 'codeCompared', 'failureCounted' }, RecipientAccess.trace,
            'The existing pair row is read FOR UPDATE before the code comparison');
        Assert.areEqual(2, guardsOf(fixture.shipmentId, LETTER_POSTAL_CODE)[0].Failed_Attempts__c, 'The failure is counted on the pair');
    }

    @IsTest
    static void shouldNeverReturnThePairKey_WhenAnsweringTheRecipient() {
        // S1 (hard rule): the pair key and its hash are never returned, on failure or success.
        Fixture fixture = insertShipment(POSTAL_CODE);
        String hash = TestDataFactory.recipientAccessGuardKey(fixture.shipmentId, POSTAL_CODE).substringAfter(':');

        Test.startTest();
        String failed = JSON.serialize(details(fixture, POSTAL_CODE, wrongCode(fixture.code)));
        String verified = JSON.serialize(details(fixture, POSTAL_CODE, fixture.code));
        Test.stopTest();

        Assert.isFalse(failed.containsIgnoreCase(hash), 'A failure never carries the postal-code hash');
        Assert.isFalse(verified.containsIgnoreCase(hash), 'A success never carries the postal-code hash');
    }

    // ─── AC-H2.1: over-long postal codes share one malformed key ─────────

    // Distinct postal codes longer than 10 characters after normalization (11, 12, ...).
    private static List<String> overLongValues(Integer count) {
        List<String> values = new List<String>();
        for (Integer index = 0; index < count; index++) {
            values.add('9'.repeat(11 + index));
        }
        return values;
    }

    // One getDeliveryDetails answer per typed postal code, each with a wrong code.
    private static List<String> wrongCodeAnswers(Fixture fixture, List<String> postalCodes) {
        List<String> answers = new List<String>();
        for (String postalCode : postalCodes) {
            answers.add(answerOf(fixture.trackingNumber, postalCode, wrongCode(fixture.code)));
        }
        return answers;
    }

    @IsTest
    static void shouldCountUnderOneMalformedRow_WhenElevenAnd200CharacterPostalCodesFail() {
        // AC-H2.1 (S2, P3): an 11-character and a 200-character value fail; one guard row for
        // both, on neither value's own pair, with the response and hash work of any failure.
        Fixture fixture = insertShipment(POSTAL_CODE);
        String twoHundred = 'A'.repeat(200);

        Test.startTest();
        List<String> answers = wrongCodeAnswers(fixture, new List<String>{ ELEVEN_CHARACTERS, twoHundred });
        Test.stopTest();

        String failure = RecipientDeliveryController.OUTCOME_NOT_MATCHED + '|' + RecipientAccess.NOT_MATCHED_MESSAGE + '|1';
        Assert.areEqual(new List<String>{ failure, failure }, answers, 'Over-long values answer like any failure, with one hash');
        List<Recipient_Access_Guard__c> guards = allGuardsOf(fixture.shipmentId);
        Assert.areEqual(1, guards.size(), 'All over-long values share one malformed guard row');
        Assert.areEqual(2, guards[0].Failed_Attempts__c, 'Both over-long failures are counted on that row');
        Assert.areEqual(0, guardsOf(fixture.shipmentId, ELEVEN_CHARACTERS).size(), 'The 11-character value has no pair of its own');
        Assert.areEqual(0, guardsOf(fixture.shipmentId, twoHundred).size(), 'The 200-character value has no pair of its own');
    }

    @IsTest
    static void shouldLock_WhenSixDifferentOverLongPostalCodesFail() {
        // AC-H2.1 (S2, P3), a second input: six different over-long values (11 to 16 characters)
        // share the malformed key's 5-attempt limit: NOT_MATCHED five times, then LOCKED.
        Fixture fixture = insertShipment(MADRID_POSTAL_CODE);

        Test.startTest();
        List<String> answers = wrongCodeAnswers(fixture, overLongValues(MAX_FAILURES + 1));
        Test.stopTest();

        Assert.areEqual(fiveNotMatchedThenLocked(), answers, 'Over-long values share one limit');
        Assert.areEqual(1, allGuardsOf(fixture.shipmentId).size(), 'One guard row for all the over-long values');
    }

    @IsTest
    static void shouldKeepOwnPair_WhenPostalCodeIsTenCharactersAfterNormalization() {
        // AC-H2.1 (S2): "12345 67890" (11 typed, 10 after normalization) and "28-001-ABC" (10, with
        // punctuation) each keep their own pair key, not the malformed one.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        wrongCodeAnswers(fixture, new List<String>{ '12345 67890', '28-001-ABC' });
        Test.stopTest();

        Assert.areEqual(1, guardsOf(fixture.shipmentId, '1234567890').size(), 'Ten characters keep their own pair');
        Assert.areEqual(1, guardsOf(fixture.shipmentId, '28-001-ABC').size(), 'Ten characters with punctuation keep their own pair');
        Assert.areEqual(2, allGuardsOf(fixture.shipmentId).size(), 'Two values, two pairs');
    }

    @IsTest
    static void shouldGrantAccess_WhenGuestFailedFiveOverLongValuesAndRecipientSendsPunctuatedCode() {
        // AC-H2.1 (S2, P3): stored "28-001"; the guest sends 5 failing over-long values; the
        // recipient then sends "28-001" and the right code.
        Fixture fixture = insertShipment(PUNCTUATED_POSTAL_CODE);

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            wrongCodeAnswers(fixture, overLongValues(MAX_FAILURES));
        }
        RecipientDeliveryController.DeliveryResponse response = details(fixture, PUNCTUATED_POSTAL_CODE, fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The recipient is granted access');
        Assert.areEqual(DEFAULT_RECIPIENT, response.details.recipientName, 'The details are returned');
        Assert.areEqual(0, guardsOf(fixture.shipmentId, PUNCTUATED_POSTAL_CODE).size(), 'The recipient\'s pair has no failure recorded');
        List<Recipient_Access_Guard__c> guards = allGuardsOf(fixture.shipmentId);
        Assert.areEqual(1, guards.size(), 'Only the malformed row exists');
        Assert.isNotNull(guards[0].Locked_Until__c, 'The malformed row is locked by the five failures');
    }

    @IsTest
    static void shouldGrantAccess_WhenGuestFailedSixOverLongValuesAndRecipientSendsLowerCasePunctuatedCode() {
        // AC-H2.1 (S2, P3), a second input: stored "K1A-0B1"; the guest sends 6 failing over-long
        // values that contain it ("K1A-0B1 K1A-0B1" and longer); the recipient sends " k1a-0b1".
        Fixture fixture = insertShipment('K1A-0B1', 'Maria Lopez');
        List<String> overLong = new List<String>();
        for (Integer index = 0; index <= MAX_FAILURES; index++) {
            overLong.add('K1A-0B1 K1A-0B1' + 'X'.repeat(index));
        }

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            wrongCodeAnswers(fixture, overLong);
        }
        RecipientDeliveryController.DeliveryResponse response = details(fixture, ' k1a-0b1', fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The recipient is granted access');
        Assert.areEqual('Maria Lopez', response.details.recipientName, 'The details are returned');
        Assert.areEqual(1, allGuardsOf(fixture.shipmentId).size(), 'Only the malformed row exists');
    }

    // ─── T2 Low CODE-001 (X16): a stored code that grows when upper-cased ─

    // Five failing over-long values from the guest, then the recipient's own stored code.
    private static RecipientDeliveryController.DeliveryResponse grantAfterGuestLocksMalformed(
        Fixture fixture, String typedPostalCode
    ) {
        System.runAs(TestDataFactory.siteGuestUser()) {
            wrongCodeAnswers(fixture, overLongValues(MAX_FAILURES));
        }
        return details(fixture, typedPostalCode, fixture.code);
    }

    @IsTest
    static void shouldGrantAccess_WhenStoredSharpSPostalCodeGrowsPastTenWhenUpperCased() {
        // AC-H2.1 / T2 CODE-001 (X16): stored "straße1234" (10 characters, "STRASSE1234" upper
        // cased); the guest locks the malformed key with 5 over-long values; the recipient
        // sending "straße1234" and the right code is still granted access.
        String stored = 'straße1234';
        Fixture fixture = insertShipment(stored);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = grantAfterGuestLocksMalformed(fixture, stored);
        Test.stopTest();

        Assert.areEqual(10, stored.length(), 'Fixture: ten characters as stored');
        Assert.areEqual(11, stored.toUpperCase().length(), 'Fixture: eleven characters upper cased');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The recipient is granted access');
        Assert.areEqual(DEFAULT_RECIPIENT, response.details.recipientName, 'The details are returned');
    }

    @IsTest
    static void shouldGrantAccess_WhenStoredLigaturePostalCodeGrowsPastTenWhenUpperCased() {
        // AC-H2.1 / T2 CODE-001 (X16), a second input: stored "ﬃ-1234567" (9 characters, the
        // ligature U+FB03 upper cases to "FFI", 11 characters); the recipient types it with spaces.
        String stored = 'ﬃ-1234567';
        Fixture fixture = insertShipment(stored, 'Maria Lopez');

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = grantAfterGuestLocksMalformed(fixture, ' ' + stored + ' ');
        Test.stopTest();

        Assert.areEqual(11, stored.toUpperCase().length(), 'Fixture: eleven characters upper cased');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The recipient is granted access');
        Assert.areEqual('Maria Lopez', response.details.recipientName, 'The details are returned');
    }

    @IsTest
    static void shouldKeepOwnPair_WhenTypedValueOfTenCharactersGrowsWhenUpperCased() {
        // AC-H2.1 / T2 CODE-001 (X16): "malformed" is decided on the typed value before upper
        // casing: "straße1234" fails on its own pair; "STRASSE1234" (11 typed) on the malformed key.
        Fixture fixture = insertShipment(POSTAL_CODE);

        Test.startTest();
        wrongCodeAnswers(fixture, new List<String>{ 'straße1234', 'STRASSE1234' });
        Test.stopTest();

        Assert.areEqual(1, guardsOf(fixture.shipmentId, 'straße1234').size(), 'Ten typed characters keep their own pair');
        Assert.areEqual(2, allGuardsOf(fixture.shipmentId).size(), 'Its own pair and the malformed row');
    }

    // ─── T1 Low CODE-001 (X16): exact postal-code comparison ──────────────

    @IsTest
    static void shouldNotMatch_WhenPostalCodeUsesKelvinSignForK() {
        // AC-H2.1 / CODE-001 (X16): stored "K1A0B1"; the Kelvin sign U+212A in place of "K" with the
        // right code must not match (it hashes to another pair, so it must not get a fresh limit).
        Fixture fixture = insertShipment(LETTER_POSTAL_CODE);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = details(fixture, KELVIN_SIGN + '1A0B1', fixture.code);
        Test.stopTest();

        Assert.areEqual(1, KELVIN_SIGN.length(), 'Fixture: one character');
        Assert.areEqual(8490, KELVIN_SIGN.codePointAt(0), 'Fixture: the Kelvin sign U+212A');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'A Kelvin-sign variant does not match');
        Assert.isNull(response.details, 'No details without verification');
    }

    @IsTest
    static void shouldNotMatch_WhenPostalCodeUsesKelvinSignWithSpacesAndLowerCase() {
        // AC-H2.1 / CODE-001 (X16), a second input: " " + U+212A + "1a 0b1" with the right code.
        Fixture fixture = insertShipment(LETTER_POSTAL_CODE, 'Maria Lopez');

        Test.startTest();
        RecipientAccess.Verification verification =
            RecipientAccess.verifyBeforeCallout(fixture.trackingNumber, ' ' + KELVIN_SIGN + '1a 0b1', fixture.code);
        Test.stopTest();

        Assert.areEqual(RecipientAccess.Outcome.NOT_MATCHED, verification.outcome, 'A Kelvin-sign variant does not match');
        Assert.areEqual(0, guardsOf(fixture.shipmentId, LETTER_POSTAL_CODE).size(), 'The recipient\'s pair is untouched');
    }

    // ─── Seam for T2 (downloadProof): no DML before a callout ────────────

    @IsTest
    static void shouldMakeNoDml_WhenVerifiedBeforeCallout() {
        // AC-002.1b / S3 seam: a successful check before a callout is DML-free; resetAttempts resets after.
        Fixture fixture = insertShipment(POSTAL_CODE);
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, POSTAL_CODE, 2, null)
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
        // RecipientDeliveryController, ProofOfDeliveryService and RecipientDeliveryDetails are with sharing.
        Map<String, String> bodies = new Map<String, String>();
        for (ApexClass apexClass : [
            SELECT Name, Body FROM ApexClass
            WHERE Name IN ('RecipientAccess', 'RecipientDeliveryController', 'ProofOfDeliveryService', 'RecipientDeliveryDetails')
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
        Assert.isTrue(bodies.get('ProofOfDeliveryService').contains('public with sharing class ProofOfDeliveryService'),
            'ProofOfDeliveryService must be with sharing');
        Assert.isTrue(bodies.get('RecipientDeliveryDetails').contains('public with sharing class RecipientDeliveryDetails'),
            'The DTO must be with sharing');
    }
}
