/**
 * Tests for delivery details, proof of delivery and rescheduling (REQ-002, REQ-003).
 */
@IsTest
private class RecipientServiceTest {
    // Blank means the provider did not say; a value is returned in the proof body.
    private static String proofTracking = '';
    private static Integer calls = 0;

    private class ProofMock implements HttpCalloutMock {
        private Integer status;
        private Boolean fail;
        ProofMock(Integer status, Boolean fail) {
            this.status = status;
            this.fail = fail;
        }
        public HttpResponse respond(HttpRequest request) {
            calls++;
            if (fail) {
                throw new CalloutException('timeout');
            }
            Assert.isTrue(request.getEndpoint().startsWith('callout:EntregaYa/proofs/'), 'uses the Named Credential');
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody('{"proofId":"PRF-1","trackingNumber":"' + proofTracking + '","signedBy":"Ana Lopez","fileName":"proof-of-delivery.pdf","pdfBase64":"JVBERi0xLjQK"}');
            return response;
        }
    }

    @TestSetup
    static void setup() {
        TestDataFactory.grantSupportAccess();
        TestDataFactory.createShipment(null, 'In transit', 'R-1');
        Shipment__c delivered = TestDataFactory.createShipment(null, 'Delivered', 'R-2');
        delivered.Proof_Id__c = 'PRF-1';
        update delivered;
        TestDataFactory.createShipment(null, 'Requested', 'R-3');
        TestDataFactory.createShipment(null, 'Picked up', 'R-4');
    }

    private static String tn(String status) {
        return [SELECT Name FROM Shipment__c WHERE Status__c = :status LIMIT 1].Name;
    }

    @IsTest
    static void detailsShownWithCorrectPostalCode_AC_002_1_AC_002_2() {
        RutaCargoDtos.DeliveryDetails d = RecipientService.getDetails(tn('In transit'), TestDataFactory.POSTAL);
        Assert.areEqual('OK', d.outcome);
        Assert.areEqual('Luis Perez', d.recipientName);
        Assert.areEqual('Calle Hidalgo 45', d.recipientAddress);
        Assert.areEqual('8187654321', d.recipientPhone);
        Assert.areEqual(ShipmentRules.today().addDays(3), d.estimatedDelivery);
        Assert.areEqual('Leave with the doorman', d.deliveryInstructions);
    }

    @IsTest
    static void wrongPostalCodeGivesStandardMessage_AC_002_3() {
        RutaCargoDtos.DeliveryDetails d = RecipientService.getDetails(tn('In transit'), '99999');
        Assert.areEqual('MISMATCH', d.outcome);
        Assert.areEqual('The details do not match this shipment', d.message);
        Assert.isNull(d.recipientName, 'no personal data on mismatch (BR-02)');
    }

    @IsTest
    static void unknownTrackingGivesSameMessage_BR_02() {
        RutaCargoDtos.DeliveryDetails d = RecipientService.getDetails('RC000000000', TestDataFactory.POSTAL);
        Assert.areEqual('The details do not match this shipment', d.message);
    }

    @IsTest
    static void fiveWrongCodesLockTheShipment_BR_02() {
        String number1 = tn('In transit');
        for (Integer i = 0; i < 5; i++) {
            RecipientService.getDetails(number1, '9999' + i);
        }
        RutaCargoDtos.DeliveryDetails locked = RecipientService.getDetails(number1, TestDataFactory.POSTAL);
        Assert.areEqual('LOCKED', locked.outcome, 'even the right code is refused while locked');
        Assert.isNull(locked.recipientName);
    }

