/**
 * Tests for the proof of delivery download (DeliveryController.downloadProof
 * and EntregaYaClient), run as the real site guest with a mocked EntregaYa.
 * Covers AC-002.4, AC-002.5 and BR-02.
 */
@IsTest
private class ProofOfDeliveryTest {
    private static final String POSTAL_CODE = '64000';
    private static final String PROOF_ID = 'PRF-88231';
    private static final String PDF_BASE64 = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 signed by Ana'));
    private static final String UNAVAILABLE = 'We could not get the proof of delivery, please try again later';

    /** Records the request and answers with a fixed status and body, or throws a timeout. */
    private class EntregaYaMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String body;
        private final Boolean timeout;
        HttpRequest lastRequest;

        EntregaYaMock(Integer statusCode, String body, Boolean timeout) {
            this.statusCode = statusCode;
            this.body = body;
            this.timeout = timeout;
        }

        public HttpResponse respond(HttpRequest request) {
            lastRequest = request;
            if (timeout) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    @TestSetup
    static void setup() {
        Account acme = TestDataFactory.buildCustomerAccount('Acme Test');
        Database.insert(acme, AccessLevel.SYSTEM_MODE);
        Shipment__c delivered = TestDataFactory.buildShipment(acme.Id, 'Delivered');
        delivered.Proof_Id__c = PROOF_ID;
        delivered.Delivered_At__c = Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0);
        Shipment__c inTransit = TestDataFactory.buildShipment(acme.Id, 'In transit');
        Database.insert(new List<Shipment__c>{ delivered, inTransit }, AccessLevel.SYSTEM_MODE);
    }

    private static Shipment__c loadShipment(String status) {
        return [SELECT Id, Name FROM Shipment__c WHERE Status__c = :status WITH SYSTEM_MODE LIMIT 1];
    }

    private static String successBody(String trackingNumber) {
        return JSON.serialize(new Map<String, Object>{
            'proofId' => PROOF_ID,
            'trackingNumber' => trackingNumber,
            'signedBy' => 'Ana Lopez',
            'fileName' => 'proof-of-delivery.pdf',
            'pdfBase64' => PDF_BASE64
        });
    }

