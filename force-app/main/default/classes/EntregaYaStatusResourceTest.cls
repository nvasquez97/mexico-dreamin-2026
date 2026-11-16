/**
 * Tests for the EntregaYa status endpoint, run as an integration user that
 * holds only the EntregaYa Integration permission set.
 * Covers AC-004.1 to AC-004.4, BR-04 and BR-09.
 */
@IsTest
private class EntregaYaStatusResourceTest {
    private static final Datetime LAST_UPDATE = Datetime.newInstanceGmt(2026, 11, 16, 18, 0, 0);

    @TestSetup
    static void setup() {
        Account acme = TestDataFactory.buildCustomerAccount('Acme Test');
        Database.insert(acme, AccessLevel.SYSTEM_MODE);
        Database.insert(TestDataFactory.buildShipment(acme.Id, 'In transit'), AccessLevel.SYSTEM_MODE);
    }

    private static Shipment__c loadShipment() {
        return [
            SELECT Id, Name, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c,
                Recipient_Name__c, Price__c, Estimated_Delivery__c
            FROM Shipment__c WITH SYSTEM_MODE LIMIT 1
        ];
    }

    private static String body(String trackingNumber, String status, String location, String timestamp, String proofId) {
        return JSON.serialize(new Map<String, Object>{
            'trackingNumber' => trackingNumber,
            'status' => status,
            'location' => location,
            'timestamp' => timestamp,
            'proofId' => proofId
        });
    }