    @IsTest
    static void proofDownloadedForDeliveredShipment_AC_002_4() {
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, false));
        Test.startTest();
        RutaCargoDtos.ProofResult proof = RecipientService.getProof(tn('Delivered'), TestDataFactory.POSTAL);
        Test.stopTest();
        Assert.areEqual('OK', proof.outcome);
        Assert.areEqual('JVBERi0xLjQK', proof.pdfBase64);
        Assert.areEqual('proof-of-delivery.pdf', proof.fileName);
        Assert.areEqual(0, [SELECT COUNT() FROM ContentVersion], 'the PDF is not stored in Salesforce');
        Assert.areEqual(1, calls, 'exactly one callout, through the Named Credential endpoint asserted in the mock');
    }

    @IsTest
    static void proofOfAnotherShipmentIsNeverReturned_BR_02() {
        proofTracking = 'RC999999998';
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, false));
        Test.startTest();
        RutaCargoDtos.ProofResult proof = RecipientService.getProof(tn('Delivered'), TestDataFactory.POSTAL);
        Test.stopTest();
        Assert.areEqual(1, calls, 'the callout happened and its answer was refused');
        Assert.areEqual('UNAVAILABLE', proof.outcome);
        Assert.isNull(proof.pdfBase64);
    }

    @IsTest
    static void proofIsAcceptedWhenItsTrackingNumberMatches_AC_002_4() {
        proofTracking = tn('Delivered');
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, false));
        Test.startTest();
        RutaCargoDtos.ProofResult proof = RecipientService.getProof(tn('Delivered'), TestDataFactory.POSTAL);
        Test.stopTest();
        Assert.areEqual('OK', proof.outcome);
        Assert.areEqual(1, calls);
    }

    @IsTest
    static void proofNeedsCorrectPostalCode_BR_02() {
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, false));
        RutaCargoDtos.ProofResult proof = RecipientService.getProof(tn('Delivered'), '11111');
        Assert.areEqual('MISMATCH', proof.outcome);
        Assert.isNull(proof.pdfBase64);
    }

    @IsTest
    static void proofRefusedWhenNotDelivered_AC_002_4() {
        RutaCargoDtos.ProofResult proof = RecipientService.getProof(tn('In transit'), TestDataFactory.POSTAL);
        Assert.areEqual('REJECTED', proof.outcome);
        Assert.areEqual(0, calls, 'no callout is attempted for a shipment that is not delivered');
    }

    @IsTest
    static void proofServerErrorShowsFriendlyMessage_AC_002_5() {
        Test.setMock(HttpCalloutMock.class, new ProofMock(503, false));
        Test.startTest();
        RutaCargoDtos.ProofResult proof = RecipientService.getProof(tn('Delivered'), TestDataFactory.POSTAL);
        Test.stopTest();
        Assert.areEqual(1, calls, 'EntregaYa was really called');
        Assert.areEqual('UNAVAILABLE', proof.outcome);
        Assert.areEqual('We could not get the proof of delivery, please try again later', proof.message);
    }

    @IsTest
    static void proofTimeoutShowsFriendlyMessage_AC_002_5() {
        Test.setMock(HttpCalloutMock.class, new ProofMock(200, true));
        Test.startTest();
        RutaCargoDtos.ProofResult proof = RecipientService.getProof(tn('Delivered'), TestDataFactory.POSTAL);
        Test.stopTest();
        Assert.areEqual(1, calls, 'EntregaYa was really called');
        Assert.areEqual('UNAVAILABLE', proof.outcome);
        Assert.areEqual('We could not get the proof of delivery, please try again later', proof.message);
    }

    @IsTest
    static void rescheduleSavesDateInstructionsAndAuditRow_AC_003_1_AC_003_5() {
        String number1 = tn('In transit');
        Date newDate = ShipmentRules.today().addDays(6);
        RutaCargoDtos.DeliveryDetails d = RecipientService.reschedule(number1, TestDataFactory.POSTAL, newDate, 'Call before arriving');
        Assert.areEqual('OK', d.outcome);
        Assert.areEqual(newDate, d.estimatedDelivery, 'new date is shown');
        Shipment__c saved = [SELECT Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c FROM Shipment__c WHERE Name = :number1];
        Assert.areEqual(newDate, saved.Estimated_Delivery__c);
        Assert.areEqual('Call before arriving', saved.Delivery_Instructions__c);
        Assert.areEqual(1, saved.Reschedule_Count__c);
        List<Delivery_Change__c> changes = [SELECT Previous_Date__c, New_Date__c, CreatedDate FROM Delivery_Change__c WHERE Shipment__r.Name = :number1];
        Assert.areEqual(1, changes.size(), 'support can see each change');
        Assert.areEqual(ShipmentRules.today().addDays(3), changes[0].Previous_Date__c);
        Assert.areEqual(newDate, changes[0].New_Date__c);
        Assert.isNotNull(changes[0].CreatedDate, 'shows when the change was made');
    }

    @IsTest
    static void rescheduleDateOutsideWindowRejected_AC_003_2() {
        String number1 = tn('In transit');
        RutaCargoDtos.DeliveryDetails tooLate = RecipientService.reschedule(number1, TestDataFactory.POSTAL, ShipmentRules.today().addDays(11), null);
        Assert.areEqual('REJECTED', tooLate.outcome, 'original +7 is day 10');
        RutaCargoDtos.DeliveryDetails today = RecipientService.reschedule(number1, TestDataFactory.POSTAL, ShipmentRules.today(), null);
        Assert.areEqual('REJECTED', today.outcome);
        Assert.areEqual(0, [SELECT COUNT() FROM Delivery_Change__c]);
    }

    @IsTest
    static void rescheduleLastAllowedDayAccepted_AC_003_2() {
        RutaCargoDtos.DeliveryDetails d = RecipientService.reschedule(tn('In transit'), TestDataFactory.POSTAL, ShipmentRules.today().addDays(10), null);
        Assert.areEqual('OK', d.outcome);
    }

    @IsTest
    static void rescheduleOnlyWhenPickedUpOrInTransit_AC_003_3() {
        Date newDate = ShipmentRules.today().addDays(5);
        Assert.areEqual('REJECTED', RecipientService.reschedule(tn('Delivered'), TestDataFactory.POSTAL, newDate, null).outcome);
        Assert.areEqual('REJECTED', RecipientService.reschedule(tn('Requested'), TestDataFactory.POSTAL, newDate, null).outcome);
        Assert.areEqual('OK', RecipientService.reschedule(tn('Picked up'), TestDataFactory.POSTAL, newDate, null).outcome);
        Assert.areEqual('OK', RecipientService.reschedule(tn('In transit'), TestDataFactory.POSTAL, newDate, null).outcome);
    }

    @IsTest
    static void rescheduleAtMostTwice_AC_003_4() {
        String number1 = tn('In transit');
        Assert.areEqual('OK', RecipientService.reschedule(number1, TestDataFactory.POSTAL, ShipmentRules.today().addDays(4), null).outcome);
        Assert.areEqual('OK', RecipientService.reschedule(number1, TestDataFactory.POSTAL, ShipmentRules.today().addDays(5), null).outcome);
        RutaCargoDtos.DeliveryDetails third = RecipientService.reschedule(number1, TestDataFactory.POSTAL, ShipmentRules.today().addDays(6), null);
        Assert.areEqual('REJECTED', third.outcome);
        Assert.areEqual(2, [SELECT COUNT() FROM Delivery_Change__c]);
    }

    @IsTest
    static void rescheduleRequiresPostalCode_BR_02() {
        RutaCargoDtos.DeliveryDetails d = RecipientService.reschedule(tn('In transit'), '00000', ShipmentRules.today().addDays(5), 'x');
        Assert.areEqual('MISMATCH', d.outcome);
        Assert.areEqual(0, [SELECT COUNT() FROM Delivery_Change__c]);
    }
}
