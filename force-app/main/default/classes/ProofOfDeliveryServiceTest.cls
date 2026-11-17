/**
 * @description Proof of delivery callout of odd/tasks/req-002-003-recipient-delivery.md
 *              (T2, S3): AC-002.4 (GET callout:EntregaYa_API/proofs/{proofId}
 *              with a 10-second timeout and no Authorization header built in
 *              Apex; the proof is returned only when the status is 200, the
 *              trackingNumber is the shipment's and the bytes are a PDF; a body
 *              over 2,500,000 characters is refused before parsing; fileName
 *              sanitized; nothing stored) and AC-002.5 (401, 404, 500 and a
 *              timeout fail with no detail for the caller). Every callout is
 *              answered by an HttpCalloutMock.
 */
@IsTest
private with sharing class ProofOfDeliveryServiceTest {

    private static final String FIRST_PROOF = 'PRF-88231';
    private static final String FIRST_TRACKING = 'RC000001042';
    private static final String SECOND_PROOF = 'PRF-90417';
    private static final String SECOND_TRACKING = 'RC000002077';
    private static final String PDF_TEXT = '%PDF-1.4\n%RutaCargo test proof\n%%EOF\n';
    private static final String PDF_BASE64 = EncodingUtil.base64Encode(Blob.valueOf(PDF_TEXT));
    private static final String ENDPOINT_PREFIX = 'callout:EntregaYa_API/proofs/';

    // Answers every request with one status and body, or throws a timeout;
    // keeps the requests it received.
    private with sharing class ProofMock implements HttpCalloutMock {
        private final Integer statusCode;
        private final String body;
        private final Boolean timeout;
        final List<HttpRequest> requests = new List<HttpRequest>();

        ProofMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
            this.timeout = false;
        }

        ProofMock(Boolean timeout) {
            this.timeout = timeout;
        }

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            if (timeout) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(body);
            return response;
        }
    }

    private static String proofBody(String proofId, String trackingNumber, String fileName, String pdfBase64) {
        return JSON.serialize(new Map<String, Object>{
            'proofId' => proofId,
            'trackingNumber' => trackingNumber,
            'signedBy' => 'Ana López',
            'fileName' => fileName,
            'pdfBase64' => pdfBase64
        });
    }

    private static ProofMock mockAnswering(Integer statusCode, String body) {
        ProofMock mock = new ProofMock(statusCode, body);
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    // Fetches and returns the exception, failing when nothing is thrown.
    private static ProofOfDeliveryService.ProofOfDeliveryException fetchFailure(String proofId, String trackingNumber) {
        try {
            ProofOfDeliveryService.fetch(proofId, trackingNumber);
        } catch (ProofOfDeliveryService.ProofOfDeliveryException expected) {
            return expected;
        }
        Assert.fail('The fetch must fail with ProofOfDeliveryException');
        return null;
    }

    // A 200 body whose pdfBase64 is a valid PDF and whose length is exactly the given one.
    private static String bodyOfLength(Integer length) {
        // The file name absorbs the remainder, so the base64 stays a multiple of 4.
        String empty = proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', 'JVBERi0x');
        Integer remainder = Math.mod(length - empty.length(), 4);
        String fileName = 'proof-of-delivery' + 'x'.repeat(remainder) + '.pdf';
        Integer padding = length - empty.length() - remainder;
        return proofBody(FIRST_PROOF, FIRST_TRACKING, fileName, 'JVBERi0x' + 'AAAA'.repeat(padding / 4));
    }

    // ─── AC-002.4: the proof is returned ─────────────────────────────────

    @IsTest
    static void shouldReturnProof_WhenFirstResponseMatchesShipment() {
        // AC-002.4: 200 with the shipment's trackingNumber and a small PDF.
        ProofMock mock = mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.Proof proof = ProofOfDeliveryService.fetch(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual('proof-of-delivery.pdf', proof.fileName, 'The file name');
        Assert.areEqual('Ana López', proof.signedBy, 'Who signed');
        Assert.areEqual(PDF_BASE64, proof.pdfBase64, 'The PDF as base64');
        Assert.areEqual(1, mock.requests.size(), 'One callout');
        Assert.areEqual(ENDPOINT_PREFIX + FIRST_PROOF, mock.requests[0].getEndpoint(), 'The proof path');
        Assert.areEqual('GET', mock.requests[0].getMethod(), 'A GET');
    }

    @IsTest
    static void shouldReturnProof_WhenSecondResponseMatchesShipment() {
        // AC-002.4: a second proof id and tracking number, so no value is hard-coded.
        String otherPdf = EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.7\n%second\n%%EOF\n'));
        ProofMock mock = mockAnswering(200, proofBody(SECOND_PROOF, SECOND_TRACKING, 'POD_90417.pdf', otherPdf));

        Test.startTest();
        ProofOfDeliveryService.Proof proof = ProofOfDeliveryService.fetch(SECOND_PROOF, SECOND_TRACKING);
        Test.stopTest();

        Assert.areEqual('POD_90417.pdf', proof.fileName, 'The file name');
        Assert.areEqual(otherPdf, proof.pdfBase64, 'The PDF as base64');
        Assert.areEqual(ENDPOINT_PREFIX + SECOND_PROOF, mock.requests[0].getEndpoint(), 'The proof path');
    }

    @IsTest
    static void shouldUseTenSecondTimeoutAndCredentialMergeField_WhenCallingOut() {
        // AC-002.4 (P2, E11): a 10-second timeout; the Authorization header is the
        // Named Credential's password merge field, never a key.
        ProofMock mock = mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.fetch(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(10000, ProofOfDeliveryService.appliedTimeoutMillis, 'The timeout set on the request');
        Assert.areEqual('Bearer {!$Credential.Password}', mock.requests[0].getHeader('Authorization'),
            'The header is the Named Credential password merge field');
    }

    @IsTest
    static void shouldAcceptBody_WhenLengthIsExactlyTheCap() {
        // AC-002.4: 2,500,000 characters is the largest accepted body.
        String body = bodyOfLength(ProofOfDeliveryService.MAX_BODY_LENGTH);
        mockAnswering(200, body);

        Test.startTest();
        ProofOfDeliveryService.Proof proof = ProofOfDeliveryService.fetch(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(2500000, body.length(), 'Fixture: the body is exactly at the cap');
        Assert.areEqual('JVBERi0x', proof.pdfBase64?.left(8), 'The proof is returned');
    }

    // ─── AC-002.4: the response is refused ───────────────────────────────

    @IsTest
    static void shouldRefuse_WhenTrackingNumberIsAnotherShipments() {
        // AC-002.4 (E7): Proof_Id__c is agent-editable; another shipment's proof is refused.
        mockAnswering(200, proofBody(FIRST_PROOF, SECOND_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.MISMATCH, failure.reason, 'Another shipment\'s proof is refused as a mismatch');
    }

    @IsTest
    static void shouldRefuse_WhenTrackingNumberDiffersOnlyInCase() {
        // AC-002.4 (E7): the comparison is exact.
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING.toLowerCase(), 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.MISMATCH, failure.reason, 'A tracking number in another case is refused as a mismatch');
    }

    @IsTest
    static void shouldRefuse_WhenTrackingNumberIsMissing() {
        // AC-002.4 (E7): no trackingNumber, no proof.
        mockAnswering(200, proofBody(FIRST_PROOF, null, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.MISMATCH, failure.reason, 'A response without trackingNumber is refused as a mismatch');
    }

    @IsTest
    static void shouldRefuse_WhenBytesAreNotPdf() {
        // AC-002.4: valid base64 whose bytes do not start with %PDF-.
        String text = EncodingUtil.base64Encode(Blob.valueOf('<html>not a pdf</html>'));
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', text));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.NOT_PDF, failure.reason, 'Bytes that are not a PDF are refused as not a PDF');
    }

    @IsTest
    static void shouldRefuse_WhenPdfBase64IsNotBase64() {
        // AC-002.4: a pdfBase64 that does not decode is refused.
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', '%PDF-1.4 raw text!'));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.NOT_PDF, failure.reason, 'A pdfBase64 that is not base64 is refused as not a PDF');
    }

    @IsTest
    static void shouldRefuse_WhenPdfBase64IsMissing() {
        // AC-002.4: no pdfBase64, no proof.
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', null));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.NOT_PDF, failure.reason, 'A response without pdfBase64 is refused as not a PDF');
    }

    @IsTest
    static void shouldRefuse_WhenBodyIsNotJson() {
        // AC-002.4: a 200 that is not a JSON object is refused.
        mockAnswering(200, '<html>maintenance</html>');

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.MALFORMED, failure.reason, 'A body that is not JSON is refused as malformed');
    }

    @IsTest
    static void shouldRefuse_WhenBodyIsOneCharacterOverTheCap() {
        // AC-002.4: 2,500,001 characters (a valid proof plus one trailing space, still
        // valid JSON) is refused for its size, before parsing.
        mockAnswering(200, bodyOfLength(ProofOfDeliveryService.MAX_BODY_LENGTH) + ' ');

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.isNotNull(failure, 'A body over the cap is refused');
        Assert.areEqual(ProofOfDeliveryService.Reason.TOO_LARGE, failure.reason, 'Refused for its size, before parsing');
    }

    @IsTest
    static void shouldRefuse_WhenBodyIsWellOverTheCap() {
        // AC-002.4: a valid proof of 2,500,004 characters is refused for its size.
        mockAnswering(200, bodyOfLength(ProofOfDeliveryService.MAX_BODY_LENGTH + 4));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.TOO_LARGE, failure.reason, 'Refused for its size');
    }

    // ─── AC-002.5: EntregaYa errors ──────────────────────────────────────

    @IsTest
    static void shouldFail_WhenEntregaYaAnswers401() {
        // AC-002.5: a wrong key.
        mockAnswering(401, '{"error":"Unauthorized"}');

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.STATUS, failure.reason, '401 fails');
    }

    @IsTest
    static void shouldFail_WhenEntregaYaAnswers404() {
        // AC-002.5: the proof does not exist.
        mockAnswering(404, '{"error":"Not Found"}');

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.STATUS, failure.reason, '404 fails');
    }

    @IsTest
    static void shouldFail_WhenEntregaYaAnswers500() {
        // AC-002.5: the service is unavailable.
        mockAnswering(500, 'Internal Server Error');

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.STATUS, failure.reason, '500 fails');
    }

    @IsTest
    static void shouldFail_WhenEntregaYaAnswers201() {
        // AC-002.4: only 200 is accepted, even with a valid proof body.
        mockAnswering(201, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.STATUS, failure.reason, '201 fails');
    }

    @IsTest
    static void shouldFail_WhenCalloutTimesOut() {
        // AC-002.5: a timeout (CalloutException) fails like any other error.
        Test.setMock(HttpCalloutMock.class, new ProofMock(true));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.CALLOUT, failure.reason, 'A timeout fails');
    }

    @IsTest
    static void shouldKeepStatusTextOutOfMessage_WhenEntregaYaFails() {
        // AC-002.5: the failure carries no response text, so a caller cannot leak it.
        mockAnswering(401, '{"error":"Unauthorized: key rejected"}');

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.isFalse(failure.getMessage().containsIgnoreCase('Unauthorized'), 'No response text in the message');
        Assert.isFalse(failure.getMessage().contains('key rejected'), 'No response body in the message');
    }

    // ─── AC-002.4 (P4): the proof id ─────────────────────────────────────

    @IsTest
    static void shouldNotCallOut_WhenProofIdHasPathCharacters() {
        // AC-002.4 (P4): a proof id cannot change the request path.
        ProofMock mock = mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure('../admin/keys', FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.INVALID_PROOF_ID, failure.reason, 'Refused before the callout');
        Assert.areEqual(0, mock.requests.size(), 'No callout');
    }

    @IsTest
    static void shouldNotCallOut_WhenProofIdHasQueryCharacters() {
        // AC-002.4 (P4): no query string or fragment.
        ProofMock mock = mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure('PRF-1?all=true#x', FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.INVALID_PROOF_ID, failure.reason, 'Refused before the callout');
        Assert.areEqual(0, mock.requests.size(), 'No callout');
    }

    @IsTest
    static void shouldNotCallOut_WhenProofIdIsNull() {
        // AC-002.4 (P4): no proof id, no callout.
        ProofMock mock = mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure(null, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.INVALID_PROOF_ID, failure.reason, 'Refused before the callout');
        Assert.areEqual(0, mock.requests.size(), 'No callout');
    }

    @IsTest
    static void shouldNotCallOut_WhenProofIdIsOver100Characters() {
        // AC-002.4 (P4): at most 100 characters.
        ProofMock mock = mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.ProofOfDeliveryException failure = fetchFailure('P'.repeat(101), FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(ProofOfDeliveryService.Reason.INVALID_PROOF_ID, failure.reason, 'Refused before the callout');
        Assert.areEqual(0, mock.requests.size(), 'No callout');
    }

    @IsTest
    static void shouldCallOut_WhenProofIdIsExactly100Characters() {
        // AC-002.4 (P4): 100 letters, digits, '_' and '-' are accepted.
        String proofId = 'A_b-9'.repeat(20);
        ProofMock mock = mockAnswering(200, proofBody(proofId, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.fetch(proofId, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual(1, mock.requests.size(), 'One callout');
        Assert.areEqual(ENDPOINT_PREFIX + proofId, mock.requests[0].getEndpoint(), 'The 100-character id is requested');
    }

    // ─── AC-002.4: the file name ─────────────────────────────────────────

    @IsTest
    static void shouldSanitizeFileName_WhenItHasPathOrUnsafeCharacters() {
        // AC-002.4: only [A-Za-z0-9._-] are kept.
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, '../../Entrega <Ana>"López".pdf', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.Proof proof = ProofOfDeliveryService.fetch(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual('....EntregaAnaLpez.pdf', proof.fileName, 'Unsafe characters are removed');
    }

    @IsTest
    static void shouldUseDefaultFileName_WhenFileNameIsMissing() {
        // AC-002.4: no fileName, the default.
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, null, PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.Proof proof = ProofOfDeliveryService.fetch(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual('proof-of-delivery.pdf', proof.fileName, 'The default file name');
    }

    @IsTest
    static void shouldUseDefaultFileName_WhenNothingSafeRemains() {
        // AC-002.4: a name with no allowed character becomes the default.
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, '<>"/ \\', PDF_BASE64));

        Test.startTest();
        ProofOfDeliveryService.Proof proof = ProofOfDeliveryService.fetch(FIRST_PROOF, FIRST_TRACKING);
        Test.stopTest();

        Assert.areEqual('proof-of-delivery.pdf', proof.fileName, 'The default file name');
    }

    // ─── AC-002.4: nothing stored ────────────────────────────────────────

    @IsTest
    static void shouldStoreNothing_WhenProofIsReturned() {
        // AC-002.4: no ContentVersion, Attachment or Document is created.
        mockAnswering(200, proofBody(FIRST_PROOF, FIRST_TRACKING, 'proof-of-delivery.pdf', PDF_BASE64));
        Integer before = [SELECT COUNT() FROM ContentVersion WITH SYSTEM_MODE]
            + [SELECT COUNT() FROM Attachment WITH SYSTEM_MODE] + [SELECT COUNT() FROM Document WITH SYSTEM_MODE];

        Test.startTest();
        ProofOfDeliveryService.fetch(FIRST_PROOF, FIRST_TRACKING);
        Integer dml = Limits.getDmlStatements();
        Test.stopTest();

        Integer after = [SELECT COUNT() FROM ContentVersion WITH SYSTEM_MODE]
            + [SELECT COUNT() FROM Attachment WITH SYSTEM_MODE] + [SELECT COUNT() FROM Document WITH SYSTEM_MODE];
        Assert.areEqual(before, after, 'No file is stored');
        Assert.areEqual(0, dml, 'The service makes no DML');
    }
}
