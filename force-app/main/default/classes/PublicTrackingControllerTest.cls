@IsTest
private class PublicTrackingControllerTest {
    private class ProofMock implements HttpCalloutMock {
        Integer code;
        String body;
        ProofMock(Integer code, String body) {
            this.code = code;
            this.body = body;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(code);
            r.setBody(body);
            return r;
        }
    }

    @TestSetup
    static void setup() {
        Account a = TestDataFactory.account('Acme Test');
        TestDataFactory.shipment(a.Id, 'In transit', '64000');
        Shipment__c d = TestDataFactory.shipment(a.Id, 'Delivered', '72000');
        update new Shipment__c(Id = d.Id, Proof_Id__c = 'PRF-1');
    }

    private static Shipment__c byStatus(String status) {
        return [SELECT Id, Name, Destination_Postal_Code__c, Reschedule_Count__c, Failed_Verifications__c FROM Shipment__c WHERE Status__c = :status];
    }

    // AC-001.1, AC-001.2, AC-001.3, AC-001.5 + BR-01
    @IsTest
    static void searchByTrackingAndReference() {
        Shipment__c s = byStatus('In transit');
        PublicTrackingController.SearchResult r =
            PublicTrackingController.search('tracking', '  ' + s.Name.toLowerCase() + ' ,\nRC000999999\n' + s.Name);
        System.assertEquals(1, r.found.size(), 'duplicates collapse, case/spaces ignored');
        System.assertEquals(s.Name, r.found[0].trackingNumber);
        System.assertEquals('Puebla', r.found[0].originCity);
        System.assertEquals(new List<String>{ 'RC000999999' }, r.notFound);
        // BR-01: the public DTO exposes nothing else
        String json = JSON.serialize(r);
        System.assert(!json.contains('SECRET'), 'no internal notes');
        System.assert(!json.contains('Price') && !json.contains('price'), 'no price');
        System.assert(!json.contains('Rita'), 'no recipient data');

        PublicTrackingController.SearchResult byRef = PublicTrackingController.search('reference', 'ref-1, nope');
        System.assertEquals(2, byRef.found.size());
        System.assertEquals(1, byRef.notFound.size());
    }

