/**
 * @description Proves EntregaYaStatusResource (req-004 S2), the HTTP contract of
 *              POST /services/apexrest/entregaya/v1/status: AC-004.1 (200 updated
 *              and the shipment saved), AC-004.2 (a POSTed "Delivered" saves
 *              Delivered_At__c and Proof_Id__c), AC-004.3 (HTTP codes: 404, 400 with each
 *              closed error code, no internals in any body; B10: a body
 *              over 16,384 bytes or nested deeper than 20 levels answers 400
 *              INVALID_JSON), AC-004.7 (503 for a
 *              lock, 500 for any other failure, nothing changes, no exception
 *              text) and AC-004.5 Apex part (403 FORBIDDEN without the custom
 *              permission RutaCargo_EntregaYa_Sender, even for a support agent who
 *              may edit statuses by hand, BR-09).
 *              Every POST sets RestContext.request/response and runs in
 *              System.runAs as the caller: the EntregaYa integration user (B8,
 *              reused or created by TestDataFactory) or a support agent. Criteria
 *              sharing rules are not evaluated in Apex tests (A10): setup mirrors
 *              both groups' rules with manual Edit shares, so a support agent could
 *              really change the shipments if the resource let them through.
 *              The service clock is fixed at 2026-11-22T00:00:00Z (seam
 *              nowOverride) so the AC timestamps of 2026-11-20 and 2026-11-21 are
 *              in the past. Every response body is parsed and compared whole, with
 *              its keys, status code and Content-Type.
 */
