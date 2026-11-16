/**
 * Tests for the carrier status service and its REST resource (REQ-004).
 */
@IsTest
private class ShipmentStatusServiceTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantSupportAccess();
        TestDataFactory.createShipment(null, 'Requested', 'S-1');
    }

    private static String tn() {
        return [SELECT Name FROM Shipment__c LIMIT 1].Name;
    }

    private static User integrationUser() {
        User integration;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            integration = new User(
                Username = 'integration' + System.currentTimeMillis() + '@rutacargo.test', Email = 'i@rutacargo.test',
                LastName = 'EntregaYa', Alias = 'entya', ProfileId = standard.Id, TimeZoneSidKey = 'America/Mexico_City',
                LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
            );
            insert integration;
            insert new PermissionSetAssignment(
                AssigneeId = integration.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'RutaCargo_EntregaYa_Integration'].Id
            );
        }
        return integration;
    }

    private static void post(String body) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/entregaya/v1/status';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        RestContext.request = request;
        RestContext.response = new RestResponse();
        EntregaYaStatusRestResource.post();
    }

    private static String body(String trackingNumber, String status, String timestamp, String proofId) {
        return JSON.serialize(new Map<String, Object>{
            'trackingNumber' => trackingNumber, 'status' => status, 'location' => 'Monterrey, NL', 'timestamp' => timestamp, 'proofId' => proofId
        });
    }

    @IsTest
    static void updatesStatusLocationAndDate_AC_004_2() {
        ShipmentStatusService.Result result = ShipmentStatusService.apply(tn(), 'Out for delivery', 'Monterrey, NL', '2026-11-20T10:00:00-06:00', null);
        Assert.areEqual(ShipmentStatusService.Outcome.APPLIED, result.outcome);
        Shipment__c s = [SELECT Status__c, Last_Location__c, Last_Update__c, Delivered_At__c FROM Shipment__c];
        Assert.areEqual('Out for delivery', s.Status__c);
        Assert.areEqual('Monterrey, NL', s.Last_Location__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0), s.Last_Update__c, '10:00 at -06:00 is 16:00 UTC');
        Assert.isNull(s.Delivered_At__c);
    }

    @IsTest
    static void deliveredSavesMomentAndProofId_AC_004_2() {
        ShipmentStatusService.apply(tn(), 'Delivered', 'Monterrey, NL', '2026-11-21T09:30:00-06:00', 'PRF-88231');
        Shipment__c s = [SELECT Status__c, Delivered_At__c, Proof_Id__c FROM Shipment__c];
        Assert.areEqual('Delivered', s.Status__c);
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 21, 15, 30, 0), s.Delivered_At__c);
        Assert.areEqual('PRF-88231', s.Proof_Id__c);
    }

    @IsTest
    static void unknownTrackingRejected_AC_004_3() {
        ShipmentStatusService.Result result = ShipmentStatusService.apply('RC000000000', 'In transit', 'x', '2026-11-20T10:00:00-06:00', null);
        Assert.areEqual(ShipmentStatusService.Outcome.NOT_FOUND, result.outcome);
        Assert.isTrue(result.message.contains('RC000000000'));
    }

    @IsTest
    static void invalidStatusRejectedIncludingRequested_AC_004_3_BR_09() {
        for (String status : new List<String>{ 'Teleported', 'Requested', '', null }) {
            ShipmentStatusService.Result result = ShipmentStatusService.apply(tn(), status, 'x', '2026-11-20T10:00:00-06:00', null);
            Assert.areEqual(ShipmentStatusService.Outcome.INVALID, result.outcome, 'status ' + status);
            Assert.isTrue(result.message.contains('Invalid status'));
        }
        Assert.areEqual('Requested', [SELECT Status__c FROM Shipment__c].Status__c, 'nothing changed');
    }

    @IsTest
    static void invalidTimestampRejected_AC_004_1() {
        Assert.areEqual(ShipmentStatusService.Outcome.INVALID, ShipmentStatusService.apply(tn(), 'In transit', 'x', 'yesterday', null).outcome);
        Assert.areEqual(ShipmentStatusService.Outcome.INVALID, ShipmentStatusService.apply(tn(), 'In transit', 'x', null, null).outcome);
    }

    @IsTest
    static void olderUpdateIgnored_AC_004_4() {
        ShipmentStatusService.apply(tn(), 'In transit', 'Queretaro', '2026-11-20T10:00:00-06:00', null);
        ShipmentStatusService.Result older = ShipmentStatusService.apply(tn(), 'Picked up', 'Mexico City', '2026-11-19T10:00:00-06:00', null);
        Assert.areEqual(ShipmentStatusService.Outcome.IGNORED_OLDER, older.outcome);
        Shipment__c s = [SELECT Status__c, Last_Location__c FROM Shipment__c];
        Assert.areEqual('In transit', s.Status__c);
        Assert.areEqual('Queretaro', s.Last_Location__c);
    }

    @IsTest
    static void restRequiresCustomPermission_BR_04() {
        post(body(tn(), 'In transit', '2026-11-20T10:00:00-06:00', null));
        Assert.areEqual(403, RestContext.response.statusCode, 'a user without the permission is refused');
        Assert.areEqual('Requested', [SELECT Status__c FROM Shipment__c].Status__c);
    }

    @IsTest
    static void restHappyPathAndErrorCodes_AC_004_1_AC_004_3() {
        User integration = integrationUser();
        String number1 = tn();
        System.runAs(integration) {
            post(body(number1, 'In transit', '2026-11-20T10:00:00-06:00', null));
            Assert.areEqual(200, RestContext.response.statusCode);
            post(body('RC000000000', 'In transit', '2026-11-20T10:00:00-06:00', null));
            Assert.areEqual(404, RestContext.response.statusCode);
            post(body(number1, 'Nope', '2026-11-20T10:00:00-06:00', null));
            Assert.areEqual(400, RestContext.response.statusCode);
            Assert.isTrue(RestContext.response.responseBody.toString().contains('Invalid status'));
            post('not json');
            Assert.areEqual(400, RestContext.response.statusCode);
            post(body(number1, 'Picked up', '2026-11-19T10:00:00-06:00', null));
            Assert.areEqual(200, RestContext.response.statusCode, 'older updates are acknowledged but ignored');
        }
        Assert.areEqual('In transit', [SELECT Status__c FROM Shipment__c].Status__c);
    }

    @IsTest
    static void bulkOfUpdatesForDistinctShipments_Volume() {
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < 50; i++) {
            Shipment__c s = TestDataFactory.createShipment(null, 'Requested', 'B-' + i);
            shipments.add(s);
        }
        Integer applied = 0;
        for (Shipment__c s : [SELECT Name FROM Shipment__c WHERE Customer_Reference__c LIKE 'B-%']) {
            if (ShipmentStatusService.apply(s.Name, 'In transit', 'Hub', '2026-11-20T10:00:00-06:00', null).outcome == ShipmentStatusService.Outcome.APPLIED) {
                applied++;
            }
        }
        Assert.areEqual(50, applied);
    }
}