    private static Map<String, Object> post(String requestBody) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/entregaya/v1/shipment-status';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBody);
        RestContext.request = request;
        RestContext.response = new RestResponse();
        System.runAs(TestDataFactory.createIntegrationUser()) {
            EntregaYaStatusResource.receiveStatus();
        }
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
        result.put('httpStatus', RestContext.response.statusCode);
        return result;
    }

    // Covers AC-004.1, AC-004.2: a status change updates status, last location and last update.
    @IsTest
    static void shouldUpdateStatusLocationAndTime_WhenValidChange() {
        Shipment__c shipment = loadShipment();
        Test.startTest();
        Map<String, Object> result = post(body(shipment.Name, 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00', null));
        Test.stopTest();
        Assert.areEqual(200, result.get('httpStatus'), 'HTTP 200');
        Assert.areEqual('updated', result.get('result'), 'Result');
        Shipment__c saved = loadShipment();
        Assert.areEqual('Out for delivery', saved.Status__c, 'Status');
        Assert.areEqual('Monterrey, NL', saved.Last_Location__c, 'Last location');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0), saved.Last_Update__c, 'Timestamp with offset converted to UTC');
        Assert.isNull(saved.Delivered_At__c, 'Not delivered');
    }

    // Covers AC-004.2: Delivered also saves the moment of delivery and the proof id.
    @IsTest
    static void shouldSaveDeliveryMomentAndProof_WhenDelivered() {
        Shipment__c shipment = loadShipment();
        post(body(shipment.Name, 'Delivered', 'Monterrey, NL', '2026-11-20T13:30:00-06:00', 'PRF-88231'));
        Shipment__c saved = loadShipment();
        Assert.areEqual('Delivered', saved.Status__c, 'Status');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 20, 19, 30, 0), saved.Delivered_At__c, 'Delivered at');
        Assert.areEqual('PRF-88231', saved.Proof_Id__c, 'Proof id');
    }

    // Covers AC-004.2: only the carrier fields change; recipient, price and estimate stay as they were.
    @IsTest
    static void shouldNotTouchOtherFields_WhenUpdating() {
        Shipment__c before = loadShipment();
        post(body(before.Name, 'Delivered', 'Monterrey, NL', '2026-11-20T13:30:00-06:00', 'PRF-1'));
        Shipment__c saved = loadShipment();
        Assert.areEqual(before.Recipient_Name__c, saved.Recipient_Name__c, 'Recipient unchanged');
        Assert.areEqual(before.Price__c, saved.Price__c, 'Price unchanged');
        Assert.areEqual(before.Estimated_Delivery__c, saved.Estimated_Delivery__c, 'Estimate unchanged');
    }

    // Covers AC-004.3: a nonexistent tracking number is rejected with a clear message.
    @IsTest
    static void shouldReject_WhenTrackingNumberDoesNotExist() {
        Map<String, Object> result = post(body('RC999999999', 'In transit', 'Puebla, PUE', '2026-11-20T10:00:00-06:00', null));
        Assert.areEqual(404, result.get('httpStatus'), 'HTTP 404');
        Assert.areEqual('UNKNOWN_TRACKING_NUMBER', result.get('code'), 'Code');
        Assert.isTrue(String.valueOf(result.get('message')).contains('RC999999999'), 'Message names the tracking number');
    }

    // Covers AC-004.3: an invalid status is rejected with a clear message and nothing changes.
    @IsTest
    static void shouldReject_WhenStatusInvalid() {
        Shipment__c shipment = loadShipment();
        Map<String, Object> result = post(body(shipment.Name, 'Lost in space', 'Puebla, PUE', '2026-11-20T10:00:00-06:00', null));
        Assert.areEqual(400, result.get('httpStatus'), 'HTTP 400');
        Assert.areEqual('INVALID_STATUS', result.get('code'), 'Code');
        Assert.isTrue(String.valueOf(result.get('message')).contains('Out for delivery'), 'Message lists valid statuses');
        Assert.areEqual('In transit', loadShipment().Status__c, 'Status unchanged');
    }

    // Covers AC-004.3, BR-09: Requested is not a carrier status (only creation sets it).
    @IsTest
    static void shouldReject_WhenStatusIsRequested() {
        Map<String, Object> result = post(body(loadShipment().Name, 'Requested', 'Puebla, PUE', '2026-11-20T10:00:00-06:00', null));
        Assert.areEqual('INVALID_STATUS', result.get('code'), 'Requested is set only at creation');
    }

    // Covers AC-004.4: an update older than the last recorded one is ignored.
    @IsTest
    static void shouldIgnore_WhenUpdateIsOlderThanLastOne() {
        Shipment__c shipment = loadShipment();
        Map<String, Object> result = post(body(shipment.Name, 'Picked up', 'CDMX', '2026-11-15T09:00:00-06:00', null));
        Assert.areEqual(200, result.get('httpStatus'), 'Accepted but ignored');
        Assert.areEqual('ignored', result.get('result'), 'Result');
        Shipment__c saved = loadShipment();
        Assert.areEqual('In transit', saved.Status__c, 'Status unchanged');
        Assert.areEqual(LAST_UPDATE, saved.Last_Update__c, 'Last update unchanged');
    }

    // Covers AC-004.4: a duplicate with the same timestamp is ignored too.
    @IsTest
    static void shouldIgnore_WhenTimestampEqualsLastOne() {
        Map<String, Object> result = post(body(loadShipment().Name, 'Exception', 'CDMX', '2026-11-16T12:00:00-06:00', null));
        Assert.areEqual('ignored', result.get('result'), 'Same timestamp ignored');
        Assert.areEqual('In transit', loadShipment().Status__c, 'Status unchanged');
    }

    // Covers AC-004.3: a timestamp without a time zone offset is rejected.
    @IsTest
    static void shouldReject_WhenTimestampInvalid() {
        Map<String, Object> result = post(body(loadShipment().Name, 'In transit', 'CDMX', '20/11/2026 10:00', null));
        Assert.areEqual(400, result.get('httpStatus'), 'HTTP 400');
        Assert.areEqual('INVALID_TIMESTAMP', result.get('code'), 'Code');
    }

    // Covers AC-004.2 (assumption L8): Delivered without a proof id is rejected.
    @IsTest
    static void shouldReject_WhenDeliveredWithoutProofId() {
        Map<String, Object> result = post(body(loadShipment().Name, 'Delivered', 'Monterrey, NL', '2026-11-20T13:30:00-06:00', null));
        Assert.areEqual(400, result.get('httpStatus'), 'HTTP 400');
        Assert.areEqual('MISSING_PROOF_ID', result.get('code'), 'Code');
        Assert.areEqual('In transit', loadShipment().Status__c, 'Status unchanged');
    }

    // Covers AC-004.3: a body that is not JSON is rejected.
    @IsTest
    static void shouldReject_WhenBodyIsNotJson() {
        Map<String, Object> result = post('not json');
        Assert.areEqual(400, result.get('httpStatus'), 'HTTP 400');
        Assert.areEqual('INVALID_BODY', result.get('code'), 'Code');
    }

    // Covers AC-004.3: a missing location is rejected.
    @IsTest
    static void shouldReject_WhenLocationMissing() {
        Map<String, Object> result = post(body(loadShipment().Name, 'In transit', '  ', '2026-11-20T10:00:00-06:00', null));
        Assert.areEqual('MISSING_FIELD', result.get('code'), 'Code');
    }

    // Covers BR-04: the integration permission set is the only one granting the endpoint and status edit.
    @IsTest
    static void shouldGrantEndpointOnlyToIntegrationPermissionSet() {
        List<SetupEntityAccess> grants = [
            SELECT Parent.Name FROM SetupEntityAccess
            WHERE SetupEntityId IN (SELECT Id FROM ApexClass WHERE Name = 'EntregaYaStatusResource')
            AND Parent.IsOwnedByProfile = false
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, grants.size(), 'One permission set grants the endpoint');
        Assert.areEqual('EntregaYa_Integration', grants[0].Parent.Name, 'Only the integration permission set');
        List<SetupEntityAccess> profileGrants = [
            SELECT Parent.Profile.Name FROM SetupEntityAccess
            WHERE SetupEntityId IN (SELECT Id FROM ApexClass WHERE Name = 'EntregaYaStatusResource')
            AND Parent.IsOwnedByProfile = true AND Parent.Profile.Name != 'System Administrator'
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(0, profileGrants.size(), 'No other profile (guest, customer) grants the endpoint: ' + profileGrants);
    }

    // Covers BR-04, BR-09 (security review L-3): the integration user cannot bypass the endpoint with direct DML.
    @IsTest
    static void shouldRejectDirectEdit_WhenIntegrationUserUsesUserMode() {
        Shipment__c shipment = loadShipment();
        System.runAs(TestDataFactory.createIntegrationUser()) {
            try {
                Database.update(new Shipment__c(Id = shipment.Id, Status__c = 'Requested'), AccessLevel.USER_MODE);
                Assert.fail('Direct edit must be rejected');
            } catch (Exception e) {
                Assert.isTrue(e.getMessage().length() > 0, 'Rejected: ' + e.getMessage());
            }
        }
        Assert.areEqual('In transit', loadShipment().Status__c, 'Status unchanged');
    }
}