    @IsTest
    static void searchValidation() {
        List<String> many = new List<String>();
        for (Integer i = 0; i < 11; i++) {
            many.add('RC' + i);
        }
        for (List<String> args : new List<List<String>>{ new List<String>{ 'tracking', String.join(many, ',') },
                new List<String>{ 'tracking', ' ,, ' }, new List<String>{ 'bogus', 'x' } }) {
            try {
                PublicTrackingController.search(args[0], args[1]);
                System.assert(false, 'expected an error');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage());
            }
        }
    }

    // AC-002.1 .. AC-002.3 + throttle
    @IsTest
    static void deliveryDetailsNeedThePostalCode() {
        Shipment__c s = byStatus('In transit');
        PublicTrackingController.DeliveryDetails ok = PublicTrackingController.getDeliveryDetails(s.Name, ' 64000 ');
        System.assertEquals(null, ok.error);
        System.assertEquals('Rita Recipient', ok.recipientName);
        System.assertEquals('Call first', ok.deliveryInstructions);
        System.assertEquals(true, ok.canReschedule);

        PublicTrackingController.DeliveryDetails bad = PublicTrackingController.getDeliveryDetails(s.Name, '00000');
        System.assertEquals('The details do not match this shipment', bad.error);
        System.assertEquals(null, bad.recipientName, 'nothing leaks on mismatch');
        System.assertEquals('The details do not match this shipment', PublicTrackingController.getDeliveryDetails('RC000000000', '64000').error);

        for (Integer i = 0; i < PublicTrackingController.MAX_FAILED; i++) {
            PublicTrackingController.getDeliveryDetails(s.Name, '1111' + i);
        }
        System.assert(PublicTrackingController.getDeliveryDetails(s.Name, '64000').error.contains('Too many'), 'locked even for the right code');
    }

    // AC-003.1 .. AC-003.5
    @IsTest
    static void rescheduleRules() {
        Shipment__c s = byStatus('In transit');
        Shipment__c full = [SELECT Original_Estimated_Delivery__c, Estimated_Delivery__c FROM Shipment__c WHERE Id = :s.Id];
        Date original = full.Original_Estimated_Delivery__c;
        Date tomorrow = ShipmentRules.today().addDays(1);

        System.assertNotEquals(null, PublicTrackingController.reschedule(s.Name, '64000', original.addDays(8), 'x').error, 'AC-003.2 upper bound');
        System.assertNotEquals(null, PublicTrackingController.reschedule(s.Name, '64000', ShipmentRules.today(), 'x').error, 'AC-003.2 lower bound');
        System.assertEquals('The details do not match this shipment', PublicTrackingController.reschedule(s.Name, '99999', tomorrow, 'x').error);

        Date d1 = original.addDays(7);
        PublicTrackingController.DeliveryDetails r1 = PublicTrackingController.reschedule(s.Name, '64000', d1, 'Leave with the doorman');
        System.assertEquals(null, r1.error);
        System.assertEquals(d1, r1.estimatedDelivery);
        System.assertEquals('Leave with the doorman', r1.deliveryInstructions);
        System.assertEquals(1, r1.reschedulesLeft);

        // window is measured from the ORIGINAL estimate, so it cannot be chained further out
        System.assertNotEquals(null, PublicTrackingController.reschedule(s.Name, '64000', d1.addDays(1), 'x').error);

        System.assertEquals(null, PublicTrackingController.reschedule(s.Name, '64000', original, 'again').error);
        // AC-003.4: max 2
        PublicTrackingController.DeliveryDetails r3 = PublicTrackingController.reschedule(s.Name, '64000', original.addDays(2), 'third');
        System.assert(r3.error.contains('2 times'));

        // AC-003.5: audit rows with before/after values
        List<Shipment_Change__c> changes = [SELECT Previous_Date__c, New_Date__c, New_Instructions__c, CreatedDate FROM Shipment_Change__c WHERE Shipment__c = :s.Id ORDER BY CreatedDate, Name];
        System.assertEquals(2, changes.size());
        System.assertEquals(d1, changes[0].New_Date__c);
        System.assertEquals(full.Estimated_Delivery__c, changes[0].Previous_Date__c);
    }

    // AC-003.3
    @IsTest
    static void deliveredCannotBeRescheduled() {
        Shipment__c d = byStatus('Delivered');
        PublicTrackingController.DeliveryDetails r = PublicTrackingController.reschedule(d.Name, '72000', ShipmentRules.today().addDays(1), 'x');
        System.assert(r.error.contains('Picked up or In transit'));
        System.assertEquals(false, PublicTrackingController.getDeliveryDetails(d.Name, '72000').canReschedule);
    }

    // AC-002.4 / AC-002.5
    @IsTest
    static void proofOfDelivery() {
        Shipment__c d = byStatus('Delivered');
        String inTransitName = byStatus('In transit').Name;
        String ok = '{"proofId":"PRF-1","trackingNumber":"' + d.Name + '","signedBy":"Ana López","fileName":"proof.pdf","pdfBase64":"JVBERi0xLjQK"}';
        User site = TestDataFactory.userWith('RutaCargo_Public_Site'); // holds the EntregaYa credential principal, like the guest
        Test.startTest(); // separates the setup DML from the callouts below
        System.runAs(site) {
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, ok));
        PublicTrackingController.ProofFile f = PublicTrackingController.getProofOfDelivery(d.Name, '72000');
        System.assertEquals('proof.pdf', f.fileName);
        System.assertEquals('JVBERi0xLjQK', f.pdfBase64);

        for (ProofMock m : new List<ProofMock>{ new ProofMock(500, ''), new ProofMock(404, ''), new ProofMock(200, 'not json'),
                new ProofMock(200, '{"trackingNumber":"RC000000001","pdfBase64":"AAAA"}') }) {
            Test.setMock(HttpCalloutMock.class, m);
            try {
                PublicTrackingController.getProofOfDelivery(d.Name, '72000');
                System.assert(false, 'expected an error');
            } catch (AuraHandledException e) {
                System.assertEquals('We could not get the proof of delivery, please try again later', e.getMessage());
            }
        }
        try {
            PublicTrackingController.getProofOfDelivery(inTransitName, '64000');
            System.assert(false, 'not delivered yet');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not available'));
        }
        // last: a mismatch writes the failure counter (DML), which must not precede a callout
        System.assertEquals('The details do not match this shipment', PublicTrackingController.getProofOfDelivery(d.Name, '00000').error);
        }
        Test.stopTest();
    }
}