@IsTest
private with sharing class EntregaYaStatusResourceTest {

    private static final String INTEGRATION_KEY = 'rceyres';
    private static final String AGENT_KEY = 'rceyrag';
    private static final String CUSTOMER_NAME = 'EntregaYa Resource Customer';
    private static final Integer SHIPMENT_COUNT = 3;
    private static final Datetime FIXED_NOW = Datetime.newInstanceGmt(2026, 11, 22, 0, 0, 0);
    private static final String ENDPOINT = '/services/apexrest/entregaya/v1/status';
    private static final String JSON_TYPE = 'application/json';
    private static final String FORBIDDEN_MESSAGE = 'This user may not send EntregaYa status updates.';
    // B10: the largest accepted body and the deepest accepted nesting; a nesting
    // depth under the size cap that raised an uncatchable "Maximum stack depth
    // reached" before the depth check; the CPU budget (a fifth of the 10,000 ms
    // synchronous limit) for answering the nested bodies.
    private static final Integer MAX_BODY_BYTES = 16384;
    private static final Integer MAX_NESTING_DEPTH = 20;
    private static final Integer NESTING_DEPTH = 4000;
    private static final Integer CPU_BUDGET_MS = 2000;
    // Fragments that must never reach EntregaYa (X7): stack traces, exception type
    // names and text, field API names, platform status codes.
    private static final List<String> INTERNALS = new List<String>{
        '__c', 'Exception', 'Class.', 'line ', 'UNABLE_TO_LOCK_ROW', 'STRING_TOO_LONG',
        'FIELD_CUSTOM_VALIDATION', 'simulated', 'Record Currently Unavailable', 'NullPointer'
    };

    // ─── Setup and helpers ────────────────────────────────────────────────

    // SECURITY-JUSTIFICATION: the running test admin has no field permissions on
    // the RutaCargo custom fields (at API 67 DML and SOQL default to user mode),
    // so the fixture is written and read back in system mode. Scope: setup DML
    // and verification reads of this test class only. Compensating control: every
    // POST under test runs inside System.runAs as the caller, and the resource and
    // service run in user mode. (pending owner approval, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    @TestSetup
    static void setup() {
        TestDataFactory.insertEntregaYaIntegrationUser(INTEGRATION_KEY);
        TestDataFactory.insertSupportAgent(AGENT_KEY);
        Account customer = TestDataFactory.newCustomerAccount(CUSTOMER_NAME);
        insertAsSystem(new List<Account>{ customer });
        List<Shipment__c> shipments = TestDataFactory.newShipments(customer.Id, SHIPMENT_COUNT);
        insertAsSystem(shipments);
        TestDataFactory.insertShipmentGroupShares(shipments, TestDataFactory.ENTREGAYA_GROUP);
        TestDataFactory.insertShipmentGroupShares(shipments, TestDataFactory.AGENT_GROUP);
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

    private static User supportAgent() {
        String username = AGENT_KEY + '.' + UserInfo.getOrganizationId() + '@example.com.rutacargo';
        return [SELECT Id FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1];
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

    private static List<String> snapshots() {
        List<String> rows = new List<String>();
        for (Shipment__c row : shipments()) {
            rows.add(row.Name + '|' + row.Status__c + '|' + row.Last_Location__c + '|' + row.Last_Update__c?.getTime()
                + '|' + row.Delivered_At__c?.getTime() + '|' + row.Proof_Id__c);
        }
        return rows;
    }

    private static void fixClock() {
        EntregaYaStatusService.nowOverride = FIXED_NOW;
    }

    private static Map<String, Object> fields(Shipment__c target, String status, String location, String timestamp) {
        return TestDataFactory.newStatusRequestFields(target.Name, status, location, timestamp, null);
    }

    private static String validBody(Shipment__c target) {
        return JSON.serialize(fields(target, 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00'));
    }

    // The validBody fields of the target with one key set to the given value.
    private static String bodyWith(Shipment__c target, String key, Object value) {
        Map<String, Object> body = fields(target, 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00');
        body.put(key, value);
        return JSON.serialize(body);
    }

    // POSTs the body as the caller and returns the response.
    private static RestResponse post(User caller, Blob body) {
        RestRequest request = new RestRequest();
        request.requestURI = ENDPOINT;
        request.httpMethod = 'POST';
        request.requestBody = body;
        RestContext.request = request;
        RestContext.response = new RestResponse();
        System.runAs(caller) {
            EntregaYaStatusResource.post();
        }
        return RestContext.response;
    }

    // POSTs each text body as the caller; returns one summary per response.
    private static List<String> postAll(User caller, List<String> bodies) {
        List<String> summaries = new List<String>();
        for (String body : bodies) {
            summaries.add(summary(post(caller, body == null ? null : Blob.valueOf(body))));
        }
        return summaries;
    }

    // "status|Content-Type|parsed body with sorted keys"; fails on any internal fragment.
    private static String summary(RestResponse response) {
        String raw = response.responseBody?.toString();
        for (String fragment : INTERNALS) {
            Assert.isFalse(raw?.contains(fragment) == true, 'The body must not contain "' + fragment + '": ' + raw);
        }
        Object parsed = raw == null ? null : JSON.deserializeUntyped(raw);
        return response.statusCode + '|' + response.headers.get('Content-Type') + '|' + canonical(parsed);
    }

    private static String canonical(Object value) {
        if (!(value instanceof Map<String, Object>)) {
            return String.valueOf(value);
        }
        Map<String, Object> entries = (Map<String, Object>) value;
        List<String> keys = new List<String>(entries.keySet());
        keys.sort();
        List<String> parts = new List<String>();
        for (String key : keys) {
            parts.add(key + '=' + canonical(entries.get(key)));
        }
        return '{' + String.join(parts, ', ') + '}';
    }

    private static String success(String result) {
        return '200|' + JSON_TYPE + '|{result=' + result + '}';
    }

    private static String error(Integer statusCode, String code, String message) {
        return statusCode + '|' + JSON_TYPE + '|{error={code=' + code + ', message=' + message + '}}';
    }

    private static String error(Integer statusCode, EntregaYaStatusService.ErrorCode code) {
        return error(statusCode, code.name(), EntregaYaStatusService.failure(code).message);
    }

    private static List<String> repeated(String value, Integer count) {
        List<String> values = new List<String>();
        for (Integer i = 0; i < count; i++) {
            values.add(value);
        }
        return values;
    }

    // POSTs each body as the integration user and asserts the same error for all
    // of them and that no shipment changed.
    private static void assertRejected(List<String> bodies, Integer statusCode, EntregaYaStatusService.ErrorCode code) {
        fixClock();
        List<String> before = snapshots();
        Test.startTest();
        List<String> summaries = postAll(integrationUser(), bodies);
        Test.stopTest();
        Assert.areEqual(repeated(error(statusCode, code), bodies.size()), summaries,
            'Every body must answer ' + statusCode + ' ' + code.name());
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    // ─── AC-004.1: 200 updated ────────────────────────────────────────────

    @IsTest
    static void post_answersUpdatedAndSavesTheShipment_forTwoUpdates() {
        // AC-004.1: 200 {"result":"updated"}; Status__c and Last_Location__c saved, for two inputs
        fixClock();
        List<Shipment__c> rows = shipments();
        Test.startTest();
        List<String> summaries = postAll(integrationUser(), new List<String>{
            validBody(rows[0]),
            JSON.serialize(fields(rows[1], 'Picked up', 'Guadalajara, JAL', '2026-11-21T09:05:00-06:00'))
        });
        Test.stopTest();
        Assert.areEqual(repeated(success('updated'), 2), summaries, 'Both POSTs must answer 200 updated');
        List<Shipment__c> after = shipments();
        Assert.areEqual('Out for delivery|Monterrey, NL', after[0].Status__c + '|' + after[0].Last_Location__c,
            'The first shipment must hold the first update');
        Assert.areEqual('Picked up|Guadalajara, JAL', after[1].Status__c + '|' + after[1].Last_Location__c,
            'The second shipment must hold the second update');
    }

    @IsTest
    static void post_answersIgnored_forARepeatedAndAnOlderUpdate() {
        // AC-004.1 / D2: a stale update (same or older timestamp) answers 200 {"result":"ignored"}
        fixClock();
        Shipment__c target = shipments()[0];
        Test.startTest();
        List<String> summaries = postAll(integrationUser(), new List<String>{
            validBody(target),
            validBody(target),
            JSON.serialize(fields(target, 'Picked up', 'Guadalajara, JAL', '2026-11-20T09:00:00-06:00'))
        });
        Test.stopTest();
        Assert.areEqual(new List<String>{ success('updated'), success('ignored'), success('ignored') }, summaries,
            'The first POST must be applied and the repeated and older ones ignored');
        Shipment__c after = shipments()[0];
        Assert.areEqual('Out for delivery|Monterrey, NL', after.Status__c + '|' + after.Last_Location__c,
            'The ignored POSTs must not change the shipment');
    }

    @IsTest
    static void post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries() {
        // AC-004.2: POSTed "Delivered" with proofId PRF-88231 at 2026-11-20T15:30:00-06:00 and PRF-90417
        // at 2026-11-21T09:05:00-06:00 answer 200 updated; Delivered_At__c and Proof_Id__c hold each value
        fixClock();
        List<Shipment__c> rows = shipments();
        Datetime firstAt = Datetime.newInstanceGmt(2026, 11, 20, 21, 30, 0);
        Datetime secondAt = Datetime.newInstanceGmt(2026, 11, 21, 15, 5, 0);
        Test.startTest();
        List<String> summaries = postAll(integrationUser(), new List<String>{
            JSON.serialize(TestDataFactory.newStatusRequestFields(
                rows[0].Name, 'Delivered', 'Monterrey, NL', '2026-11-20T15:30:00-06:00', 'PRF-88231')),
            JSON.serialize(TestDataFactory.newStatusRequestFields(
                rows[1].Name, 'Delivered', 'Guadalajara, JAL', '2026-11-21T09:05:00-06:00', 'PRF-90417'))
        });
        Test.stopTest();
        Assert.areEqual(repeated(success('updated'), 2), summaries, 'Both deliveries must answer 200 updated');
        List<String> after = snapshots();
        Assert.areEqual(rows[0].Name + '|Delivered|Monterrey, NL|' + firstAt.getTime() + '|' + firstAt.getTime() + '|PRF-88231',
            after[0], 'The first delivery must save Delivered_At__c and Proof_Id__c');
        Assert.areEqual(rows[1].Name + '|Delivered|Guadalajara, JAL|' + secondAt.getTime() + '|' + secondAt.getTime() + '|PRF-90417',
            after[1], 'The second delivery must save Delivered_At__c and Proof_Id__c');
    }

    @IsTest
    static void post_readsOnlyTheFiveKnownKeys_andIgnoresTheRest() {
        // AC-004.3 / X6: unknown keys (also a field API name) are ignored; only the five contract keys are read
        fixClock();
        List<Shipment__c> rows = shipments();
        Map<String, Object> withCarrier = fields(rows[0], 'In transit', 'Puebla, PUE', '2026-11-20T10:00:00-06:00');
        withCarrier.put('carrier', 'Other');
        Map<String, Object> withFieldName = fields(rows[1], 'Picked up', 'Leon, GTO', '2026-11-20T10:00:00-06:00');
        withFieldName.put('Status__c', 'Delivered');
        withFieldName.put('Proof_Id__c', 'PRF-00001');
        Test.startTest();
        List<String> summaries = postAll(integrationUser(), new List<String>{
            JSON.serialize(withCarrier), JSON.serialize(withFieldName)
        });
        Test.stopTest();
        Assert.areEqual(repeated(success('updated'), 2), summaries, 'Unknown keys must not block the update');
        List<Shipment__c> after = shipments();
        Assert.areEqual('In transit|Puebla, PUE|null|Picked up|Leon, GTO|null',
            after[0].Status__c + '|' + after[0].Last_Location__c + '|' + after[0].Proof_Id__c + '|'
            + after[1].Status__c + '|' + after[1].Last_Location__c + '|' + after[1].Proof_Id__c,
            'Only the contract keys may reach the shipment');
    }

    // ─── AC-004.3: HTTP codes ─────────────────────────────────────────────

    @IsTest
    static void post_answers404_forUnknownTrackingNumbers() {
        // AC-004.3: an unknown tracking number answers 404 TRACKING_NOT_FOUND and nothing changes
        Shipment__c target = shipments()[0];
        assertRejected(new List<String>{ bodyWith(target, 'trackingNumber', 'RC000000000'),
            bodyWith(target, 'trackingNumber', 'RC999999999') }, 404, EntregaYaStatusService.ErrorCode.TRACKING_NOT_FOUND);
    }

    @IsTest
    static void post_answers400InvalidStatus_forLostAndLowercaseDelivered() {
        // AC-004.3: a status outside the six values ("Lost", "delivered") answers 400 INVALID_STATUS
        Shipment__c target = shipments()[0];
        assertRejected(new List<String>{ bodyWith(target, 'status', 'Lost'), bodyWith(target, 'status', 'delivered') },
            400, EntregaYaStatusService.ErrorCode.INVALID_STATUS);
    }

    @IsTest
    static void post_answers400InvalidJson_forBodiesThatAreNotAJsonObject() {
        // AC-004.3: malformed JSON, an empty body or a JSON value that is not an object answers 400 INVALID_JSON
        assertRejected(new List<String>{ '{"trackingNumber":"RC', 'not json', '', null, '[]', '"RC000000001"', 'null' },
            400, EntregaYaStatusService.ErrorCode.INVALID_JSON);
    }

    @IsTest
    static void post_answers400InvalidJson_forBytesThatAreNotUtf8Text() {
        // AC-004.3: a body that is not UTF-8 text answers 400 INVALID_JSON and nothing changes
        fixClock();
        List<String> before = snapshots();
        Test.startTest();
        String answer = summary(post(integrationUser(), EncodingUtil.base64Decode('/w==')));
        Test.stopTest();
        Assert.areEqual(error(400, EntregaYaStatusService.ErrorCode.INVALID_JSON), answer, 'Bytes must answer INVALID_JSON');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void post_answers400InvalidJson_forWrongJsonTypes() {
        // AC-004.3: a known key holding a number, boolean, array or object answers 400 INVALID_JSON
        Shipment__c target = shipments()[0];
        assertRejected(new List<String>{
            bodyWith(target, 'status', 5),
            bodyWith(target, 'location', true),
            bodyWith(target, 'trackingNumber', new List<String>{ target.Name }),
            bodyWith(target, 'proofId', new Map<String, Object>{ 'id' => 'PRF-1' }),
            bodyWith(target, 'timestamp', 1795190400000L)
        }, 400, EntregaYaStatusService.ErrorCode.INVALID_JSON);
    }

    @IsTest
    static void post_answers400MissingField_forAbsentNullOrMiscasedKeys() {
        // AC-004.3: a missing field (absent, JSON null, or a key in another case) answers 400 MISSING_FIELD
        Shipment__c target = shipments()[0];
        Map<String, Object> withoutLocation = fields(target, 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00');
        withoutLocation.remove('location');
        Map<String, Object> miscased = fields(target, 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00');
        miscased.put('Timestamp', miscased.remove('timestamp'));
        assertRejected(new List<String>{ JSON.serialize(withoutLocation), bodyWith(target, 'trackingNumber', null),
            JSON.serialize(miscased), '{}' }, 400, EntregaYaStatusService.ErrorCode.MISSING_FIELD);
    }

    @IsTest
    static void post_answers400InvalidTrackingNumber_forBadFormats() {
        // AC-004.3: a tracking number not matching ^RC\d{9}$ answers 400 INVALID_TRACKING_NUMBER
        Shipment__c target = shipments()[0];
        assertRejected(new List<String>{ bodyWith(target, 'trackingNumber', 'RC12345678'),
            bodyWith(target, 'trackingNumber', 'rc123456789'), bodyWith(target, 'trackingNumber', 'RC1234567890') },
            400, EntregaYaStatusService.ErrorCode.INVALID_TRACKING_NUMBER);
    }

    @IsTest
    static void post_answers400InvalidLocation_forEmptyAndTooLongLocations() {
        // AC-004.3: an empty or over-255-character location answers 400 INVALID_LOCATION
        Shipment__c target = shipments()[0];
        assertRejected(new List<String>{ bodyWith(target, 'location', '   '), bodyWith(target, 'location', 'x'.repeat(256)) },
            400, EntregaYaStatusService.ErrorCode.INVALID_LOCATION);
    }

    @IsTest
    static void post_answers400InvalidTimestamp_forNoOffsetUnparsableAndFuture() {
        // AC-004.3: a timestamp without offset, unparsable, or more than 10 minutes ahead answers 400 INVALID_TIMESTAMP
        Shipment__c target = shipments()[0];
        String elevenMinutesAhead = FIXED_NOW.addMinutes(11).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss') + 'Z';
        assertRejected(new List<String>{ bodyWith(target, 'timestamp', '2026-11-20T10:00:00'),
            bodyWith(target, 'timestamp', 'yesterday'), bodyWith(target, 'timestamp', elevenMinutesAhead) },
            400, EntregaYaStatusService.ErrorCode.INVALID_TIMESTAMP);
    }

    @IsTest
    static void post_answers400ProofIdRequired_forDeliveredWithoutProofId() {
        // AC-004.3 / B1: "Delivered" with a null or absent proofId answers 400 PROOF_ID_REQUIRED
        Shipment__c target = shipments()[0];
        Map<String, Object> absent = fields(target, 'Delivered', 'Monterrey, NL', '2026-11-20T10:00:00-06:00');
        absent.remove('proofId');
        assertRejected(new List<String>{ bodyWith(target, 'status', 'Delivered'), JSON.serialize(absent) },
            400, EntregaYaStatusService.ErrorCode.PROOF_ID_REQUIRED);
    }

    @IsTest
    static void post_answers400InvalidProofId_forBadCharactersAndTooLong() {
        // AC-004.3 / B9: a proofId with other characters or over 100 characters answers 400 INVALID_PROOF_ID
        Shipment__c target = shipments()[0];
        assertRejected(new List<String>{ bodyWith(target, 'proofId', 'PRF 88231'), bodyWith(target, 'proofId', 'P'.repeat(101)) },
            400, EntregaYaStatusService.ErrorCode.INVALID_PROOF_ID);
    }

    // ─── AC-004.3 / B10: body size cap ────────────────────────────────────

    // The body is padded with JSON whitespace, inside the object after "{" or after
    // the closing "}", to exactly the given size in bytes.
    private static String padTo(String body, Integer size, Boolean inside) {
        String padding = ' '.repeat(size - Blob.valueOf(body).size());
        String padded = inside ? '{' + padding + body.substring(1) : body + padding;
        Assert.areEqual(size, Blob.valueOf(padded).size(), 'The padded body must be exactly ' + size + ' bytes');
        return padded;
    }

    private static String nestedArrays(Integer depth) {
        return '['.repeat(depth) + ']'.repeat(depth);
    }

    private static String nestedObjects(Integer depth) {
        return '{"a":'.repeat(depth - 1) + '{}' + '}'.repeat(depth - 1);
    }

    // The JSON object body with one more, unknown, key "meta" holding the value.
    private static String withMeta(String body, String value) {
        return body.removeEnd('}') + ',"meta":' + value + '}';
    }

    @IsTest
    static void post_answers400InvalidJson_forBodiesOverTheSizeCap() {
        // AC-004.3 / B10: a body over 16 KB (valid fields padded to 16,385 bytes, or nested arrays) answers 400 INVALID_JSON; nothing changes
        Shipment__c target = shipments()[0];
        String overNested = nestedArrays(MAX_BODY_BYTES / 2 + 1);
        Assert.areEqual(MAX_BODY_BYTES + 2, Blob.valueOf(overNested).size(), 'The nested body must be over the cap');
        assertRejected(new List<String>{ padTo(validBody(target), MAX_BODY_BYTES + 1, true), overNested },
            400, EntregaYaStatusService.ErrorCode.INVALID_JSON);
    }

    @IsTest
    static void post_answers400InvalidJson_withinTheCpuBudget_forDeeplyNestedBodiesUnderTheCap() {
        // AC-004.3 / B10: a body under 16 KB nested deeper than 20 levels (bare arrays, a known key, or valid fields
        // plus an unknown key one level too deep) answers 400 INVALID_JSON, well within the CPU limit
        Shipment__c target = shipments()[0];
        List<String> bodies = new List<String>{
            nestedArrays(NESTING_DEPTH), '{"trackingNumber":' + nestedArrays(NESTING_DEPTH) + '}',
            withMeta(validBody(target), nestedArrays(MAX_NESTING_DEPTH))
        };
        for (String body : bodies) {
            Assert.isTrue(Blob.valueOf(body).size() < MAX_BODY_BYTES, 'The nested body must be under the cap');
        }
        fixClock();
        List<String> before = snapshots();
        User caller = integrationUser();
        Test.startTest();
        Integer cpuBefore = Limits.getCpuTime();
        List<String> summaries = postAll(caller, bodies);
        Integer cpuUsed = Limits.getCpuTime() - cpuBefore;
        Test.stopTest();
        Assert.areEqual(repeated(error(400, EntregaYaStatusService.ErrorCode.INVALID_JSON), 3), summaries,
            'A deeply nested body must answer 400 INVALID_JSON');
        Assert.isTrue(cpuUsed < CPU_BUDGET_MS, 'The nested bodies must use under ' + CPU_BUDGET_MS + ' ms of CPU; used ' + cpuUsed);
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void post_answersUpdated_forAnUnknownKeyNestedToExactlyTheDepthLimit() {
        // AC-004.1 / B10 boundary: valid fields plus an unknown key nested to exactly 20 levels (arrays, objects) answer 200 updated
        fixClock();
        List<Shipment__c> rows = shipments();
        List<String> bodies = new List<String>{
            withMeta(validBody(rows[0]), nestedArrays(MAX_NESTING_DEPTH - 1)),
            withMeta(JSON.serialize(fields(rows[1], 'Picked up', 'Guadalajara, JAL', '2026-11-21T09:05:00-06:00')),
                nestedObjects(MAX_NESTING_DEPTH - 1))
        };
        Test.startTest();
        List<String> summaries = postAll(integrationUser(), bodies);
        Test.stopTest();
        Assert.areEqual(repeated(success('updated'), 2), summaries, 'A body nested exactly 20 levels must be accepted');
        List<Shipment__c> after = shipments();
        Assert.areEqual('Out for delivery|Monterrey, NL|Picked up|Guadalajara, JAL',
            after[0].Status__c + '|' + after[0].Last_Location__c + '|' + after[1].Status__c + '|' + after[1].Last_Location__c,
            'Both shipments must hold their update');
    }

    @IsTest
    static void post_answersUpdated_forValidBodiesExactlyAtTheSizeCap() {
        // AC-004.1 / B10 boundary: valid fields padded with whitespace to exactly 16,384 bytes still answer 200 updated
        fixClock();
        List<Shipment__c> rows = shipments();
        List<String> bodies = new List<String>{
            padTo(validBody(rows[0]), MAX_BODY_BYTES, true),
            padTo(JSON.serialize(fields(rows[1], 'Picked up', 'Guadalajara, JAL', '2026-11-21T09:05:00-06:00')), MAX_BODY_BYTES, false)
        };
        Test.startTest();
        List<String> summaries = postAll(integrationUser(), bodies);
        Test.stopTest();
        Assert.areEqual(repeated(success('updated'), 2), summaries, 'A body of exactly 16,384 bytes must be accepted');
        List<Shipment__c> after = shipments();
        Assert.areEqual('Out for delivery|Monterrey, NL|Picked up|Guadalajara, JAL',
            after[0].Status__c + '|' + after[0].Last_Location__c + '|' + after[1].Status__c + '|' + after[1].Last_Location__c,
            'Both shipments must hold their update');
    }

    // ─── AC-004.7: lock and unexpected failures ───────────────────────────

    private static List<String> postWithFailures(Shipment__c target, List<EntregaYaStatusService.Simulation> failures) {
        List<String> summaries = new List<String>();
        for (EntregaYaStatusService.Simulation failure : failures) {
            EntregaYaStatusService.simulatedFailure = failure;
            summaries.addAll(postAll(integrationUser(), new List<String>{ validBody(target) }));
        }
        return summaries;
    }

    @IsTest
    static void post_answers503_whenTheRowIsLocked() {
        // AC-004.7: UNABLE_TO_LOCK_ROW (update or FOR UPDATE wait) answers 503 TEMPORARILY_UNAVAILABLE; nothing changes
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> summaries = postWithFailures(target, new List<EntregaYaStatusService.Simulation>{
            EntregaYaStatusService.Simulation.LOCK_ON_UPDATE, EntregaYaStatusService.Simulation.LOCK_ON_QUERY });
        Test.stopTest();
        Assert.areEqual(repeated(error(503, EntregaYaStatusService.ErrorCode.TEMPORARILY_UNAVAILABLE), 2), summaries,
            'A lock must answer 503 with the generic body');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void post_answers500_forUnexpectedAndRealSaveErrors() {
        // AC-004.7: an unexpected DmlException, another exception or a real non-lock save error answers 500 INTERNAL_ERROR
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> summaries = postWithFailures(target, new List<EntregaYaStatusService.Simulation>{
            EntregaYaStatusService.Simulation.UNEXPECTED_DML, EntregaYaStatusService.Simulation.UNEXPECTED_OTHER,
            EntregaYaStatusService.Simulation.REAL_SAVE_ERROR });
        Test.stopTest();
        Assert.areEqual(repeated(error(500, EntregaYaStatusService.ErrorCode.INTERNAL_ERROR), 3), summaries,
            'Any other failure must answer 500 with the generic body');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void post_answers500_whenAnExceptionEscapesTheResource() {
        // AC-004.7 / X7: an exception inside the resource (no request to read) answers 500 INTERNAL_ERROR, no exception text
        fixClock();
        List<String> before = snapshots();
        RestContext.request = null;
        RestContext.response = new RestResponse();
        Test.startTest();
        System.runAs(integrationUser()) {
            EntregaYaStatusResource.post();
        }
        Test.stopTest();
        Assert.areEqual(error(500, EntregaYaStatusService.ErrorCode.INTERNAL_ERROR), summary(RestContext.response),
            'An escaping exception must answer 500 with the generic body');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    // ─── AC-004.5 (Apex part): 403 without the custom permission ──────────

    @IsTest
    static void post_answers403AndChangesNothing_forASupportAgent() {
        // AC-004.5: a support agent (may edit statuses by hand, BR-09) gets 403 FORBIDDEN, before any parsing; nothing changes
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> summaries = postAll(supportAgent(), new List<String>{ validBody(target), '{"trackingNumber":"RC' });
        Test.stopTest();
        Assert.areEqual(repeated(error(403, 'FORBIDDEN', FORBIDDEN_MESSAGE), 2), summaries,
            'A caller without RutaCargo_EntregaYa_Sender must get 403 FORBIDDEN');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }

    @IsTest
    static void post_answers403_forTheRunningAdministrator() {
        // AC-004.5: any caller without RutaCargo_EntregaYa_Sender (here the test administrator) gets 403 FORBIDDEN
        fixClock();
        Shipment__c target = shipments()[0];
        List<String> before = snapshots();
        Test.startTest();
        List<String> summaries = postAll(new User(Id = UserInfo.getUserId()), new List<String>{ validBody(target) });
        Test.stopTest();
        Assert.areEqual(new List<String>{ error(403, 'FORBIDDEN', FORBIDDEN_MESSAGE) }, summaries,
            'The administrator without RutaCargo_EntregaYa_Sender must get 403 FORBIDDEN');
        Assert.areEqual(before, snapshots(), 'Nothing may change');
    }
}
