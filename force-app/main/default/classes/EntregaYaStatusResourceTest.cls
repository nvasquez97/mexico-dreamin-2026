@IsTest
private class EntregaYaStatusResourceTest {
    private static String body(String tn, String status, String ts, String proof) {
        return JSON.serialize(new Map<String, Object>{
            'trackingNumber' => tn, 'status' => status, 'location' => 'Monterrey, NL', 'timestamp' => ts, 'proofId' => proof
        });
    }

    private static void post(String json) {
        RestContext.request = new RestRequest();
        RestContext.request.requestBody = Blob.valueOf(json);
        RestContext.response = new RestResponse();
        EntregaYaStatusResource.receive();
    }

    private static User integrationUser() {
        return TestDataFactory.userWith('RutaCargo_EntregaYa_Integration');
    }

    // AC-004.1, AC-004.2
    @IsTest
    static void appliesStatusChanges() {
        Shipment__c s = TestDataFactory.shipment(TestDataFactory.account('A').Id, 'In transit', '64000');
        User api = integrationUser();
        System.runAs(api) {
            post(body(s.Name, 'Out for delivery', '2026-11-20T10:00:00-06:00', null));
        }
        System.assertEquals(200, RestContext.response.statusCode);
        Shipment__c r = [SELECT Status__c, Last_Location__c, Last_Update__c, Delivered_At__c FROM Shipment__c WHERE Id = :s.Id];
        System.assertEquals('Out for delivery', r.Status__c);
        System.assertEquals('Monterrey, NL', r.Last_Location__c);
        System.assertEquals(Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0), r.Last_Update__c, '10:00 at -06:00 is 16:00Z');
        System.assertEquals(null, r.Delivered_At__c);

        System.runAs(api) {
            post(body(s.Name.toLowerCase(), 'Delivered', '2026-11-20T15:30:00-06:00', 'PRF-1'));
        }
        r = [SELECT Status__c, Delivered_At__c, Proof_Id__c FROM Shipment__c WHERE Id = :s.Id];
        System.assertEquals('Delivered', r.Status__c);
        System.assertEquals(Datetime.newInstanceGmt(2026, 11, 20, 21, 30, 0), r.Delivered_At__c);
        System.assertEquals('PRF-1', r.Proof_Id__c);
    }

    // AC-004.4
    @IsTest
    static void ignoresOlderUpdates() {
        Shipment__c s = TestDataFactory.shipment(TestDataFactory.account('A').Id, 'In transit', '64000');
        System.runAs(integrationUser()) {
            post(body(s.Name, 'Out for delivery', '2026-11-20T10:00:00-06:00', null));
            post(body(s.Name, 'In transit', '2026-11-19T10:00:00-06:00', null));
        }
        System.assertEquals(200, RestContext.response.statusCode);
        System.assert(RestContext.response.responseBody.toString().contains('ignored'));
        System.assertEquals('Out for delivery', [SELECT Status__c FROM Shipment__c WHERE Id = :s.Id].Status__c);
    }

    // AC-004.3
    @IsTest
    static void rejectsBadRequestsClearly() {
        Shipment__c s = TestDataFactory.shipment(TestDataFactory.account('A').Id, 'In transit', '64000');
        System.runAs(integrationUser()) {
            post(body('RC000000000', 'Delivered', '2026-11-20T10:00:00-06:00', null));
            System.assertEquals(404, RestContext.response.statusCode);
            System.assert(RestContext.response.responseBody.toString().contains('Shipment not found'));
            post(body(s.Name, 'Lost', '2026-11-20T10:00:00-06:00', null));
            System.assertEquals(400, RestContext.response.statusCode);
            System.assert(RestContext.response.responseBody.toString().contains('Valid statuses'));
            post(body(s.Name, 'Delivered', 'yesterday', null));
            System.assertEquals(400, RestContext.response.statusCode);
            post('{"status":"Delivered","timestamp":"2026-11-20T10:00:00Z"}');
            System.assertEquals(400, RestContext.response.statusCode);
            post('{"trackingNumber":"' + s.Name + '","timestamp":"2026-11-20T10:00:00Z"}');
            System.assertEquals(400, RestContext.response.statusCode);
            post('{"trackingNumber":"' + s.Name + '","status":"Delivered"}');
            System.assertEquals(400, RestContext.response.statusCode);
            post('garbage');
            System.assertEquals(400, RestContext.response.statusCode);
        }
        System.assertEquals('In transit', [SELECT Status__c FROM Shipment__c WHERE Id = :s.Id].Status__c, 'nothing changed');
    }

    // BR-04
    @IsTest
    static void onlyTheIntegrationUserMayPost() {
        Shipment__c s = TestDataFactory.shipment(TestDataFactory.account('A').Id, 'In transit', '64000');
        System.runAs(TestDataFactory.userWith(null)) {
            post(body(s.Name, 'Delivered', '2026-11-20T10:00:00-06:00', 'PRF-1'));
        }
        System.assertEquals(403, RestContext.response.statusCode);
        System.assertEquals('In transit', [SELECT Status__c FROM Shipment__c WHERE Id = :s.Id].Status__c);
    }
}
