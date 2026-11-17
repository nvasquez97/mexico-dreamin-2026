/**
 * @description Proves EntregaYaStatusService (req-004 S1): AC-004.2 (what an
 *              update saves), AC-004.4 (stale and equal timestamps ignored),
 *              AC-004.3 validation part (closed error codes, fixed messages),
 *              B5 (future guard), B7 (lock and unexpected errors mapped, never
 *              rethrown) and AC-004.9 (a direct update by the integration user is
 *              refused, the same change through the service is applied).
 *              Every call runs as the EntregaYa integration user (B8, reused or
 *              created by TestDataFactory) in System.runAs, so its permission set,
 *              FLS and the group share apply. Criteria sharing rules are not
 *              evaluated in Apex tests (A10): setup mirrors the deployed rule with
 *              manual Edit shares to the RutaCargo_EntregaYa_Integration group.
 *              The service clock is fixed at 2026-11-22T00:00:00Z so the
 *              AC timestamps of 2026-11-20 and 2026-11-21 are in the past.
 */
@IsTest
private with sharing class EntregaYaStatusServiceTest {

    private static final String INTEGRATION_KEY = 'rceysvc';
    private static final String CUSTOMER_NAME = 'EntregaYa Service Customer';
    private static final Integer SHIPMENT_COUNT = 4;
    private static final Datetime FIXED_NOW = Datetime.newInstanceGmt(2026, 11, 22, 0, 0, 0);
    // 2026-11-20T10:00:00-06:00 as an instant
    private static final Datetime PREVIOUS_UPDATE = Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0);
    private static final String PREVIOUS_STATUS = 'In transit';
    private static final String PREVIOUS_LOCATION = 'Queretaro, QRO';
    private static final String DIRECT_UPDATE_MESSAGE = 'Status updates from EntregaYa must use the status service.';

    // ─── Setup and helpers ────────────────────────────────────────────────

    // SECURITY-JUSTIFICATION: the running test admin has no field permissions on
    // the RutaCargo custom fields (at API 67 DML and SOQL default to user mode),
    // so the fixture is written and read back in system mode. Scope: setup DML
    // and verification reads of this test class only. Compensating control: every
    // call under test runs inside System.runAs as the integration user, and the
    // service itself runs in user mode. (pending owner approval, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    private static void updateAsSystem(List<SObject> records) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
    }

    @TestSetup
    static void setup() {
        TestDataFactory.insertEntregaYaIntegrationUser(INTEGRATION_KEY);
        Account customer = TestDataFactory.newCustomerAccount(CUSTOMER_NAME);
        insertAsSystem(new List<Account>{ customer });
        List<Shipment__c> shipments = TestDataFactory.newShipments(customer.Id, SHIPMENT_COUNT);
        insertAsSystem(shipments);
        TestDataFactory.insertShipmentGroupShares(shipments, TestDataFactory.ENTREGAYA_GROUP);
    }

    private static User integrationUser() {
        return [
            SELECT Id FROM User
            WHERE IsActive = true AND Profile.Name = :TestDataFactory.INTEGRATION_PROFILE_NAME
                AND Id IN (SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = :TestDataFactory.ENTREGAYA_GROUP)
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    private static List<Shipment__c> shipments() {
        return [
            SELECT Id, Name, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c
            FROM Shipment__c
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :SHIPMENT_COUNT
        ];
    }

    private static Shipment__c shipment(Id shipmentId) {
        return [
            SELECT Id, Name, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c
            FROM Shipment__c
            WHERE Id = :shipmentId
            WITH SYSTEM_MODE
        ];
    }

    private static String snapshot(Shipment__c row) {
        return row.Status__c + '|' + row.Last_Location__c + '|' + row.Last_Update__c?.getTime() + '|'
            + row.Delivered_At__c?.getTime() + '|' + row.Proof_Id__c;
    }

    private static List<String> snapshots() {
        List<String> rows = new List<String>();
        for (Shipment__c row : shipments()) {
            rows.add(snapshot(row));
        }
        return rows;
    }

    private static String outcomeOf(EntregaYaStatusService.Result result) {
        return result.outcome + '|' + result.errorCode;
    }

    private static EntregaYaStatusService.Result applyAsIntegration(EntregaYaStatusRequest request) {
        EntregaYaStatusService.Result result;
        System.runAs(integrationUser()) {
            result = EntregaYaStatusService.apply(request);
        }
        return result;
    }

    private static EntregaYaStatusRequest request(Shipment__c target, String status, String location, String timestamp) {
        return TestDataFactory.newStatusRequest(target.Name, status, location, timestamp, null);
    }

    private static EntregaYaStatusRequest validRequest(Shipment__c target) {
        return request(target, 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00');
    }

    private static String iso(Datetime instant) {
        return instant.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss') + 'Z';
    }

    private static void fixClock() {
        EntregaYaStatusService.nowOverride = FIXED_NOW;
    }

    // Gives both first shipments a previous update of 2026-11-20T10:00:00-06:00.
    private static List<Shipment__c> shipmentsWithPreviousUpdate() {
        List<Shipment__c> rows = shipments();
        List<Shipment__c> changes = new List<Shipment__c>();
        for (Integer i = 0; i < 2; i++) {
            changes.add(new Shipment__c(Id = rows[i].Id, Status__c = PREVIOUS_STATUS,
                Last_Location__c = PREVIOUS_LOCATION, Last_Update__c = PREVIOUS_UPDATE));
        }
        updateAsSystem(changes);
        return shipments();
    }

    // Applies each request and returns "outcome|code" per request.
    private static List<String> outcomesOf(List<EntregaYaStatusRequest> requests) {
        List<String> outcomes = new List<String>();
        System.runAs(integrationUser()) {
            for (EntregaYaStatusRequest each : requests) {
                outcomes.add(outcomeOf(EntregaYaStatusService.apply(each)));
            }
        }
        return outcomes;
    }

    private static List<String> repeated(String value, Integer count) {
        List<String> values = new List<String>();
        for (Integer i = 0; i < count; i++) {
            values.add(value);
        }
        return values;
    }

    // ─── AC-004.2: what an update saves ───────────────────────────────────

    @IsTest
    static void apply_savesStatusLocationAndInstant_forTwoUpdates() {
        // AC-004.2: Status__c, Last_Location__c and Last_Update__c (the timestamp as an instant) are saved
        fixClock();
        List<Shipment__c> rows = shipments();
        Test.startTest();
        String first = outcomeOf(applyAsIntegration(validRequest(rows[0])));
        String second = outcomeOf(applyAsIntegration(
            request(rows[1], 'Picked up', '  Guadalajara, JAL ', '2026-11-20T08:15:00+02:00')));
        Test.stopTest();
        Assert.areEqual('UPDATED|null|UPDATED|null', first + '|' + second, 'Both updates must be applied');
        Assert.areEqual('Out for delivery|Monterrey, NL|' + Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0).getTime()
            + '|null|null', snapshot(shipment(rows[0].Id)), 'First shipment must hold the first update');
        Assert.areEqual('Picked up|Guadalajara, JAL|' + Datetime.newInstanceGmt(2026, 11, 20, 6, 15, 0).getTime()
            + '|null|null', snapshot(shipment(rows[1].Id)), 'Second shipment must hold the second update, trimmed');
    }

    @IsTest
    static void apply_savesDeliveredAtAndProofId_forTwoDeliveries() {
        // AC-004.2: Delivered with PRF-88231 at 2026-11-20T15:30:00-06:00 and PRF-90417 at 2026-11-21T09:05:00-06:00
        fixClock();
        List<Shipment__c> rows = shipments();
        Datetime firstAt = Datetime.newInstanceGmt(2026, 11, 20, 21, 30, 0);
        Datetime secondAt = Datetime.newInstanceGmt(2026, 11, 21, 15, 5, 0);
        Test.startTest();
        String first = outcomeOf(applyAsIntegration(TestDataFactory.newStatusRequest(
            rows[0].Name, 'Delivered', 'Monterrey, NL', '2026-11-20T15:30:00-06:00', 'PRF-88231')));
        String second = outcomeOf(applyAsIntegration(TestDataFactory.newStatusRequest(
            rows[1].Name, 'Delivered', 'Guadalajara, JAL', '2026-11-21T09:05:00-06:00', 'PRF-90417')));
        Test.stopTest();
        Assert.areEqual('UPDATED|null|UPDATED|null', first + '|' + second, 'Both deliveries must be applied');
        Assert.areEqual('Delivered|Monterrey, NL|' + firstAt.getTime() + '|' + firstAt.getTime() + '|PRF-88231',
            snapshot(shipment(rows[0].Id)), 'First delivery must save Delivered_At__c and Proof_Id__c');
        Assert.areEqual('Delivered|Guadalajara, JAL|' + secondAt.getTime() + '|' + secondAt.getTime() + '|PRF-90417',
            snapshot(shipment(rows[1].Id)), 'Second delivery must save Delivered_At__c and Proof_Id__c');
    }

    @IsTest
    static void apply_keepsDeliveredAtAndProofId_whenTheUpdateIsNotDelivered() {
        // AC-004.2: a non-Delivered update leaves Delivered_At__c and Proof_Id__c unchanged
        fixClock();
        List<Shipment__c> rows = shipments();
        Datetime deliveredAt = Datetime.newInstanceGmt(2026, 11, 19, 12, 0, 0);
        updateAsSystem(new List<Shipment__c>{
            new Shipment__c(Id = rows[0].Id, Delivered_At__c = deliveredAt, Proof_Id__c = 'PRF-11111'),
            new Shipment__c(Id = rows[1].Id, Delivered_At__c = deliveredAt, Proof_Id__c = 'PRF-22222')
        });
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            TestDataFactory.newStatusRequest(rows[0].Name, 'In transit', 'Leon, GTO', '2026-11-20T10:00:00-06:00', 'PRF-NEW1'),
            TestDataFactory.newStatusRequest(rows[1].Name, 'Exception', 'Celaya, GTO', '2026-11-20T11:00:00-06:00', null)
        });
        Test.stopTest();
        Assert.areEqual(repeated('UPDATED|null', 2), outcomes, 'Both updates must be applied');
        Assert.areEqual(deliveredAt.getTime() + '|PRF-11111|' + deliveredAt.getTime() + '|PRF-22222',
            shipment(rows[0].Id).Delivered_At__c.getTime() + '|' + shipment(rows[0].Id).Proof_Id__c + '|'
                + shipment(rows[1].Id).Delivered_At__c.getTime() + '|' + shipment(rows[1].Id).Proof_Id__c,
            'Delivered_At__c and Proof_Id__c must be unchanged by a non-Delivered update');
    }

    // ─── AC-004.4 (B2): stale and equal timestamps ────────────────────────

    @IsTest
    static void apply_ignoresAnOlderTimestamp() {
        // AC-004.4: Last_Update__c 2026-11-20T10:00:00-06:00, update at 09:00:00-06:00 is ignored and nothing changes
        fixClock();
        List<Shipment__c> rows = shipmentsWithPreviousUpdate();
        List<String> before = snapshots();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(rows[0], 'Out for delivery', 'Monterrey, NL', '2026-11-20T09:00:00-06:00'),
            request(rows[1], 'Picked up', 'Guadalajara, JAL', '2026-11-20T15:59:59Z')
        });
        Test.stopTest();
        Assert.areEqual(repeated('IGNORED|null', 2), outcomes, 'Older updates must be ignored');
        Assert.areEqual(before, snapshots(), 'An ignored update must change nothing');
    }

    @IsTest
    static void apply_ignoresTheSameInstant_inTwoNotations() {
        // AC-004.4: an update with exactly the same timestamp as Last_Update__c is also ignored
        fixClock();
        List<Shipment__c> rows = shipmentsWithPreviousUpdate();
        List<String> before = snapshots();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(rows[0], 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00'),
            request(rows[1], 'Exception', 'Guadalajara, JAL', '2026-11-20T16:00:00Z')
        });
        Test.stopTest();
        Assert.areEqual(repeated('IGNORED|null', 2), outcomes, 'Updates at the same instant must be ignored');
        Assert.areEqual(before, snapshots(), 'An ignored update must change nothing');
    }

    @IsTest
    static void apply_appliesANewerTimestamp() {
        // AC-004.4: an update at 2026-11-20T11:00:00-06:00 after Last_Update__c 10:00:00-06:00 is applied
        fixClock();
        List<Shipment__c> rows = shipmentsWithPreviousUpdate();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(rows[0], 'Out for delivery', 'Monterrey, NL', '2026-11-20T11:00:00-06:00'),
            request(rows[1], 'Picked up', 'Guadalajara, JAL', '2026-11-20T16:00:01Z')
        });
        Test.stopTest();
        Assert.areEqual(repeated('UPDATED|null', 2), outcomes, 'Newer updates must be applied');
        Assert.areEqual('Out for delivery|Monterrey, NL|' + Datetime.newInstanceGmt(2026, 11, 20, 17, 0, 0).getTime()
            + '|null|null', snapshot(shipment(rows[0].Id)), 'The newer update must be saved');
        Assert.areEqual('Picked up|Guadalajara, JAL|' + Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 1).getTime()
            + '|null|null', snapshot(shipment(rows[1].Id)), 'An update one second newer must be saved');
    }

    @IsTest
    static void apply_appliesAnyValidUpdate_whenThereIsNoLastUpdate() {
        // AC-004.4: a shipment with no Last_Update__c accepts any valid update, even an old one
        fixClock();
        List<Shipment__c> rows = shipments();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(rows[0], 'Requested', 'Puebla, PUE', '2020-01-01T00:00:00Z'),
            request(rows[1], 'In transit', 'Merida, YUC', '2025-06-30T23:59:59+05:30')
        });
        Test.stopTest();
        Assert.areEqual(repeated('UPDATED|null', 2), outcomes, 'Updates on shipments without Last_Update__c must apply');
        Assert.areEqual(Datetime.newInstanceGmt(2020, 1, 1, 0, 0, 0).getTime() + '|'
                + Datetime.newInstanceGmt(2025, 6, 30, 18, 29, 59).getTime(),
            shipment(rows[0].Id).Last_Update__c.getTime() + '|' + shipment(rows[1].Id).Last_Update__c.getTime(),
            'Last_Update__c must hold each timestamp as an instant');
    }

    // ─── AC-004.3: validation and the closed list of error codes ──────────

    @IsTest
    static void apply_returnsTrackingNotFound_forAnUnknownTrackingNumber() {
        // AC-004.3: an unknown tracking number gives TRACKING_NOT_FOUND and nothing changes
        fixClock();
        List<String> before = snapshots();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            TestDataFactory.newStatusRequest('RC999999999', 'In transit', 'Puebla, PUE', '2026-11-20T10:00:00-06:00', null),
            TestDataFactory.newStatusRequest('RC888888888', 'Delivered', 'Merida, YUC', '2026-11-20T10:00:00Z', 'PRF-1')
        });
        Test.stopTest();
        Assert.areEqual(repeated('NOT_FOUND|TRACKING_NOT_FOUND', 2), outcomes, 'Unknown tracking numbers are not found');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void apply_rejectsAStatusOutsideTheSixValues() {
        // AC-004.3: "Lost" and "delivered" (wrong case) give INVALID_STATUS and nothing changes
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(target, 'Lost', 'Puebla, PUE', '2026-11-20T10:00:00-06:00'),
            TestDataFactory.newStatusRequest(target.Name, 'delivered', 'Puebla, PUE', '2026-11-20T10:00:00-06:00', 'PRF-1'),
            request(target, 'In Transit', 'Puebla, PUE', '2026-11-20T10:00:00-06:00')
        });
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|INVALID_STATUS', 3), outcomes, 'Only the six exact values are accepted');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void apply_rejectsAMissingField() {
        // AC-004.3: a missing trackingNumber, status, location or timestamp (or no request) gives MISSING_FIELD
        fixClock();
        Shipment__c target = shipments()[0];
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            TestDataFactory.newStatusRequest(null, 'In transit', 'Puebla, PUE', '2026-11-20T10:00:00Z', null),
            TestDataFactory.newStatusRequest(target.Name, null, 'Puebla, PUE', '2026-11-20T10:00:00Z', null),
            TestDataFactory.newStatusRequest(target.Name, 'In transit', null, '2026-11-20T10:00:00Z', null),
            TestDataFactory.newStatusRequest(target.Name, 'In transit', 'Puebla, PUE', null, null),
            null
        });
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|MISSING_FIELD', 5), outcomes, 'Each missing field must be reported');
    }

    @IsTest
    static void apply_rejectsAMalformedTrackingNumber() {
        // AC-004.3: a tracking number not matching ^RC\d{9}$ gives INVALID_TRACKING_NUMBER
        fixClock();
        List<String> invalid = new List<String>{
            'RC12345678', 'RC1234567890', 'rc123456789', 'XX123456789', 'RC12345678A', '', ' RC123456789'
        };
        List<EntregaYaStatusRequest> requests = new List<EntregaYaStatusRequest>();
        for (String tracking : invalid) {
            requests.add(TestDataFactory.newStatusRequest(tracking, 'In transit', 'Puebla, PUE', '2026-11-20T10:00:00Z', null));
        }
        Test.startTest();
        List<String> outcomes = outcomesOf(requests);
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|INVALID_TRACKING_NUMBER', invalid.size()), outcomes,
            'Every malformed tracking number must be rejected');
    }

    @IsTest
    static void apply_rejectsAnEmptyOrOverlongLocation() {
        // AC-004.3: an empty, blank or 256-character location gives INVALID_LOCATION and nothing changes
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(target, 'In transit', '', '2026-11-20T10:00:00Z'),
            request(target, 'In transit', '   ', '2026-11-20T10:00:00Z'),
            request(target, 'In transit', 'x'.repeat(256), '2026-11-20T10:00:00Z')
        });
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|INVALID_LOCATION', 3), outcomes, 'Bad locations must be rejected');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void apply_acceptsALocationOf255Characters() {
        // AC-004.3: a 255-character location (and one of 1 character) is accepted
        fixClock();
        List<Shipment__c> rows = shipments();
        String longest = 'y'.repeat(255);
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(rows[0], 'In transit', longest, '2026-11-20T10:00:00Z'),
            request(rows[1], 'In transit', 'z', '2026-11-20T10:00:00Z')
        });
        Test.stopTest();
        Assert.areEqual(repeated('UPDATED|null', 2), outcomes, 'Locations of 1 and 255 characters are valid');
        Assert.areEqual(longest + '|z', shipment(rows[0].Id).Last_Location__c + '|' + shipment(rows[1].Id).Last_Location__c,
            'Both locations must be saved');
    }

    @IsTest
    static void apply_rejectsATimestampWithoutOffset() {
        // AC-004.3: a timestamp without offset gives INVALID_TIMESTAMP
        fixClock();
        Shipment__c target = shipments()[0];
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(target, 'In transit', 'Puebla, PUE', '2026-11-20T10:00:00'),
            request(target, 'In transit', 'Puebla, PUE', '2026-11-20T10:00:00.000'),
            request(target, 'In transit', 'Puebla, PUE', '2026-11-20')
        });
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|INVALID_TIMESTAMP', 3), outcomes, 'An offset is mandatory');
    }

    @IsTest
    static void apply_rejectsAnUnparsableTimestamp() {
        // AC-004.3: an unparsable timestamp gives INVALID_TIMESTAMP
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> invalid = new List<String>{
            'yesterday', '', '2026-13-01T10:00:00Z', '2026-02-30T10:00:00Z', '2026-11-20T24:00:00Z',
            '2026-11-20T10:60:00Z', '2026-11-20 10:00:00-06:00', '2026-11-20T10:00:00+15:00', '2026-11-20T10:00:00-0600'
        };
        List<EntregaYaStatusRequest> requests = new List<EntregaYaStatusRequest>();
        for (String timestamp : invalid) {
            requests.add(request(target, 'In transit', 'Puebla, PUE', timestamp));
        }
        Test.startTest();
        List<String> outcomes = outcomesOf(requests);
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|INVALID_TIMESTAMP', invalid.size()), outcomes,
            'Every unparsable timestamp must be rejected');
    }

    @IsTest
    static void apply_rejectsATimestampMoreThanTenMinutesAhead() {
        // AC-004.3, B5: a timestamp more than 10 minutes after the server clock gives INVALID_TIMESTAMP
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(target, 'In transit', 'Puebla, PUE', iso(FIXED_NOW.addMinutes(10).addSeconds(1))),
            request(target, 'In transit', 'Puebla, PUE', iso(FIXED_NOW.addDays(400)))
        });
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|INVALID_TIMESTAMP', 2), outcomes, 'Far-future timestamps must be rejected');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void apply_acceptsATimestampUpToTenMinutesAhead() {
        // AC-004.3, B5: a timestamp exactly 10 minutes (or 9 minutes) after the server clock is accepted
        fixClock();
        List<Shipment__c> rows = shipments();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            request(rows[0], 'In transit', 'Puebla, PUE', iso(FIXED_NOW.addMinutes(10))),
            request(rows[1], 'In transit', 'Puebla, PUE', iso(FIXED_NOW.addMinutes(9)))
        });
        Test.stopTest();
        Assert.areEqual(repeated('UPDATED|null', 2), outcomes, 'Timestamps up to 10 minutes ahead are valid');
    }

    @IsTest
    static void apply_requiresAProofId_forDelivered() {
        // AC-004.3, B1: Delivered without proofId (null or blank) gives PROOF_ID_REQUIRED and nothing changes
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            TestDataFactory.newStatusRequest(target.Name, 'Delivered', 'Puebla, PUE', '2026-11-20T10:00:00Z', null),
            TestDataFactory.newStatusRequest(target.Name, 'Delivered', 'Puebla, PUE', '2026-11-20T10:00:00Z', '  ')
        });
        Test.stopTest();
        Assert.areEqual(repeated('INVALID|PROOF_ID_REQUIRED', 2), outcomes, 'A delivery needs a proof id');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void apply_reportsTheFirstFailedCheck_inTheDecidedOrder() {
        // AC-004.3: order missing field, tracking, status, location, timestamp, proof id
        fixClock();
        Test.startTest();
        List<String> outcomes = outcomesOf(new List<EntregaYaStatusRequest>{
            TestDataFactory.newStatusRequest('bad', 'Lost', null, 'never', null),
            TestDataFactory.newStatusRequest('bad', 'Lost', '', 'never', null),
            TestDataFactory.newStatusRequest('RC000000001', 'Lost', '', 'never', null),
            TestDataFactory.newStatusRequest('RC000000001', 'Delivered', '', 'never', null),
            TestDataFactory.newStatusRequest('RC000000001', 'Delivered', 'Puebla, PUE', 'never', null)
        });
        Test.stopTest();
        Assert.areEqual(new List<String>{
            'INVALID|MISSING_FIELD', 'INVALID|INVALID_TRACKING_NUMBER', 'INVALID|INVALID_STATUS',
            'INVALID|INVALID_LOCATION', 'INVALID|INVALID_TIMESTAMP'
        }, outcomes, 'The first failed check must be reported');
    }

    @IsTest
    static void failure_mapsEachCodeToItsOutcomeAndAFixedGenericMessage() {
        // AC-004.3: no error message contains a stack trace, an exception type name or a field API name
        List<String> leaks = new List<String>();
        Set<String> messages = new Set<String>();
        Map<String, String> outcomes = new Map<String, String>();
        Test.startTest();
        for (EntregaYaStatusService.ErrorCode code : EntregaYaStatusService.ErrorCode.values()) {
            EntregaYaStatusService.Result result = EntregaYaStatusService.failure(code);
            String lower = result.message.toLowerCase();
            if (String.isBlank(result.message) || lower.contains('__c') || lower.contains('exception')
                    || lower.contains('class.') || lower.contains('line ') || lower.contains('shipment__')) {
                leaks.add(code.name());
            }
            messages.add(result.message);
            outcomes.put(code.name(), result.outcome.name());
        }
        Test.stopTest();
        Assert.areEqual(new List<String>(), leaks, 'Messages must be generic and non-empty');
        Assert.areEqual(EntregaYaStatusService.ErrorCode.values().size(), messages.size(), 'One message per code');
        Assert.areEqual('NOT_FOUND|RETRYABLE|INTERNAL|INVALID', outcomes.get('TRACKING_NOT_FOUND') + '|'
            + outcomes.get('TEMPORARILY_UNAVAILABLE') + '|' + outcomes.get('INTERNAL_ERROR') + '|'
            + outcomes.get('INVALID_STATUS'), 'Each code must map to its outcome');
    }

    // ─── B7: lock timeouts and unexpected errors ──────────────────────────

    @IsTest
    static void apply_returnsRetryable_whenTheRowIsLocked() {
        // B7 (AC-004.7 service part): UNABLE_TO_LOCK_ROW, from the query or the update, is RETRYABLE; nothing changes
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        List<String> outcomes = new List<String>();
        Test.startTest();
        EntregaYaStatusService.simulatedFailure = EntregaYaStatusService.Simulation.LOCK_ON_UPDATE;
        outcomes.add(outcomeOf(applyAsIntegration(validRequest(target))));
        EntregaYaStatusService.simulatedFailure = EntregaYaStatusService.Simulation.LOCK_ON_QUERY;
        outcomes.add(outcomeOf(applyAsIntegration(validRequest(target))));
        Test.stopTest();
        Assert.areEqual(repeated('RETRYABLE|TEMPORARILY_UNAVAILABLE', 2), outcomes, 'A lock timeout must be retryable');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void apply_returnsInternal_forAnUnexpectedException() {
        // B7 (AC-004.7 service part): any other exception is INTERNAL with the fixed message, never its text
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        EntregaYaStatusService.simulatedFailure = EntregaYaStatusService.Simulation.UNEXPECTED_DML;
        EntregaYaStatusService.Result dml = applyAsIntegration(validRequest(target));
        EntregaYaStatusService.simulatedFailure = EntregaYaStatusService.Simulation.UNEXPECTED_OTHER;
        EntregaYaStatusService.Result other = applyAsIntegration(validRequest(target));
        Test.stopTest();
        String expected = EntregaYaStatusService.failure(EntregaYaStatusService.ErrorCode.INTERNAL_ERROR).message;
        Assert.areEqual('INTERNAL|INTERNAL_ERROR|' + expected + '|INTERNAL|INTERNAL_ERROR|' + expected,
            outcomeOf(dml) + '|' + dml.message + '|' + outcomeOf(other) + '|' + other.message,
            'Unexpected exceptions must map to INTERNAL with the fixed message');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    // ─── AC-004.9 (P4, BR-04): only through the service ───────────────────

    private static List<Database.SaveResult> directUpdateAsIntegration(List<Shipment__c> changes) {
        List<Database.SaveResult> results;
        System.runAs(integrationUser()) {
            results = Database.update(changes, false, AccessLevel.USER_MODE);
        }
        return results;
    }

    private static String errorsOf(List<Database.SaveResult> results) {
        List<String> errors = new List<String>();
        for (Database.SaveResult result : results) {
            errors.add(result.isSuccess() ? 'success' : result.getErrors()[0].getMessage());
        }
        return String.join(errors, '|');
    }

    @IsTest
    static void directUpdate_isRefused_butTheSameChangeThroughTheServiceIsApplied() {
        // AC-004.9: the integration user's direct update is refused; the same change through the service is applied
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        String direct = errorsOf(directUpdateAsIntegration(new List<Shipment__c>{ new Shipment__c(Id = target.Id,
            Status__c = 'Out for delivery', Last_Location__c = 'Monterrey, NL', Last_Update__c = PREVIOUS_UPDATE) }));
        List<String> afterDirect = snapshots();
        String viaService = outcomeOf(applyAsIntegration(validRequest(target)));
        Test.stopTest();
        Assert.areEqual(DIRECT_UPDATE_MESSAGE, direct, 'The direct update must be refused with the generic message');
        Assert.areEqual(before, afterDirect, 'The refused update must change nothing');
        Assert.areEqual('UPDATED|null', viaService, 'The same change through the service must be applied');
        Assert.areEqual('Out for delivery|Monterrey, NL|' + PREVIOUS_UPDATE.getTime() + '|null|null',
            snapshot(shipment(target.Id)), 'The service must save the change');
    }

    @IsTest
    static void directUpdate_isStillRefused_afterServiceCalls() {
        // AC-004.9: the service's permission to write ends with its own update, also after a failure
        fixClock();
        List<Shipment__c> rows = shipments();
        Test.startTest();
        String applied = outcomeOf(applyAsIntegration(validRequest(rows[0])));
        EntregaYaStatusService.simulatedFailure = EntregaYaStatusService.Simulation.UNEXPECTED_DML;
        String failed = outcomeOf(applyAsIntegration(validRequest(rows[1])));
        String direct = errorsOf(directUpdateAsIntegration(new List<Shipment__c>{
            new Shipment__c(Id = rows[2].Id, Status__c = 'Exception'),
            new Shipment__c(Id = rows[3].Id, Last_Location__c = 'Toluca, MEX')
        }));
        Test.stopTest();
        Assert.areEqual('UPDATED|null|INTERNAL|INTERNAL_ERROR', applied + '|' + failed, 'One applied and one failed call');
        Assert.areEqual(DIRECT_UPDATE_MESSAGE + '|' + DIRECT_UPDATE_MESSAGE, direct,
            'Direct updates after service calls must still be refused');
        Assert.isFalse(EntregaYaStatusService.isApplying(), 'The service must not stay in its applying state');
    }
}
