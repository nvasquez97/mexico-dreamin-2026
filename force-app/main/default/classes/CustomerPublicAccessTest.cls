/**
 * @description A logged-in customer on the public site (odd/tasks/
 *              bug-customer-public-tracking.md, S1): the seeded customer Ana
 *              López (Customer Community, UserType CspLitePortal) runs public
 *              tracking and the recipient flow exactly like the site guest, with
 *              no extra data and the same verification. AC-BUG.1 (BR-01: the
 *              same search JSON as the guest, the seven BR-01 keys, for her own
 *              and for Marta Ruiz's shipment), AC-BUG.2 (REQ-002/003: details,
 *              reschedule through ShipmentTriggerHandler.beforeUpdate and the
 *              proof with a mocked callout, on a shipment of Marta's account),
 *              AC-BUG.4 (X16, BR-02/G9: a wrong access code gets NOT_MATCHED and
 *              no recipient-owned value, on her own shipment as on another
 *              account's; the per-pair lock after 5 failures holds for the right
 *              code too) and AC-BUG.5 (P2, X11: Ana cannot query the guard row
 *              her failures created and owns; the daily purge, run by the
 *              admin, still deletes such rows). Apex tests do not enforce Apex
 *              class access on direct calls (B1): the grant itself is proven by
 *              scripts/checks/customer-access-check.sh against the org
 *              (AC-BUG.3). No portal user is inserted (req-005 F7): the seeded
 *              users are queried. Each test inserts its own shipments: the clear
 *              access code exists only in the transaction that inserts it.
 */