    private static DeliveryController.ProofResponse downloadAsGuest(String trackingNumber, String postalCode, EntregaYaMock mock) {
        Test.setMock(HttpCalloutMock.class, mock);
        DeliveryController.ProofResponse response;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            Test.startTest();
            response = DeliveryController.downloadProof(trackingNumber, postalCode);
            Test.stopTest();
        }
        return response;
    }

    // Covers AC-002.4: a Delivered shipment returns the signed PDF fetched from EntregaYa.
    @IsTest
    static void shouldReturnPdf_WhenDeliveredAndEntregaYaAnswers() {
        Shipment__c shipment = loadShipment('Delivered');
        EntregaYaMock mock = new EntregaYaMock(200, successBody(shipment.Name), false);
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, POSTAL_CODE, mock);
        Assert.isTrue(response.success, 'Download succeeded: ' + response.message);
        Assert.areEqual(PDF_BASE64, response.pdfBase64, 'PDF content from EntregaYa');
        Assert.areEqual('proof-of-delivery-' + shipment.Name + '.pdf', response.fileName, 'Safe file name');
    }

    // Covers AC-002.4: the request goes through the EntregaYa Named Credential with GET /proofs/{proofId} and a 10 s timeout.
    @IsTest
    static void shouldCallProofEndpointThroughNamedCredential_WhenDownloading() {
        Shipment__c shipment = loadShipment('Delivered');
        EntregaYaMock mock = new EntregaYaMock(200, successBody(shipment.Name), false);
        downloadAsGuest(shipment.Name, POSTAL_CODE, mock);
        Assert.areEqual('callout:EntregaYa/proofs/' + PROOF_ID, mock.lastRequest.getEndpoint(), 'Endpoint');
        Assert.areEqual('GET', mock.lastRequest.getMethod(), 'Method');
        Assert.isNull(mock.lastRequest.getHeader('Authorization'), 'The key is added by the credential, never by Apex');
    }

    // Covers AC-002.4: the PDF is not stored in Salesforce.
    @IsTest
    static void shouldNotStoreThePdf_WhenDownloading() {
        Shipment__c shipment = loadShipment('Delivered');
        downloadAsGuest(shipment.Name, POSTAL_CODE, new EntregaYaMock(200, successBody(shipment.Name), false));
        Assert.areEqual(0, [SELECT COUNT() FROM ContentVersion WITH SYSTEM_MODE], 'No file saved');
        Assert.areEqual(0, [SELECT COUNT() FROM Attachment WITH SYSTEM_MODE], 'No attachment saved');
    }

    // Covers AC-002.5: a 5xx answer shows the exact retry message.
    @IsTest
    static void shouldShowRetryMessage_WhenEntregaYaFails() {
        Shipment__c shipment = loadShipment('Delivered');
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, POSTAL_CODE, new EntregaYaMock(503, 'Service Unavailable', false));
        Assert.isFalse(response.success, 'Download failed');
        Assert.areEqual(UNAVAILABLE, response.message, 'Exact message');
        Assert.isNull(response.pdfBase64, 'No content');
    }

    // Covers AC-002.5: a timeout (EntregaYa does not respond) shows the exact retry message.
    @IsTest
    static void shouldShowRetryMessage_WhenEntregaYaTimesOut() {
        Shipment__c shipment = loadShipment('Delivered');
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, POSTAL_CODE, new EntregaYaMock(0, null, true));
        Assert.areEqual(UNAVAILABLE, response.message, 'Exact message');
    }

    // Covers AC-002.5: 401/404 answers do not leak details; the same retry message is shown.
    @IsTest
    static void shouldNotLeakProviderError_WhenEntregaYaRejectsKey() {
        Shipment__c shipment = loadShipment('Delivered');
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, POSTAL_CODE, new EntregaYaMock(401, '{"error":"invalid key ey_sk"}', false));
        Assert.areEqual(UNAVAILABLE, response.message, 'Generic message');
        Assert.isFalse(JSON.serialize(response).contains('ey_sk'), 'Provider body not exposed');
    }

    // Covers BR-02: a proof that belongs to another tracking number is never returned.
    @IsTest
    static void shouldRejectProof_WhenResponseIsForAnotherShipment() {
        Shipment__c shipment = loadShipment('Delivered');
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, POSTAL_CODE, new EntregaYaMock(200, successBody('RC000000001'), false));
        Assert.isFalse(response.success, 'Mismatched proof rejected');
        Assert.isNull(response.pdfBase64, 'No content');
    }

    // Covers AC-002.4: a shipment that is not Delivered has no proof, and EntregaYa is not called.
    @IsTest
    static void shouldNotCallEntregaYa_WhenShipmentNotDelivered() {
        Shipment__c shipment = loadShipment('In transit');
        EntregaYaMock mock = new EntregaYaMock(200, successBody(shipment.Name), false);
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, POSTAL_CODE, mock);
        Assert.isFalse(response.success, 'Not available');
        Assert.isNull(mock.lastRequest, 'No callout');
        Assert.areEqual('The proof of delivery is available once the shipment is delivered.', response.message, 'Message');
    }

    // Covers BR-02, AC-002.3: a wrong postal code gets the mismatch message, and EntregaYa is not called.
    @IsTest
    static void shouldDenyDownload_WhenPostalCodeIsWrong() {
        Shipment__c shipment = loadShipment('Delivered');
        EntregaYaMock mock = new EntregaYaMock(200, successBody(shipment.Name), false);
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, '01000', mock);
        Assert.areEqual('The details do not match this shipment', response.message, 'Mismatch message');
        Assert.isNull(mock.lastRequest, 'No callout');
    }

    // Covers AC-002.5: a 200 answer without a PDF is treated as a failure.
    @IsTest
    static void shouldShowRetryMessage_WhenBodyIsNotPdf() {
        Shipment__c shipment = loadShipment('Delivered');
        String body = JSON.serialize(new Map<String, Object>{ 'trackingNumber' => shipment.Name, 'pdfBase64' => EncodingUtil.base64Encode(Blob.valueOf('<html>')) });
        DeliveryController.ProofResponse response = downloadAsGuest(shipment.Name, POSTAL_CODE, new EntregaYaMock(200, body, false));
        Assert.areEqual(UNAVAILABLE, response.message, 'Exact message');
    }

    // Covers BR-02 (security review H-1): wrong codes on the proof path are counted and lock the shipment like the details path.
    @IsTest
    static void shouldCountAndLock_WhenProofRequestedWithWrongCodes() {
        Shipment__c shipment = loadShipment('Delivered');
        EntregaYaMock mock = new EntregaYaMock(200, successBody(shipment.Name), false);
        Test.setMock(HttpCalloutMock.class, mock);
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            for (Integer i = 0; i < 5; i++) {
                DeliveryController.downloadProof(shipment.Name, '0100' + i);
            }
            DeliveryController.ProofResponse locked = DeliveryController.downloadProof(shipment.Name, POSTAL_CODE);
            Assert.isTrue(locked.message.contains('Too many attempts'), 'Locked: ' + locked.message);
        }
        Assert.isNull(mock.lastRequest, 'EntregaYa never called');
        Assert.isNotNull([SELECT Verification_Locked_Until__c FROM Shipment__c WHERE Id = :shipment.Id WITH SYSTEM_MODE].Verification_Locked_Until__c, 'Lock saved');
    }
}
