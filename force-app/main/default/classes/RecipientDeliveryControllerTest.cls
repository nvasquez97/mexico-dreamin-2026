/**
 * @description Delivery details and reschedule of odd/tasks/req-002-003-recipient-delivery.md
 *              (T1, S2): AC-002.2 (exactly the eleven keys, the shipment's
 *              values, no private value), AC-002.3 (a wrong postal code gets the
 *              shared message and no details), AC-002.7 (the real site guest user
 *              reads and reschedules although it cannot read Shipment__c),
 *              AC-003.1 (a valid reschedule saves the date, the instructions and
 *              the count), AC-003.2 (window from today + 1 in Mexico City to the
 *              original estimate + 7, through the "today" seam), AC-003.3
 *              (statuses) and AC-003.4 (at most 2 reschedules). Each test inserts
 *              its own shipments: the clear access code exists only in the
 *              transaction that inserts it.
 *              downloadProof (T2, S3): AC-002.4 (the proof of two verified
 *              Delivered shipments through GET callout:EntregaYa_API/proofs/{id},
 *              nothing stored; no callout and proofAvailable false when not
 *              Delivered or without Proof_Id__c; another shipment's proof, bytes
 *              that are not a PDF and a body over the cap get the AC-002.5
 *              message), AC-002.5 (401, 404, 500 and a timeout get exactly that
 *              message and no response text; no DML before the callout and a
 *              non-zero counter reset after it), AC-002.1b (a failed
 *              downloadProof is counted, makes no callout and shares the lock
 *              with getDeliveryDetails) and AC-002.7 (the real site guest user
 *              downloads although it cannot read Shipment__c). Every callout is
 *              answered by an HttpCalloutMock.
 */