@IsTest
private with sharing class CustomerPublicAccessTest {

    private static final String TRACKING_MODE = 'TRACKING_NUMBER';
    private static final String CUSTOMER_USER_TYPE = 'CspLitePortal';
    // TestDataFactory.newShipment's destination postal code.
    private static final String POSTAL_CODE = '44160';
    private static final String OTHER_POSTAL_CODE = '99999';
    private static final Date ORIGINAL = Date.newInstance(2026, 12, 10);
    private static final Date TODAY_IN_MEXICO = Date.newInstance(2026, 12, 5);
    private static final String IN_TRANSIT = 'In transit';
    private static final String DELIVERED = 'Delivered';
    private static final Set<String> BR01_KEYS = new Set<String>{
        'trackingNumber', 'status', 'originCity', 'destinationCity', 'lastLocation', 'lastUpdate', 'estimatedDelivery'
    };
    private static final String PDF_BASE64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4\n%proof\n%%EOF\n'));
    // The recipient-owned values of Ana's own shipment (BR-02, G7): never returned on a failure.
    private static final String OWN_ADDRESS = 'Calle Privada 7, Col. Roma';
    private static final String OWN_PHONE = '+52 55 9999 0001';
    private static final String OWN_EMAIL = 'own.recipient@example.com';
    private static final String OWN_INSTRUCTIONS = 'Leave it at the back door';
    private static final Integer MAX_FAILED_ATTEMPTS = 5;
    private static final Integer PURGE_BATCH_SIZE = 2000;

    // A saved shipment with its tracking number and its clear access code.
    private with sharing class Fixture {
        Id shipmentId;
        String trackingNumber;
        String code;
    }

    // Answers each proof id with its tracking number and a small PDF; records every endpoint.
    private with sharing class ProofMock implements HttpCalloutMock {
        final Map<String, String> trackingByProofId = new Map<String, String>();
        final List<String> endpoints = new List<String>();

        /**
         * @description Answers a proof request with a small PDF.
         * @param request the GET callout:EntregaYa_API/proofs/{proofId} request
         * @return a 200 response with the proof JSON
         */
        public HttpResponse respond(HttpRequest request) {
            endpoints.add(request.getEndpoint());
            String proofId = request.getEndpoint().substringAfterLast('/');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setBody(JSON.serialize(new Map<String, Object>{
                'proofId' => proofId,
                'trackingNumber' => trackingByProofId.get(proofId),
                'signedBy' => 'Signer of ' + proofId,
                'fileName' => proofId + '.pdf',
                'pdfBase64' => PDF_BASE64
            }));
            return response;
        }
    }

    // ─── Users and data ──────────────────────────────────────────────────

    private static User ana() {
        return TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
    }

    private static Id anaAccountId() {
        return TestDataFactory.seededCustomerAccountId(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
    }

    private static Id martaAccountId() {
        return TestDataFactory.seededCustomerAccountId(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
    }

    private static Shipment__c newDelivery(Id accountId, String recipientName) {
        Shipment__c shipment = TestDataFactory.newShipment(accountId);
        shipment.Recipient_Name__c = recipientName;
        shipment.Estimated_Delivery__c = ORIGINAL;
        return shipment;
    }

    // Ana's own shipment (her account is the sender) with distinctive recipient-owned values.
    private static Shipment__c newOwnDelivery() {
        Shipment__c shipment = newDelivery(anaAccountId(), 'Own Recipient');
        shipment.Recipient_Address__c = OWN_ADDRESS;
        shipment.Recipient_Phone__c = OWN_PHONE;
        shipment.Recipient_Email__c = OWN_EMAIL;
        shipment.Delivery_Instructions__c = OWN_INSTRUCTIONS;
        return shipment;
    }

    // Inserts the shipments as the admin, then sets the status (the trigger fixes it on insert).
    private static List<Fixture> insertShipments(List<Shipment__c> shipments, String status) {
        Map<Id, String> codes = TestDataFactory.insertShipmentsWithCodes(shipments);
        List<Shipment__c> changes = new List<Shipment__c>();
        for (Shipment__c shipment : shipments) {
            changes.add(new Shipment__c(Id = shipment.Id, Status__c = status, Reschedule_Count__c = 0));
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

    private static Fixture insertShipment(Shipment__c shipment, String status) {
        return insertShipments(new List<Shipment__c>{ shipment }, status)[0];
    }

    // A Delivered shipment with the given proof id.
    private static Fixture insertDelivered(Shipment__c shipment, String proofId) {
        Fixture fixture = insertShipment(shipment, DELIVERED);
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixture.shipmentId, Proof_Id__c = proofId)
        });
        return fixture;
    }

    // A shipment with the BR-01 facts set, for tracking; its last location is "Hub <city>".
    private static Fixture insertTracked(Id accountId, String destinationCity, Datetime lastUpdate) {
        String lastLocation = 'Hub ' + destinationCity;
        Shipment__c shipment = newDelivery(accountId, 'Tracked Recipient');
        shipment.Destination_City__c = destinationCity;
        Fixture fixture = insertShipment(shipment, IN_TRANSIT);
        TestDataFactory.updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = fixture.shipmentId, Last_Location__c = lastLocation, Last_Update__c = lastUpdate)
        });
        return fixture;
    }

    private static Shipment__c reload(Id shipmentId) {
        return [
            SELECT Estimated_Delivery__c, Original_Estimated_Delivery__c, Delivery_Instructions__c,
                Reschedule_Count__c, Status__c, Delivery_Access_Code_Hash__c, LastModifiedById
            FROM Shipment__c WHERE Id = :shipmentId WITH SYSTEM_MODE
        ];
    }

    private static String wrongCodeOf(Fixture fixture) {
        return (fixture.code.startsWith('A') ? 'B' : 'A') + fixture.code.substring(1);
    }

    private static ProofMock setProofMock() {
        ProofMock mock = new ProofMock();
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    private static Recipient_Access_Guard__c guardOfPair(Id shipmentId, String typedPostalCode) {
        return [
            SELECT Id, OwnerId, Failed_Attempts__c, Locked_Until__c FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :TestDataFactory.recipientAccessGuardKey(shipmentId, typedPostalCode)
            WITH SYSTEM_MODE
        ];
    }

    private static Map<String, Object> parse(String serialized) {
        return (Map<String, Object>) JSON.deserializeUntyped(serialized);
    }

    // The serialized response contains none of the recipient-owned values of Ana's own shipment.
    private static void assertNoRecipientOwnedValue(String serialized) {
        for (String privateValue : new List<String>{ OWN_ADDRESS, OWN_PHONE, OWN_EMAIL, OWN_INSTRUCTIONS }) {
            Assert.isFalse(serialized.contains(privateValue), 'A failed verification returns no recipient-owned value: ' + privateValue);
        }
    }

    private static void assertNotMatched(String outcome, String message) {
        Assert.areEqual(RecipientDeliveryController.OUTCOME_NOT_MATCHED, outcome, 'A wrong access code is NOT_MATCHED');
        Assert.areEqual(RecipientAccess.NOT_MATCHED_MESSAGE, message, 'The shared failure message');
    }

    // ─── AC-BUG.1: public tracking, the same JSON as the guest ────────────

    // Runs the same search as the site guest and as Ana; asserts the JSON is identical
    // and holds exactly the BR-01 keys of the one shipment.
    private static Map<String, Object> assertSameSearchJsonAsGuest(String trackingNumber) {
        List<String> values = new List<String>{ trackingNumber };
        String guestJson;
        String anaJson;
        String anaUserType;
        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            guestJson = JSON.serialize(PublicTrackingController.search(TRACKING_MODE, values));
        }
        System.runAs(ana()) {
            anaUserType = UserInfo.getUserType();
            anaJson = JSON.serialize(PublicTrackingController.search(TRACKING_MODE, values));
        }
        Test.stopTest();
        Assert.areEqual(CUSTOMER_USER_TYPE, anaUserType, 'Ana is a logged-in customer (CspLitePortal)');
        Assert.areEqual(guestJson, anaJson, 'Ana gets exactly the JSON the site guest gets');
        Map<String, Object> result = parse(anaJson);
        List<Object> results = (List<Object>) result.get('results');
        Assert.areEqual(1, results.size(), 'One shipment found');
        Assert.areEqual(0, ((List<Object>) result.get('notFound')).size(), 'Nothing missing');
        Map<String, Object> shipment = (Map<String, Object>) results[0];
        Assert.areEqual(BR01_KEYS, shipment.keySet(), 'Exactly the seven BR-01 keys, nothing else');
        return shipment;
    }

    @IsTest
    static void anaGetsTheGuestTrackingJsonForHerOwnShipment() {
        // AC-BUG.1 (BR-01): a tracking number of Ana's own account.
        Fixture own = insertTracked(anaAccountId(), 'Monterrey', Datetime.newInstanceGmt(2026, 12, 1, 18, 30, 0));

        Map<String, Object> shipment = assertSameSearchJsonAsGuest(own.trackingNumber);

        Assert.areEqual(own.trackingNumber, shipment.get('trackingNumber'), 'Her tracking number');
        Assert.areEqual('Monterrey', shipment.get('destinationCity'), 'Her destination city');
        Assert.areEqual('Hub Monterrey', shipment.get('lastLocation'), 'Her last location');
        Assert.areEqual('2026-12-01 12:30', shipment.get('lastUpdate'), 'Her last update in Mexico City');
        Assert.areEqual(IN_TRANSIT, shipment.get('status'), 'Her status');
    }

    @IsTest
    static void anaGetsTheGuestTrackingJsonForMartasShipment() {
        // AC-BUG.1 (BR-01): a tracking number of Marta's account, which Ana cannot read by sharing.
        Fixture martas = insertTracked(martaAccountId(), 'Puebla', Datetime.newInstanceGmt(2026, 12, 2, 20, 15, 0));

        Map<String, Object> shipment = assertSameSearchJsonAsGuest(martas.trackingNumber);

        Assert.areEqual(martas.trackingNumber, shipment.get('trackingNumber'), 'Marta\'s tracking number');
        Assert.areEqual('Puebla', shipment.get('destinationCity'), 'Marta\'s destination city');
        Assert.areEqual('Hub Puebla', shipment.get('lastLocation'), 'Marta\'s last location');
        Assert.areEqual('2026-12-02 14:15', shipment.get('lastUpdate'), 'Marta\'s last update in Mexico City');
        Assert.areEqual('2026-12-10', shipment.get('estimatedDelivery'), 'Marta\'s estimated delivery');
    }

    // ─── AC-BUG.2: the recipient flow on another account's shipment ───────

    @IsTest
    static void anaGetsTheGuestDetailsOfMartasShipments() {
        // AC-BUG.2 (REQ-002): Ana holds the three values of two shipments of Marta's account.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        List<Fixture> fixtures = insertShipments(new List<Shipment__c>{
            newDelivery(martaAccountId(), 'Laura Gomez'), newDelivery(martaAccountId(), 'Pedro Ruiz')
        }, IN_TRANSIT);
        String guestJson;
        RecipientDeliveryController.DeliveryResponse first;
        RecipientDeliveryController.DeliveryResponse second;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            guestJson = JSON.serialize(RecipientDeliveryController.getDeliveryDetails(
                fixtures[0].trackingNumber, POSTAL_CODE, fixtures[0].code));
        }
        System.runAs(ana()) {
            first = RecipientDeliveryController.getDeliveryDetails(fixtures[0].trackingNumber, POSTAL_CODE, fixtures[0].code);
            second = RecipientDeliveryController.getDeliveryDetails(fixtures[1].trackingNumber, POSTAL_CODE, fixtures[1].code);
        }
        Test.stopTest();

        Assert.areEqual(guestJson, JSON.serialize(first), 'Ana gets exactly the guest\'s response');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, first.outcome, 'Ana is verified on the first');
        Assert.areEqual('Laura Gomez', first.details.recipientName, 'The first shipment\'s recipient');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, second.outcome, 'Ana is verified on the second');
        Assert.areEqual('Pedro Ruiz', second.details.recipientName, 'The second shipment\'s recipient');
    }

    @IsTest
    static void anaReschedulesExactlyLikeTheGuest() {
        // AC-BUG.2 (REQ-003): the guest and Ana reschedule twin shipments of Marta's account the same way.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        List<Fixture> twins = insertShipments(new List<Shipment__c>{
            newDelivery(martaAccountId(), 'Twin Recipient'), newDelivery(martaAccountId(), 'Twin Recipient')
        }, IN_TRANSIT);
        String guestJson;
        String anaJson;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            guestJson = JSON.serialize(RecipientDeliveryController.rescheduleDelivery(
                twins[0].trackingNumber, POSTAL_CODE, twins[0].code, '2026-12-14', 'Ring twice'));
        }
        System.runAs(ana()) {
            anaJson = JSON.serialize(RecipientDeliveryController.rescheduleDelivery(
                twins[1].trackingNumber, POSTAL_CODE, twins[1].code, '2026-12-14', 'Ring twice'));
        }
        Test.stopTest();

        Assert.areEqual(guestJson, anaJson, 'Ana\'s reschedule answers exactly like the guest\'s');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, parse(anaJson).get('outcome'), 'Ana\'s reschedule is accepted');
        Shipment__c guests = reload(twins[0].shipmentId);
        Shipment__c anas = reload(twins[1].shipmentId);
        Assert.areEqual(guests.Estimated_Delivery__c, anas.Estimated_Delivery__c, 'The same date is saved');
        Assert.areEqual(guests.Delivery_Instructions__c, anas.Delivery_Instructions__c, 'The same instructions are saved');
        Assert.areEqual(guests.Reschedule_Count__c, anas.Reschedule_Count__c, 'The same count is saved');
    }

    @IsTest
    static void anaReschedulesMartasShipmentsThroughTheTrigger() {
        // AC-BUG.2 (REQ-003): the update by a CspLitePortal user passes ShipmentTriggerHandler.beforeUpdate.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        List<Fixture> fixtures = insertShipments(new List<Shipment__c>{
            newDelivery(martaAccountId(), 'Laura Gomez'), newDelivery(martaAccountId(), 'Pedro Ruiz')
        }, IN_TRANSIT);
        String hashBefore = reload(fixtures[0].shipmentId).Delivery_Access_Code_Hash__c;
        User customer = ana();
        RecipientDeliveryController.DeliveryResponse first;
        RecipientDeliveryController.DeliveryResponse second;

        Test.startTest();
        System.runAs(customer) {
            first = RecipientDeliveryController.rescheduleDelivery(
                fixtures[0].trackingNumber, POSTAL_CODE, fixtures[0].code, '2026-12-12', 'Leave with the doorman');
            second = RecipientDeliveryController.rescheduleDelivery(
                fixtures[1].trackingNumber, POSTAL_CODE, fixtures[1].code, '2026-12-16', null);
        }
        Test.stopTest();

        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, first.outcome, 'The first reschedule is accepted');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, second.outcome, 'The second reschedule is accepted');
        Shipment__c firstSaved = reload(fixtures[0].shipmentId);
        Shipment__c secondSaved = reload(fixtures[1].shipmentId);
        Assert.areEqual(customer.Id, firstSaved.LastModifiedById, 'The update ran as Ana, through the trigger');
        Assert.areEqual(Date.newInstance(2026, 12, 12), firstSaved.Estimated_Delivery__c, 'The first new date');
        Assert.areEqual('Leave with the doorman', firstSaved.Delivery_Instructions__c, 'The first instructions');
        Assert.areEqual(1, firstSaved.Reschedule_Count__c, 'The first reschedule is counted');
        Assert.areEqual(ORIGINAL, firstSaved.Original_Estimated_Delivery__c, 'The trigger keeps the original estimate');
        Assert.areEqual(hashBefore, firstSaved.Delivery_Access_Code_Hash__c, 'The trigger keeps the hash');
        Assert.areEqual(Date.newInstance(2026, 12, 16), secondSaved.Estimated_Delivery__c, 'The second new date');
        Assert.isNull(secondSaved.Delivery_Instructions__c, 'Blank instructions clear them');
        Assert.areEqual(1, secondSaved.Reschedule_Count__c, 'The second reschedule is counted');
    }

    @IsTest
    static void anaDownloadsTheProofOfMartasShipmentsLikeTheGuest() {
        // AC-BUG.2 (REQ-002): the proof of two Delivered shipments of Marta's account, mocked callout.
        Fixture first = insertDelivered(newDelivery(martaAccountId(), 'Laura Gomez'), 'PRF-88231');
        Fixture second = insertDelivered(newDelivery(martaAccountId(), 'Pedro Ruiz'), 'PRF-90417');
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-88231', first.trackingNumber);
        mock.trackingByProofId.put('PRF-90417', second.trackingNumber);
        String guestJson;
        RecipientDeliveryController.ProofResponse anaFirst;
        RecipientDeliveryController.ProofResponse anaSecond;

        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            guestJson = JSON.serialize(RecipientDeliveryController.downloadProof(first.trackingNumber, POSTAL_CODE, first.code));
        }
        System.runAs(ana()) {
            anaFirst = RecipientDeliveryController.downloadProof(first.trackingNumber, POSTAL_CODE, first.code);
            anaSecond = RecipientDeliveryController.downloadProof(second.trackingNumber, POSTAL_CODE, second.code);
        }
        Test.stopTest();

        Assert.areEqual(guestJson, JSON.serialize(anaFirst), 'Ana gets exactly the guest\'s proof response');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, anaFirst.outcome, 'Ana gets the first proof');
        Assert.areEqual('PRF-88231.pdf', anaFirst.fileName, 'The first proof file');
        Assert.areEqual(PDF_BASE64, anaFirst.pdfBase64, 'The first PDF');
        Assert.areEqual(RecipientDeliveryController.OUTCOME_SUCCESS, anaSecond.outcome, 'Ana gets the second proof');
        Assert.areEqual('Signer of PRF-90417', anaSecond.signedBy, 'The second proof signer');
        Assert.areEqual(new List<String>{
            'callout:EntregaYa_API/proofs/PRF-88231', 'callout:EntregaYa_API/proofs/PRF-88231',
            'callout:EntregaYa_API/proofs/PRF-90417'
        }, mock.endpoints, 'One callout per download');
    }

    // ─── AC-BUG.4: a wrong code, on her own shipment and on another ──────

    @IsTest
    static void anaGetsNoDetailsOfHerOwnShipmentWithAWrongCode() {
        // AC-BUG.4 (X16, BR-02/G9): Ana is the sender; her tracking number and postal code are not enough.
        Fixture own = insertShipment(newOwnDelivery(), IN_TRANSIT);
        RecipientDeliveryController.DeliveryResponse response;

        Test.startTest();
        System.runAs(ana()) {
            response = RecipientDeliveryController.getDeliveryDetails(own.trackingNumber, POSTAL_CODE, wrongCodeOf(own));
        }
        Test.stopTest();

        assertNotMatched(response.outcome, response.message);
        Assert.isNull(response.details, 'No details without the access code');
        assertNoRecipientOwnedValue(JSON.serialize(response));
    }

    @IsTest
    static void anaCannotRescheduleHerOwnShipmentWithAWrongCode() {
        // AC-BUG.4 (X16, BR-02/G9): the sender cannot reschedule without the access code.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture own = insertShipment(newOwnDelivery(), IN_TRANSIT);
        RecipientDeliveryController.DeliveryResponse response;

        Test.startTest();
        System.runAs(ana()) {
            response = RecipientDeliveryController.rescheduleDelivery(
                own.trackingNumber, POSTAL_CODE, wrongCodeOf(own), '2026-12-14', 'Changed by the sender');
        }
        Test.stopTest();

        assertNotMatched(response.outcome, response.message);
        Assert.isNull(response.details, 'No details without the access code');
        assertNoRecipientOwnedValue(JSON.serialize(response));
        Shipment__c after = reload(own.shipmentId);
        Assert.areEqual(ORIGINAL, after.Estimated_Delivery__c, 'The date does not change');
        Assert.areEqual(OWN_INSTRUCTIONS, after.Delivery_Instructions__c, 'The instructions do not change');
        Assert.areEqual(0, after.Reschedule_Count__c, 'Nothing is counted');
    }

    @IsTest
    static void anaGetsNoProofOfHerOwnShipmentWithAWrongCode() {
        // AC-BUG.4 (X16, BR-02/G9): no proof and no callout for the sender without the access code.
        Fixture own = insertDelivered(newOwnDelivery(), 'PRF-55001');
        ProofMock mock = setProofMock();
        mock.trackingByProofId.put('PRF-55001', own.trackingNumber);
        RecipientDeliveryController.ProofResponse response;

        Test.startTest();
        System.runAs(ana()) {
            response = RecipientDeliveryController.downloadProof(own.trackingNumber, POSTAL_CODE, wrongCodeOf(own));
        }
        Test.stopTest();

        assertNotMatched(response.outcome, response.message);
        Assert.isNull(response.pdfBase64, 'No PDF without the access code');
        Assert.areEqual(0, mock.endpoints.size(), 'No callout without the access code');
        assertNoRecipientOwnedValue(JSON.serialize(response));
    }

    @IsTest
    static void anaGetsNotMatchedOnMartasShipmentWithAWrongCode() {
        // AC-BUG.4 (X16): a wrong code on another account's shipment, on each of the three calls.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture martas = insertShipment(newDelivery(martaAccountId(), 'Laura Gomez'), IN_TRANSIT);
        ProofMock mock = setProofMock();
        String wrong = wrongCodeOf(martas);
        RecipientDeliveryController.DeliveryResponse details;
        RecipientDeliveryController.DeliveryResponse rescheduled;
        RecipientDeliveryController.ProofResponse proof;

        Test.startTest();
        System.runAs(ana()) {
            details = RecipientDeliveryController.getDeliveryDetails(martas.trackingNumber, POSTAL_CODE, wrong);
            rescheduled = RecipientDeliveryController.rescheduleDelivery(martas.trackingNumber, POSTAL_CODE, wrong, '2026-12-14', null);
            proof = RecipientDeliveryController.downloadProof(martas.trackingNumber, POSTAL_CODE, wrong);
        }
        Test.stopTest();

        assertNotMatched(details.outcome, details.message);
        Assert.isNull(details.details, 'No details');
        assertNotMatched(rescheduled.outcome, rescheduled.message);
        Assert.isNull(rescheduled.details, 'No details after a refused reschedule');
        assertNotMatched(proof.outcome, proof.message);
        Assert.areEqual(0, mock.endpoints.size(), 'No callout');
        Assert.areEqual(0, reload(martas.shipmentId).Reschedule_Count__c, 'Nothing is rescheduled');
    }

    @IsTest
    static void anaIsLockedAfterFiveWrongCodesEvenWithTheRightCode() {
        // AC-BUG.4 (X16, per-pair limit): 5 wrong codes, then LOCKED, also for the right code.
        RecipientDeliveryController.todayOverride = TODAY_IN_MEXICO;
        Fixture martas = insertShipment(newDelivery(martaAccountId(), 'Laura Gomez'), IN_TRANSIT);
        ProofMock mock = setProofMock();
        String wrong = wrongCodeOf(martas);
        List<String> wrongOutcomes = new List<String>();
        String afterLockWrong;
        String afterLockRightDetails;
        String afterLockRightReschedule;
        String afterLockRightProof;

        Test.startTest();
        System.runAs(ana()) {
            for (Integer attempt = 0; attempt < MAX_FAILED_ATTEMPTS; attempt++) {
                wrongOutcomes.add(RecipientDeliveryController.getDeliveryDetails(martas.trackingNumber, POSTAL_CODE, wrong).outcome);
            }
            afterLockWrong = RecipientDeliveryController.getDeliveryDetails(martas.trackingNumber, POSTAL_CODE, wrong).outcome;
            afterLockRightDetails = RecipientDeliveryController.getDeliveryDetails(
                martas.trackingNumber, POSTAL_CODE, martas.code).outcome;
            afterLockRightReschedule = RecipientDeliveryController.rescheduleDelivery(
                martas.trackingNumber, POSTAL_CODE, martas.code, '2026-12-14', null).outcome;
            afterLockRightProof = RecipientDeliveryController.downloadProof(martas.trackingNumber, POSTAL_CODE, martas.code).outcome;
        }
        Test.stopTest();

        String notMatched = RecipientDeliveryController.OUTCOME_NOT_MATCHED;
        String locked = RecipientDeliveryController.OUTCOME_LOCKED;
        Assert.areEqual(new List<String>{ notMatched, notMatched, notMatched, notMatched, notMatched }, wrongOutcomes,
            'The five wrong codes are NOT_MATCHED');
        Assert.areEqual(locked, afterLockWrong, 'A sixth wrong code is LOCKED');
        Assert.areEqual(locked, afterLockRightDetails, 'The right code is LOCKED for details');
        Assert.areEqual(locked, afterLockRightReschedule, 'The right code is LOCKED for a reschedule');
        Assert.areEqual(locked, afterLockRightProof, 'The right code is LOCKED for the proof');
        Assert.areEqual(0, mock.endpoints.size(), 'No callout while locked');
        Assert.areEqual(MAX_FAILED_ATTEMPTS, guardOfPair(martas.shipmentId, POSTAL_CODE).Failed_Attempts__c, 'The pair holds 5 failures');
    }

    // ─── AC-BUG.5: the guard rows Ana's failures create ──────────────────

    @IsTest
    static void anaCannotQueryTheGuardRowHerFailureCreated() {
        // AC-BUG.5 (P2, X11, B2): the guard row is owned by Ana, yet she has no object permission on it.
        Fixture martas = insertShipment(newDelivery(martaAccountId(), 'Laura Gomez'), IN_TRANSIT);
        User customer = ana();
        Exception refusal;

        Test.startTest();
        System.runAs(customer) {
            RecipientDeliveryController.getDeliveryDetails(martas.trackingNumber, POSTAL_CODE, wrongCodeOf(martas));
            try {
                List<Recipient_Access_Guard__c> visible = [SELECT Id FROM Recipient_Access_Guard__c WITH USER_MODE];
                Assert.fail('Ana must not query Recipient_Access_Guard__c; she saw ' + visible.size() + ' row(s)');
            } catch (QueryException refused) {
                refusal = refused;
            }
        }
        Test.stopTest();

        Assert.areEqual(customer.Id, guardOfPair(martas.shipmentId, POSTAL_CODE).OwnerId, 'Ana owns the guard row of her failure');
        Assert.isNotNull(refusal, 'The user-mode query is refused');
    }

    @IsTest
    static void purgeDeletesExpiredGuardRowsOwnedByAna() {
        // AC-BUG.5 (P2, B2): the admin's daily purge deletes Ana's stale counter row and her expired lock.
        Fixture martas = insertShipment(newDelivery(martaAccountId(), 'Laura Gomez'), IN_TRANSIT);
        User customer = ana();
        System.runAs(customer) {
            RecipientDeliveryController.getDeliveryDetails(martas.trackingNumber, POSTAL_CODE, wrongCodeOf(martas));
            for (Integer attempt = 0; attempt < MAX_FAILED_ATTEMPTS; attempt++) {
                RecipientDeliveryController.getDeliveryDetails(martas.trackingNumber, OTHER_POSTAL_CODE, martas.code);
            }
        }
        Recipient_Access_Guard__c counter = guardOfPair(martas.shipmentId, POSTAL_CODE);
        Recipient_Access_Guard__c lock = guardOfPair(martas.shipmentId, OTHER_POSTAL_CODE);
        Assert.areEqual(customer.Id, counter.OwnerId, 'Ana owns the counter row');
        Assert.areEqual(customer.Id, lock.OwnerId, 'Ana owns the locked row');
        Assert.isNotNull(lock.Locked_Until__c, 'The other pair is locked');

        Test.startTest();
        Database.executeBatch(new RecipientAccessGuardPurge(Datetime.now().addDays(2)), PURGE_BATCH_SIZE);
        Test.stopTest();

        Set<Id> guardIds = new Set<Id>{ counter.Id, lock.Id };
        Assert.areEqual(0, [SELECT COUNT() FROM Recipient_Access_Guard__c WHERE Id IN :guardIds WITH SYSTEM_MODE],
            'The purge deletes both stale rows owned by Ana');
    }
}