@IsTest
private with sharing class RecipientDeliveryControllerTest {

    private static final String POSTAL_CODE = '64000';
    private static final String ACCOUNT_NAME = 'Recipient Delivery Customer';
    private static final Date ORIGINAL = Date.newInstance(2026, 12, 10);
    private static final Date TODAY_IN_MEXICO = Date.newInstance(2026, 12, 5);
    private static final String DOORMAN = 'Leave with the doorman';
    private static final String PICKED_UP = 'Picked up';
    private static final String IN_TRANSIT = 'In transit';
    private static final Set<String> DETAIL_KEYS = new Set<String>{
        'recipientName', 'deliveryAddress', 'contactPhone', 'estimatedDelivery', 'deliveryInstructions',
        'status', 'canReschedule', 'reschedulesLeft', 'rescheduleFrom', 'rescheduleTo', 'proofAvailable'
    };

    // A saved shipment with its tracking number and its clear access code.
    private with sharing class Fixture {
        Id shipmentId;
        String trackingNumber;
        String code;
    }

    private static Shipment__c newShipment(Id accountId, Date estimate) {
        Shipment__c shipment = TestDataFactory.newShipment(accountId);
        shipment.Destination_Postal_Code__c = POSTAL_CODE;
        shipment.Estimated_Delivery__c = estimate;
        return shipment;
    }

    // Inserts the shipments, then sets the fields the trigger fixes on insert.
    private static List<Fixture> insertShipments(List<Shipment__c> shipments, List<String> statuses, List<Integer> counts) {
        Map<Id, String> codes = TestDataFactory.insertShipmentsWithCodes(shipments);
        List<Shipment__c> changes = new List<Shipment__c>();
        for (Integer i = 0; i < shipments.size(); i++) {
            changes.add(new Shipment__c(Id = shipments[i].Id, Status__c = statuses[i], Reschedule_Count__c = counts[i]));
        }
        TestDataFactory.updateAsSystem(changes);
        Map<Id, Shipment__c> names = new Map<Id, Shipment__c>([
            SELECT Id, Name FROM Shipment__c WHERE Id IN :codes.keySet() WITH SYSTEM_MODE
        ]);
        List<Fixture> fixtures = new List<Fixture>();
        for (Shipment__c shipment : shipments) {
            Fixture fixture = new Fixture();
            fixture.shipmentId = shipment.Id;
            fixture.code = codes.get(shipment.Id);
            fixture.trackingNumber = names.get(shipment.Id).Name;
            fixtures.add(fixture);
        }
        return fixtures;
    }

    private static Fixture insertShipment(String status, Integer count, Date estimate) {
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        return insertShipments(new List<Shipment__c>{ newShipment(customer.Id, estimate) },
            new List<String>{ status }, new List<Integer>{ count })[0];
    }

    private static Shipment__c reload(Id shipmentId) {
        return [
            SELECT Estimated_Delivery__c, Original_Estimated_Delivery__c, Delivery_Instructions__c,
                Reschedule_Count__c, Status__c, Price__c, Recipient_Name__c, SystemModstamp
            FROM Shipment__c WHERE Id = :shipmentId WITH SYSTEM_MODE
        ];
    }

    private static RecipientDeliveryController.DeliveryResponse reschedule(Fixture fixture, String newDate, String instructions) {
        return RecipientDeliveryController.rescheduleDelivery(
            fixture.trackingNumber, POSTAL_CODE, fixture.code, newDate, instructions);
    }

    private static String iso(Date value) {
        return String.valueOf(value);
    }

    // Rejected with the given message, and the shipment did not change.
    private static void assertRejectedUnchanged(
        RecipientDeliveryController.DeliveryResponse response, String message, Shipment__c before, Id shipmentId
    ) {
        Assert.areEqual(RecipientDeliveryController.OUTCOME_REJECTED, response.outcome, 'The reschedule must be rejected');
        Assert.areEqual(message, response.message, 'The rejection message');
        Shipment__c after = reload(shipmentId);
        Assert.areEqual(before.Estimated_Delivery__c, after.Estimated_Delivery__c, 'The date must not change');
        Assert.areEqual(before.Delivery_Instructions__c, after.Delivery_Instructions__c, 'The instructions must not change');
        Assert.areEqual(before.Reschedule_Count__c, after.Reschedule_Count__c, 'The count must not change');
        Assert.areEqual(before.SystemModstamp, after.SystemModstamp, 'The shipment must not be written');
    }

    // ─── AC-002.2: the details ───────────────────────────────────────────

    @IsTest
    static void shouldReturnExactlyTheElevenKeysWithShipmentValues_WhenVerified() {
        // AC-002.2 (BR-02): two shipments with different values, exactly the eleven keys.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        Shipment__c first = newShipment(customer.Id, ORIGINAL);
        first.Delivery_Instructions__c = 'Ring twice';
        Shipment__c second = newShipment(customer.Id, ORIGINAL.addDays(3));
        second.Recipient_Name__c = 'Maria Lopez';
        second.Recipient_Address__c = 'Calle Hidalgo 5, Centro';
        second.Destination_City__c = 'Monterrey';
        second.Recipient_Phone__c = '+52 81 1111 2222';
        List<Fixture> fixtures = insertShipments(new List<Shipment__c>{ first, second },
            new List<String>{ IN_TRANSIT, PICKED_UP }, new List<Integer>{ 0, 1 });

        Test.startTest();
        RecipientDeliveryDetails firstDetails = RecipientDeliveryController.getDeliveryDetails(
            fixtures[0].trackingNumber, POSTAL_CODE, fixtures[0].code).details;
        RecipientDeliveryDetails secondDetails = RecipientDeliveryController.getDeliveryDetails(
            fixtures[1].trackingNumber, POSTAL_CODE, fixtures[1].code).details;
        Test.stopTest();

        Map<String, Object> firstJson = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(firstDetails));
        Map<String, Object> secondJson = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(secondDetails));
        Assert.areEqual(DETAIL_KEYS, firstJson.keySet(), 'The details must have exactly the eleven keys');
        Assert.areEqual(new Map<String, Object>{
            'recipientName' => 'Test Recipient',
            'deliveryAddress' => 'Av. Vallarta 200, Col. Americana, 64000 Guadalajara',
            'contactPhone' => '+52 33 0000 0000',
            'estimatedDelivery' => '2026-12-10',
            'deliveryInstructions' => 'Ring twice',
            'status' => IN_TRANSIT,
            'canReschedule' => true,
            'reschedulesLeft' => 2,
            'rescheduleFrom' => '2026-12-06',
            'rescheduleTo' => '2026-12-17',
            'proofAvailable' => false
        }, firstJson, 'The first shipment\'s values');
        Assert.areEqual(new Map<String, Object>{
            'recipientName' => 'Maria Lopez',
            'deliveryAddress' => 'Calle Hidalgo 5, Centro, 64000 Monterrey',
            'contactPhone' => '+52 81 1111 2222',
            'estimatedDelivery' => '2026-12-13',
            'deliveryInstructions' => null,
            'status' => PICKED_UP,
            'canReschedule' => true,
            'reschedulesLeft' => 1,
            'rescheduleFrom' => '2026-12-06',
            'rescheduleTo' => '2026-12-20',
            'proofAvailable' => false
        }, secondJson, 'The second shipment\'s values');
    }

    @IsTest
    static void shouldContainNoPrivateValue_WhenDetailsAreSerialized() {
        // AC-002.2 (BR-03): no Id, Price__c, Carrier_Cost__c, Internal_Notes__c, Account__c,
        // Recipient_Email__c or hash value in the serialized details or response.
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        Shipment__c shipment = newShipment(customer.Id, ORIGINAL);
        shipment.Price__c = 4321.98;
        shipment.Carrier_Cost__c = 1234.56;
        shipment.Internal_Notes__c = 'Confidential carrier note';
        shipment.Recipient_Email__c = 'private.recipient@example.com';
        Fixture fixture = insertShipments(new List<Shipment__c>{ shipment },
            new List<String>{ IN_TRANSIT }, new List<Integer>{ 0 })[0];
        Shipment__c stored = [
            SELECT Delivery_Access_Code_Hash__c FROM Shipment__c WHERE Id = :fixture.shipmentId WITH SYSTEM_MODE
        ];

        Test.startTest();
        String serialized = JSON.serialize(
            RecipientDeliveryController.getDeliveryDetails(fixture.trackingNumber, POSTAL_CODE, fixture.code));
        Test.stopTest();

        Assert.isTrue(serialized.contains('Test Recipient'), 'The response must carry the details');
        for (String privateValue : new List<String>{
            String.valueOf(fixture.shipmentId), String.valueOf(fixture.shipmentId).left(15), '4321.98', '1234.56',
            'Confidential carrier note', String.valueOf(customer.Id).left(15), 'private.recipient@example.com',
            stored.Delivery_Access_Code_Hash__c, stored.Delivery_Access_Code_Hash__c.split('\\$')[3], fixture.code
        }) {
            Assert.isFalse(serialized.contains(privateValue), 'The response must not contain a private value');
        }
    }

    @IsTest
    static void shouldReportProofAvailable_WhenDeliveredWithProofId() {
        // AC-002.2: proofAvailable only for Delivered with a Proof_Id__c.
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        List<Shipment__c> shipments = new List<Shipment__c>{
            newShipment(customer.Id, ORIGINAL), newShipment(customer.Id, ORIGINAL), newShipment(customer.Id, ORIGINAL)
        };
        List<Fixture> fixtures = insertShipments(shipments,
            new List<String>{ 'Delivered', 'Delivered', IN_TRANSIT }, new List<Integer>{ 0, 0, 0 });
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixtures[0].shipmentId, Proof_Id__c = 'PRF-88231'),
            new Shipment__c(Id = fixtures[2].shipmentId, Proof_Id__c = 'PRF-90417')
        });

        Test.startTest();
        List<Boolean> available = new List<Boolean>();
        for (Fixture fixture : fixtures) {
            available.add(RecipientDeliveryController.getDeliveryDetails(
                fixture.trackingNumber, POSTAL_CODE, fixture.code).details.proofAvailable);
        }
        Test.stopTest();

        Assert.areEqual(new List<Boolean>{ true, false, false }, available,
            'Proof is available only for Delivered with a proof id');
    }

    // ─── AC-002.3: wrong postal code ─────────────────────────────────────

    @IsTest
    static void shouldReturnSharedMessageAndNoDetails_WhenPostalCodeIsWrong() {
        // AC-002.3: a wrong postal code gets exactly "The details do not match this shipment",
        // the same outcome and message as a wrong code.
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        String wrongCode = (fixture.code.startsWith('A') ? 'B' : 'A') + fixture.code.substring(1);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse wrongPostal =
            RecipientDeliveryController.getDeliveryDetails(fixture.trackingNumber, '01000', fixture.code);
        RecipientDeliveryController.DeliveryResponse wrongAccess =
            RecipientDeliveryController.getDeliveryDetails(fixture.trackingNumber, POSTAL_CODE, wrongCode);
        Test.stopTest();

        Assert.areEqual('The details do not match this shipment', wrongPostal.message, 'The exact message');
        Assert.isNull(wrongPostal.details, 'No details');
        Assert.areEqual(wrongAccess.message, wrongPostal.message, 'Same message as a wrong code');
        Assert.areEqual(wrongAccess.outcome, wrongPostal.outcome, 'Same outcome as a wrong code');
    }

    // ─── AC-002.7: the real site guest user ──────────────────────────────

    @IsTest
    static void shouldReturnDetails_WhenGuestCannotReadShipment() {
        // AC-002.7 (P10, P11): the guest reads the details through the controller only.
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        RecipientDeliveryController.DeliveryResponse response;
        Boolean guestCanRead;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            guestCanRead = Schema.SObjectType.Shipment__c.isAccessible();
            response = RecipientDeliveryController.getDeliveryDetails(fixture.trackingNumber, POSTAL_CODE, fixture.code);
        }
        Test.stopTest();

        Assert.isFalse(guestCanRead, 'The guest has no access to Shipment__c');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The guest is verified');
        Assert.areEqual('Test Recipient', response.details.recipientName, 'The guest gets the details');
    }

    @IsTest
    static void shouldReschedule_WhenGuestSendsValidValues() {
        // AC-002.7: the guest reschedules through the controller; only the three fields change.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        Shipment__c before = reload(fixture.shipmentId);
        RecipientDeliveryController.DeliveryResponse response;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            response = reschedule(fixture, '2026-12-14', DOORMAN);
        }
        Test.stopTest();

        Shipment__c after = reload(fixture.shipmentId);
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The guest reschedule is accepted');
        Assert.areEqual(Date.newInstance(2026, 12, 14), after.Estimated_Delivery__c, 'The new date is saved');
        Assert.areEqual(before.Status__c, after.Status__c, 'Status unchanged');
        Assert.areEqual(before.Price__c, after.Price__c, 'Price unchanged');
        Assert.areEqual(before.Recipient_Name__c, after.Recipient_Name__c, 'Recipient unchanged');
        Assert.areEqual(ORIGINAL, after.Original_Estimated_Delivery__c, 'Original estimate unchanged');
    }

    // ─── AC-003.1: a valid reschedule ────────────────────────────────────

    @IsTest
    static void shouldSaveDateInstructionsAndCount_WhenInTransitIsRescheduled() {
        // AC-003.1: In transit, count 0, a valid date and "Leave with the doorman".
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-12', DOORMAN);
        Test.stopTest();

        Shipment__c after = reload(fixture.shipmentId);
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'Accepted');
        Assert.areEqual(Date.newInstance(2026, 12, 12), after.Estimated_Delivery__c, 'Estimated_Delivery__c is the new date');
        Assert.areEqual(DOORMAN, after.Delivery_Instructions__c, 'Delivery_Instructions__c is the new text');
        Assert.areEqual(1, after.Reschedule_Count__c, 'Reschedule_Count__c is 1');
        Assert.areEqual('2026-12-12', response.details.estimatedDelivery, 'The returned details show the new date');
        Assert.areEqual(DOORMAN, response.details.deliveryInstructions, 'The returned details show the new text');
        Assert.areEqual(1, response.details.reschedulesLeft, 'One reschedule left');
    }

    @IsTest
    static void shouldClearInstructions_WhenInstructionsAreBlank() {
        // AC-003.1 (S2): blank instructions clear them.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixture.shipmentId, Delivery_Instructions__c = 'Old text')
        });

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-13', '  ');
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'Accepted');
        Assert.isNull(reload(fixture.shipmentId).Delivery_Instructions__c, 'Blank instructions clear the field');
    }

    @IsTest
    static void shouldReject_WhenInstructionsExceed1000Characters() {
        // AC-003.1 (S2): instructions over 1000 characters are rejected; nothing changes.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        Shipment__c before = reload(fixture.shipmentId);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-13', 'x'.repeat(1001));
        Test.stopTest();

        assertRejectedUnchanged(response, RecipientDeliveryController.INSTRUCTIONS_MESSAGE, before, fixture.shipmentId);
    }

    @IsTest
    static void shouldAccept_WhenInstructionsAreExactly1000Characters() {
        // AC-003.1 (S2): 1000 characters is the limit, accepted.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-13', 'x'.repeat(1000));
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, '1000 characters are accepted');
    }

    // ─── AC-003.2: the window ────────────────────────────────────────────

    @IsTest
    static void shouldReject_WhenNewDateIsToday() {
        // AC-003.2: today T in Mexico City is outside the window.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        Shipment__c before = reload(fixture.shipmentId);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, iso(TODAY_IN_MEXICO), DOORMAN);
        Test.stopTest();

        assertRejectedUnchanged(response, RecipientDeliveryController.WINDOW_MESSAGE, before, fixture.shipmentId);
    }

    @IsTest
    static void shouldReject_WhenNewDateIsOriginalPlusEight() {
        // AC-003.2: D+8 is outside the window.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        Shipment__c before = reload(fixture.shipmentId);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, iso(ORIGINAL.addDays(8)), DOORMAN);
        Test.stopTest();

        assertRejectedUnchanged(response, RecipientDeliveryController.WINDOW_MESSAGE, before, fixture.shipmentId);
    }

    @IsTest
    static void shouldReject_WhenNewDateIsUnparsable() {
        // AC-003.2: unparsable dates (not ISO, impossible day, blank) are rejected.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        Shipment__c before = reload(fixture.shipmentId);

        Test.startTest();
        List<String> messages = new List<String>();
        for (String newDate : new List<String>{ 'next week', '12/12/2026', '2026-12-32', '2026-02-30', '', null }) {
            messages.add(reschedule(fixture, newDate, DOORMAN).message);
        }
        RecipientDeliveryController.DeliveryResponse last = reschedule(fixture, '2026-1-12', DOORMAN);
        Test.stopTest();

        for (String message : messages) {
            Assert.areEqual(RecipientDeliveryController.WINDOW_MESSAGE, message, 'An unparsable date gets the window message');
        }
        assertRejectedUnchanged(last, RecipientDeliveryController.WINDOW_MESSAGE, before, fixture.shipmentId);
    }

    @IsTest
    static void shouldAccept_WhenNewDateIsTomorrow() {
        // AC-003.2: T+1 is the first day of the window.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, iso(TODAY_IN_MEXICO.addDays(1)), DOORMAN);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'T+1 is accepted');
        Assert.areEqual(TODAY_IN_MEXICO.addDays(1), reload(fixture.shipmentId).Estimated_Delivery__c, 'T+1 is saved');
    }

    @IsTest
    static void shouldAccept_WhenNewDateIsOriginalPlusSeven() {
        // AC-003.2: D+7 is the last day of the window.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, iso(ORIGINAL.addDays(7)), DOORMAN);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'D+7 is accepted');
        Assert.areEqual(ORIGINAL.addDays(7), reload(fixture.shipmentId).Estimated_Delivery__c, 'D+7 is saved');
    }

    @IsTest
    static void shouldMeasureFromOriginal_WhenEstimateWasMovedLater() {
        // AC-003.2 (D4): the estimate moved to D+5, the window still ends at D+7.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixture.shipmentId, Estimated_Delivery__c = ORIGINAL.addDays(5))
        });
        Shipment__c before = reload(fixture.shipmentId);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, iso(ORIGINAL.addDays(8)), DOORMAN);
        Test.stopTest();

        assertRejectedUnchanged(response, RecipientDeliveryController.WINDOW_MESSAGE, before, fixture.shipmentId);
    }

    @IsTest
    static void shouldMeasureSecondRescheduleFromOriginal_WhenFirstMovedTheDate() {
        // AC-003.2 (D4): after a first reschedule to D+7, D+8 is still rejected.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse first = reschedule(fixture, iso(ORIGINAL.addDays(7)), DOORMAN);
        Shipment__c afterFirst = reload(fixture.shipmentId);
        RecipientDeliveryController.DeliveryResponse second = reschedule(fixture, iso(ORIGINAL.addDays(8)), DOORMAN);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, first.outcome, 'The first reschedule is accepted');
        Assert.areEqual(iso(ORIGINAL.addDays(7)), first.details.rescheduleTo, 'The window still ends at D+7');
        assertRejectedUnchanged(second, RecipientDeliveryController.WINDOW_MESSAGE, afterFirst, fixture.shipmentId);
    }

    @IsTest
    static void shouldNotOfferAndReject_WhenOriginalEstimateIsEmpty() {
        // AC-003.2: no Original_Estimated_Delivery__c, canReschedule false and rejected.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 0, null);
        Shipment__c before = reload(fixture.shipmentId);

        Test.startTest();
        RecipientDeliveryDetails details = RecipientDeliveryController.getDeliveryDetails(
            fixture.trackingNumber, POSTAL_CODE, fixture.code).details;
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-08', DOORMAN);
        Test.stopTest();

        Assert.isNull(before.Original_Estimated_Delivery__c, 'Fixture: no original estimate');
        Assert.isFalse(details.canReschedule, 'canReschedule is false without an original estimate');
        Assert.isNull(details.rescheduleTo, 'No window without an original estimate');
        assertRejectedUnchanged(response, RecipientDeliveryController.NO_ESTIMATE_MESSAGE, before, fixture.shipmentId);
    }

    @IsTest
    static void shouldNotOffer_WhenWindowHasClosed() {
        // AC-003.2: today is D+7, so tomorrow is past the window.
        RecipientDeliveryController.todayOverride = ORIGINAL.addDays(7);
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);

        Test.startTest();
        RecipientDeliveryDetails details = RecipientDeliveryController.getDeliveryDetails(
            fixture.trackingNumber, POSTAL_CODE, fixture.code).details;
        Test.stopTest();

        Assert.isFalse(details.canReschedule, 'No date fits the window');
    }

    @IsTest
    static void shouldUseMexicoCityDate_WhenNoTodayOverride() {
        // AC-003.2 (BR-06): "today" is the date in America/Mexico_City. SMOKE TEST: with no
        // clock seam it runs at the real instant, so a wrong time zone is caught only in the
        // hours when that zone's date differs from Mexico City's. The expected date is built
        // independently (the zone's UTC offset at this instant), not with the code's expression;
        // the window rules themselves are proven through todayOverride.
        Fixture fixture = insertShipment(IN_TRANSIT, 0, Date.today().addDays(3));
        Datetime instant = Datetime.now();
        Integer offsetSeconds = TimeZone.getTimeZone('America/Mexico_City').getOffset(instant) / 1000;
        Date mexicoToday = instant.addSeconds(offsetSeconds).dateGmt();

        Test.startTest();
        RecipientDeliveryDetails details = RecipientDeliveryController.getDeliveryDetails(
            fixture.trackingNumber, POSTAL_CODE, fixture.code).details;
        Test.stopTest();

        Assert.areEqual(iso(mexicoToday.addDays(1)), details.rescheduleFrom, 'The window starts tomorrow in Mexico City');
    }

    // ─── AC-003.3: statuses ──────────────────────────────────────────────

    @IsTest
    static void shouldRejectWithStatusMessage_WhenStatusIsNotPickedUpOrInTransit() {
        // AC-003.3: Requested, Out for delivery, Delivered and Exception are rejected; nothing changes.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        List<String> statuses = new List<String>{ 'Requested', 'Out for delivery', 'Delivered', 'Exception' };
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (String status : statuses) {
            shipments.add(newShipment(customer.Id, ORIGINAL));
        }
        List<Fixture> fixtures = insertShipments(shipments, statuses, new List<Integer>{ 0, 0, 0, 0 });
        Map<Id, Shipment__c> before = new Map<Id, Shipment__c>();
        for (Fixture fixture : fixtures) {
            before.put(fixture.shipmentId, reload(fixture.shipmentId));
        }

        Test.startTest();
        List<RecipientDeliveryController.DeliveryResponse> responses = new List<RecipientDeliveryController.DeliveryResponse>();
        for (Fixture fixture : fixtures) {
            responses.add(reschedule(fixture, '2026-12-12', DOORMAN));
        }
        Test.stopTest();

        for (Integer i = 0; i < fixtures.size(); i++) {
            assertRejectedUnchanged(responses[i], RecipientDeliveryController.STATUS_MESSAGE,
                before.get(fixtures[i].shipmentId), fixtures[i].shipmentId);
            Assert.isFalse(responses[i].details.canReschedule, statuses[i] + ': canReschedule is false');
        }
    }

    @IsTest
    static void shouldAccept_WhenStatusIsPickedUpOrInTransit() {
        // AC-003.3: Picked up and In transit are accepted.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        List<Fixture> fixtures = insertShipments(
            new List<Shipment__c>{ newShipment(customer.Id, ORIGINAL), newShipment(customer.Id, ORIGINAL) },
            new List<String>{ PICKED_UP, IN_TRANSIT }, new List<Integer>{ 0, 0 });

        Test.startTest();
        String pickedUp = reschedule(fixtures[0], '2026-12-11', DOORMAN).outcome;
        String inTransit = reschedule(fixtures[1], '2026-12-15', 'Call on arrival').outcome;
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, pickedUp, 'Picked up is accepted');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, inTransit, 'In transit is accepted');
        Assert.areEqual(Date.newInstance(2026, 12, 15), reload(fixtures[1].shipmentId).Estimated_Delivery__c,
            'The In transit date is saved');
    }

    // ─── AC-003.4: at most 2 reschedules ─────────────────────────────────

    @IsTest
    static void shouldRejectWithLimitMessage_WhenRescheduledTwice() {
        // AC-003.4: Reschedule_Count__c 2 is rejected; nothing changes.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 2, ORIGINAL);
        Shipment__c before = reload(fixture.shipmentId);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-12', DOORMAN);
        Test.stopTest();

        assertRejectedUnchanged(response, RecipientDeliveryController.LIMIT_MESSAGE, before, fixture.shipmentId);
        Assert.areEqual(0, response.details.reschedulesLeft, 'No reschedule left');
    }

    @IsTest
    static void shouldAcceptAndReachTwo_WhenRescheduledOnce() {
        // AC-003.4: with 1 it is accepted and becomes 2.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, 1, ORIGINAL);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-12', DOORMAN);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'Accepted with 1');
        Assert.areEqual(2, reload(fixture.shipmentId).Reschedule_Count__c, 'The count becomes 2');
        Assert.isFalse(response.details.canReschedule, 'No more reschedules offered');
    }

    @IsTest
    static void shouldAcceptAndReachOne_WhenCountIsNull() {
        // AC-003.4: with null it is accepted and becomes 1.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture fixture = insertShipment(IN_TRANSIT, null, ORIGINAL);

        Test.startTest();
        RecipientDeliveryController.DeliveryResponse response = reschedule(fixture, '2026-12-12', DOORMAN);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'Accepted with null');
        Assert.areEqual(1, reload(fixture.shipmentId).Reschedule_Count__c, 'The count becomes 1');
    }

    // ─── downloadProof (T2) ──────────────────────────────────────────────

    private static final String PROOF_UNAVAILABLE = 'We could not get the proof of delivery, please try again later';
    private static final String PDF_BASE64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4\n%proof\n%%EOF\n'));

    // Answers each proof id with its tracking number and a small PDF (or with a
    // fixed status, or a timeout); records every request and the DML statements
    // made before it.
    private with sharing class ProofMock implements HttpCalloutMock {
        final Map<String, String> trackingByProofId = new Map<String, String>();
        Integer statusCode = 200;
        String pdfBase64 = PDF_BASE64;
        String fixedBody;
        Boolean timeout = false;
        final List<String> endpoints = new List<String>();
        final List<Integer> dmlBeforeCallout = new List<Integer>();

        public HttpResponse respond(HttpRequest request) {
            endpoints.add(request.getEndpoint());
            dmlBeforeCallout.add(Limits.getDmlStatements());
            if (timeout) {
                throw new CalloutException('Read timed out');
            }
            String proofId = request.getEndpoint().substringAfterLast('/');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setStatus(statusCode == 200 ? 'OK' : 'Unauthorized Not Found Server Error');
            response.setBody(fixedBody ?? JSON.serialize(new Map<String, Object>{
                'proofId' => proofId,
                'trackingNumber' => trackingByProofId.get(proofId),
                'signedBy' => 'Signer of ' + proofId,
                'fileName' => proofId + '.pdf',
                'pdfBase64' => pdfBase64
            }));
            return response;
        }
    }

    private static ProofMock setProofMock() {
        ProofMock mock = new ProofMock();
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    // One Delivered shipment with the given proof id.
    private static Fixture insertDelivered(String proofId) {
        Fixture fixture = insertShipment('Delivered', 0, ORIGINAL);
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixture.shipmentId, Proof_Id__c = proofId)
        });
        return fixture;
    }

    private static RecipientDeliveryController.ProofResponse download(Fixture fixture) {
        return RecipientDeliveryController.downloadProof(fixture.trackingNumber, POSTAL_CODE, fixture.code);
    }

    private static String wrongCodeOf(Fixture fixture) {
        return (fixture.code.startsWith('A') ? 'B' : 'A') + fixture.code.substring(1);
    }

    private static Integer storedFiles() {
        return [SELECT COUNT() FROM ContentVersion WITH SYSTEM_MODE]
            + [SELECT COUNT() FROM Attachment WITH SYSTEM_MODE]
            + [SELECT COUNT() FROM Document WITH SYSTEM_MODE];
    }

    private static Recipient_Access_Guard__c guardOf(Id shipmentId) {
        List<Recipient_Access_Guard__c> guards = [
            SELECT Failed_Attempts__c, Locked_Until__c FROM Recipient_Access_Guard__c
            WHERE Shipment__c = :shipmentId WITH SYSTEM_MODE
        ];
        return guards.isEmpty() ? null : guards[0];
    }

    // The response is the AC-002.5 failure, with no proof and no response text.
    private static void assertUnavailable(RecipientDeliveryController.ProofResponse response) {
        Assert.areEqual(RecipientDeliveryController.OUTCOME_UNAVAILABLE, response.outcome, 'The proof is unavailable');
        Assert.areEqual(PROOF_UNAVAILABLE, response.message, 'Exactly the AC-002.5 message');
        Assert.isNull(response.pdfBase64, 'No PDF');
        Assert.isNull(response.fileName, 'No file name');
        Assert.isNull(response.signedBy, 'No signer');
        String serialized = JSON.serialize(response);
        for (String leak : new List<String>{ 'Unauthorized', 'Not Found', 'Server Error', 'timed out', 'Exception' }) {
            Assert.isFalse(serialized.containsIgnoreCase(leak), 'No response or exception text: ' + leak);
        }
    }

    @IsTest
    static void shouldReturnProofs_WhenTwoDeliveredShipmentsAreVerified() {
        // AC-002.4: PRF-88231 and PRF-90417, each answered with its shipment's trackingNumber.
        Account customer = TestDataFactory.insertCustomerAccount(ACCOUNT_NAME);
        List<Fixture> fixtures = insertShipments(
            new List<Shipment__c>{ newShipment(customer.Id, ORIGINAL), newShipment(customer.Id, ORIGINAL) },
            new List<String>{ 'Delivered', 'Delivered' }, new List<Integer>{ 0, 0 });
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixtures[0].shipmentId, Proof_Id__c = 'PRF-88231'),
            new Shipment__c(Id = fixtures[1].shipmentId, Proof_Id__c = 'PRF-90417')
        });
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-88231', fixtures[0].trackingNumber);
        mock.trackingByProofId.put('PRF-90417', fixtures[1].trackingNumber);
        Integer filesBefore = storedFiles();

        Test.startTest();
        RecipientDeliveryController.ProofResponse first = download(fixtures[0]);
        RecipientDeliveryController.ProofResponse second = download(fixtures[1]);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, first.outcome, 'The first proof is returned');
        Assert.areEqual('PRF-88231.pdf', first.fileName, 'The first file name');
        Assert.areEqual('Signer of PRF-88231', first.signedBy, 'The first signer');
        Assert.areEqual(PDF_BASE64, first.pdfBase64, 'The first PDF');
        Assert.isTrue(first.proofAvailable, 'The first proof is available');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, second.outcome, 'The second proof is returned');
        Assert.areEqual('PRF-90417.pdf', second.fileName, 'The second file name');
        Assert.areEqual('Signer of PRF-90417', second.signedBy, 'The second signer');
        Assert.areEqual(new List<String>{
            'callout:EntregaYa_API/proofs/PRF-88231', 'callout:EntregaYa_API/proofs/PRF-90417'
        }, mock.endpoints, 'One GET per proof, through the Named Credential');
        Assert.areEqual(filesBefore, storedFiles(), 'No ContentVersion, Attachment or Document is created');
    }

    @IsTest
    static void shouldNotCallOut_WhenShipmentIsNotDelivered() {
        // AC-002.4: In transit with a Proof_Id__c, no callout and proofAvailable false.
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixture.shipmentId, Proof_Id__c = 'PRF-88231')
        });
        ProofMock mock = setProofMock();

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        Assert.areEqual(0, mock.endpoints.size(), 'No callout');
        Assert.isFalse(response.proofAvailable, 'proofAvailable is false');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_AVAILABLE, response.outcome, 'Not available');
        Assert.areEqual(RecipientDeliveryController.PROOF_NOT_AVAILABLE_MESSAGE, response.message, 'The not available message');
        Assert.isNull(response.pdfBase64, 'No PDF');
    }

    @IsTest
    static void shouldNotCallOut_WhenDeliveredWithoutProofId() {
        // AC-002.4: Delivered without Proof_Id__c, no callout and proofAvailable false.
        Fixture fixture = insertDelivered(null);
        ProofMock mock = setProofMock();

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        Assert.areEqual(0, mock.endpoints.size(), 'No callout');
        Assert.isFalse(response.proofAvailable, 'proofAvailable is false');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_AVAILABLE, response.outcome, 'Not available');
    }

    @IsTest
    static void shouldReturnUnavailable_WhenProofIsAnotherShipments() {
        // AC-002.4 (E7): the response's trackingNumber is another shipment's.
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-88231', 'RC000009999');

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
    }

    @IsTest
    static void shouldReturnUnavailable_WhenBytesAreNotPdf() {
        // AC-002.4: the bytes do not start with %PDF-.
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-88231', fixture.trackingNumber);
        mock.pdfBase64 = EncodingUtil.base64Encode(Blob.valueOf('PK zip archive, not a PDF'));

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
    }

    @IsTest
    static void shouldReturnUnavailable_WhenBodyIsOverTheCap() {
        // AC-002.4: a body of 2,500,001 characters.
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();
        mock.fixedBody = ' '.repeat(ProofOfDeliveryService.MAX_BODY_LENGTH + 1);

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
    }

    @IsTest
    static void shouldReturnUnavailable_WhenEntregaYaAnswers401() {
        // AC-002.5: a wrong key.
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();
        mock.statusCode = 401;
        mock.fixedBody = '{"error":"Unauthorized"}';

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
    }

    @IsTest
    static void shouldReturnUnavailable_WhenEntregaYaAnswers404() {
        // AC-002.5: the proof does not exist.
        Fixture fixture = insertDelivered('PRF-90417');
        ProofMock mock = setProofMock();
        mock.statusCode = 404;
        mock.fixedBody = '{"error":"Not Found"}';

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
    }

    @IsTest
    static void shouldReturnUnavailable_WhenEntregaYaAnswers500() {
        // AC-002.5: the service is unavailable.
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();
        mock.statusCode = 500;
        mock.fixedBody = 'Internal Server Error';

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
    }

    @IsTest
    static void shouldReturnUnavailable_WhenCalloutTimesOut() {
        // AC-002.5: a timeout (CalloutException).
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();
        mock.timeout = true;

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
        Assert.areEqual(1, mock.endpoints.size(), 'The callout was attempted');
    }

    @IsTest
    static void shouldMakeNoDmlBeforeCalloutAndResetCounter_WhenCounterIsNonZero() {
        // AC-002.5 (S3): a verified request makes no DML before the callout; the
        // non-zero counter is reset after it.
        Fixture fixture = insertDelivered('PRF-88231');
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, 3, null)
        });
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-88231', fixture.trackingNumber);

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The proof is returned');
        Assert.areEqual(new List<Integer>{ 0 }, mock.dmlBeforeCallout, 'No DML before the callout');
        Assert.areEqual(0, guardOf(fixture.shipmentId).Failed_Attempts__c, 'The counter is reset after the callout');
    }

    @IsTest
    static void shouldResetCounter_WhenVerifiedCalloutFails() {
        // AC-002.5 (S3): the recipient was verified, so the counter is reset even when EntregaYa fails.
        Fixture fixture = insertDelivered('PRF-90417');
        TestDataFactory.insertRecipientAccessGuards(new List<Recipient_Access_Guard__c>{
            TestDataFactory.newRecipientAccessGuard(fixture.shipmentId, 2, null)
        });
        ProofMock mock = setProofMock();
        mock.statusCode = 500;

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = download(fixture);
        Test.stopTest();

        assertUnavailable(response);
        Assert.areEqual(0, guardOf(fixture.shipmentId).Failed_Attempts__c, 'The counter is reset');
    }

    // ─── AC-002.1b: downloadProof failures ───────────────────────────────

    @IsTest
    static void shouldCountFailureWithoutCallout_WhenDownloadProofCodeIsWrong() {
        // AC-002.1b: a failed downloadProof is counted on the guard and makes no callout.
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();

        Test.startTest();
        RecipientDeliveryController.ProofResponse response = RecipientDeliveryController.downloadProof(
            fixture.trackingNumber, POSTAL_CODE, wrongCodeOf(fixture));
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, response.outcome, 'Not matched');
        Assert.areEqual(RecipientAccess.NOT_MATCHED_MESSAGE, response.message, 'The shared message');
        Assert.areEqual(0, mock.endpoints.size(), 'No callout');
        Assert.areEqual(1, guardOf(fixture.shipmentId).Failed_Attempts__c, 'The failure is counted');
    }

    @IsTest
    static void shouldLockWithoutCallout_WhenFailuresMixDetailsAndDownloadProof() {
        // AC-002.1b: 3 failures through getDeliveryDetails and 2 through downloadProof
        // lock the shipment; the sixth attempt, with the right values, gets the lock
        // message and makes no callout.
        Fixture fixture = insertDelivered('PRF-88231');
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-88231', fixture.trackingNumber);
        String wrongCode = wrongCodeOf(fixture);

        Test.startTest();
        for (Integer i = 0; i < 3; i++) {
            RecipientDeliveryController.getDeliveryDetails(fixture.trackingNumber, POSTAL_CODE, wrongCode);
        }
        Decimal afterDetails = guardOf(fixture.shipmentId).Failed_Attempts__c;
        for (Integer i = 0; i < 2; i++) {
            RecipientDeliveryController.downloadProof(fixture.trackingNumber, POSTAL_CODE, wrongCode);
        }
        RecipientDeliveryController.ProofResponse sixth = download(fixture);
        Test.stopTest();

        Assert.areEqual(3, afterDetails, 'Three failures counted through getDeliveryDetails');
        Assert.isNotNull(guardOf(fixture.shipmentId).Locked_Until__c, 'The fifth failure, through downloadProof, locks');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_LOCKED, sixth.outcome, 'Locked');
        Assert.areEqual(RecipientAccess.LOCKED_MESSAGE, sixth.message, 'The lock message');
        Assert.areEqual(0, mock.endpoints.size(), 'No callout while locked or failing');
    }

    // ─── AC-002.7: the real site guest user ──────────────────────────────

    @IsTest
    static void shouldDownloadProof_WhenGuestCannotReadShipment() {
        // AC-002.7 (P10, P11): the guest downloads through the controller only.
        Fixture fixture = insertDelivered('PRF-90417');
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-90417', fixture.trackingNumber);
        RecipientDeliveryController.ProofResponse response;
        Boolean guestCanRead;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            guestCanRead = Schema.SObjectType.Shipment__c.isAccessible();
            response = download(fixture);
        }
        Test.stopTest();

        Assert.isFalse(guestCanRead, 'The guest has no access to Shipment__c');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, response.outcome, 'The guest gets the proof');
        Assert.areEqual(PDF_BASE64, response.pdfBase64, 'The guest gets the PDF');
        Assert.areEqual(new List<String>{ 'callout:EntregaYa_API/proofs/PRF-90417' }, mock.endpoints, 'One callout');
    }

    @IsTest
    static void shouldThrowGenericAuraHandledException_WhenDownloadProofFailsUnexpectedly() {
        // S2/S3: an unexpected exception becomes a generic AuraHandledException.
        Fixture fixture = insertDelivered('PRF-88231');
        setProofMock();
        RecipientDeliveryController.simulateUnexpectedFailure = true;

        Test.startTest();
        try {
            download(fixture);
            Assert.fail('An unexpected error must be thrown as AuraHandledException');
        } catch (AuraHandledException expected) {
            Assert.areEqual(RecipientDeliveryController.GENERIC_ERROR_MESSAGE, expected.getMessage(), 'A generic message');
        }
        Test.stopTest();
    }

    // ─── Unexpected errors ───────────────────────────────────────────────

    @IsTest
    static void shouldThrowGenericAuraHandledException_WhenUnexpectedErrorOccurs() {
        // AC-002.2 (BR-03: no internal value reaches the recipient), per the S2 rule that an
        // unexpected exception becomes a generic AuraHandledException with no internal text.
        Fixture fixture = insertShipment(IN_TRANSIT, 0, ORIGINAL);
        RecipientDeliveryController.simulateUnexpectedFailure = true;

        Test.startTest();
        try {
            RecipientDeliveryController.getDeliveryDetails(fixture.trackingNumber, POSTAL_CODE, fixture.code);
            Assert.fail('An unexpected error must be thrown as AuraHandledException');
        } catch (AuraHandledException expected) {
            Assert.areEqual(RecipientDeliveryController.GENERIC_ERROR_MESSAGE, expected.getMessage(), 'A generic message');
        }
        Test.stopTest();
    }
}
