/**
 * @description Fetches a proof of delivery PDF from EntregaYa (req-002-003 S3;
 *              AC-002.4, AC-002.5; policy P2, P4, X7, X9). The request is
 *              GET callout:EntregaYa_API/proofs/{proofId} with a 10-second
 *              timeout through the Named Credential EntregaYa_API (password
 *              authentication, named principal; E11): the base URL and the API
 *              key (its password) are entered by hand in Setup by the owner, and
 *              the header is "Authorization: Bearer {!$Credential.Password}", a
 *              merge field the platform resolves when it sends the request, so
 *              the key is never in Apex, in the repository or in a log. The
 *              guest needs no permission for it. The proof id is
 *              validated against ^[A-Za-z0-9_-]{1,100}$ and URL-encoded, so it
 *              cannot change the path. The response is accepted only when the
 *              status is 200, the body is at most 2,500,000 characters (checked
 *              before parsing: a larger base64 body, its parsed copy and the
 *              decoded bytes would not fit in the 6 MB heap, and a LimitException
 *              cannot be caught), the trackingNumber is exactly the shipment's
 *              (Proof_Id__c is agent-editable, E7) and pdfBase64 decodes to bytes
 *              that start with "%PDF-". Nothing is stored and nothing is logged.
 *              Every failure is a ProofOfDeliveryException with a fixed message
 *              and a Reason: it never carries the response's status text, body
 *              or headers. Called only by RecipientDeliveryController.downloadProof
 *              after the recipient is verified; it has no guest class access.
 */
public with sharing class ProofOfDeliveryService {

    /** @description Characters accepted in a response body (≈1.8 MB of PDF). */
    public static final Integer MAX_BODY_LENGTH = 2500000;
    /** @description The callout timeout recommended by EntregaYa. */
    public static final Integer TIMEOUT_MILLIS = 10000;
    /** @description The file name used when EntregaYa sends none that is safe. */
    public static final String DEFAULT_FILE_NAME = 'proof-of-delivery.pdf';

    private static final String ENDPOINT_PREFIX = 'callout:EntregaYa_API/proofs/';
    // A merge field of the Named Credential, resolved by the platform; never a key.
    // SECURITY-JUSTIFICATION: E11 - the platform refuses the site guest's callout
    // through an External Credential unless the guest gets Read on
    // UserExternalCredential, an object permission the project rule forbids, so
    // EntregaYa_API is a legacy password Named Credential (P2 prefers External
    // Credentials) and this Authorization header is its password merge field.
    // Scope: one header of GET callout:EntregaYa_API/proofs/{proofId} only; merge
    // fields are allowed in headers, not in the body. Compensating control: the
    // key lives only in the org's Named Credential, entered by hand by the owner;
    // the header value is this constant, never user input; the proof id is
    // validated against ^[A-Za-z0-9_-]{1,100}$ and URL-encoded; the request,
    // response and key are never logged or returned. (pending owner approval, 2026-11-17)
    private static final String AUTHORIZATION_MERGE_FIELD = 'Bearer {!$Credential.Password}';
    private static final Integer HTTP_OK = 200;
    private static final Pattern PROOF_ID = Pattern.compile('^[A-Za-z0-9_-]{1,100}$');
    private static final String UNSAFE_FILE_NAME_CHARACTERS = '[^A-Za-z0-9._-]';
    // "%PDF-" in hexadecimal.
    private static final String PDF_MAGIC_HEX = '255044462d';
    // Base64 characters that decode to the first 6 bytes, enough for "%PDF-".
    private static final Integer PREFIX_BASE64_LENGTH = 8;

    // The timeout set on the last request (HttpRequest has no getter), for tests.
    @TestVisible
    private static Integer appliedTimeoutMillis;

    /** @description Why a proof could not be returned; never shown to a recipient. */
    public enum Reason { INVALID_PROOF_ID, CALLOUT, STATUS, TOO_LARGE, MALFORMED, MISMATCH, NOT_PDF }

    /** @description A proof of delivery: what the verified recipient downloads. */
    public with sharing class Proof {
        /** @description The file name, only [A-Za-z0-9._-]. */
        public String fileName { get; private set; }
        /** @description Who signed for the delivery. */
        public String signedBy { get; private set; }
        /** @description The PDF as base64, exactly as EntregaYa sent it. */
        public String pdfBase64 { get; private set; }

        private Proof(String fileName, String signedBy, String pdfBase64) {
            this.fileName = fileName;
            this.signedBy = signedBy;
            this.pdfBase64 = pdfBase64;
        }
    }

    /**
     * @description Any failure to get a valid proof. The message is fixed per
     *              reason and never includes response text, headers or the key.
     */
    public with sharing class ProofOfDeliveryException extends Exception {
        /** @description Why the proof could not be returned. */
        public Reason reason { get; private set; }
    }

    /**
     * @description Fetches the proof and checks that it belongs to the shipment.
     * @param proofId the shipment's Proof_Id__c
     * @param trackingNumber the shipment's Name; the response must carry exactly it
     * @return the proof (never null)
     * @throws ProofOfDeliveryException on any failure, before or after the callout
     */
    public static Proof fetch(String proofId, String trackingNumber) {
        if (String.isBlank(proofId) || !PROOF_ID.matcher(proofId).matches()) {
            throw failure(Reason.INVALID_PROOF_ID, null);
        }
        // The body is not kept after parsing: only the parsed copy stays on the heap.
        return proofOf(parse(receiveBody(proofId)), trackingNumber);
    }

    // ─── Internals ───────────────────────────────────────────────────────

    private static HttpRequest newRequest(String proofId) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(ENDPOINT_PREFIX + EncodingUtil.urlEncode(proofId, 'UTF-8'));
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setHeader('Authorization', AUTHORIZATION_MERGE_FIELD);
        request.setTimeout(TIMEOUT_MILLIS);
        appliedTimeoutMillis = TIMEOUT_MILLIS;
        return request;
    }

    // The body of a 200 answer of at most MAX_BODY_LENGTH characters. A timeout
    // or an unreachable host is a CalloutException; its text is dropped.
    private static String receiveBody(String proofId) {
        HttpResponse response;
        try {
            response = new Http().send(newRequest(proofId));
        } catch (CalloutException unreachable) {
            throw failure(Reason.CALLOUT, unreachable);
        }
        if (response.getStatusCode() != HTTP_OK) {
            throw failure(Reason.STATUS, null);
        }
        String body = response.getBody();
        if (body == null || body.length() > MAX_BODY_LENGTH) {
            throw failure(Reason.TOO_LARGE, null);
        }
        return body;
    }

    private static Map<String, Object> parse(String body) {
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (JSONException notJson) {
            throw failure(Reason.MALFORMED, notJson);
        } catch (TypeException notAnObject) {
            throw failure(Reason.MALFORMED, notAnObject);
        }
    }

    private static Proof proofOf(Map<String, Object> fields, String trackingNumber) {
        String responseTracking = stringOf(fields, 'trackingNumber');
        if (responseTracking == null || trackingNumber == null || !responseTracking.equals(trackingNumber)) {
            throw failure(Reason.MISMATCH, null);
        }
        String pdfBase64 = stringOf(fields, 'pdfBase64');
        if (!isPdf(pdfBase64)) {
            throw failure(Reason.NOT_PDF, null);
        }
        return new Proof(safeFileName(stringOf(fields, 'fileName')), stringOf(fields, 'signedBy'), pdfBase64);
    }

    // The value when it is a String, otherwise null.
    private static String stringOf(Map<String, Object> fields, String key) {
        Object value = fields.get(key);
        return value instanceof String ? (String) value : null;
    }

    // The bytes must start with "%PDF-" and the whole value must be base64: its
    // length a multiple of 4 and its decoded size exactly the size that length
    // and padding give (a character that is not base64 is refused or dropped by
    // the decoder, so the size would differ).
    private static Boolean isPdf(String pdfBase64) {
        if (String.isBlank(pdfBase64) || pdfBase64.length() < PREFIX_BASE64_LENGTH
                || Math.mod(pdfBase64.length(), 4) != 0) {
            return false;
        }
        try {
            String prefixHex = EncodingUtil.convertToHex(
                EncodingUtil.base64Decode(pdfBase64.left(PREFIX_BASE64_LENGTH)));
            if (!prefixHex.startsWith(PDF_MAGIC_HEX)) {
                return false;
            }
            return EncodingUtil.base64Decode(pdfBase64).size() == decodedSize(pdfBase64);
        } catch (StringException notBase64) {
            return false;
        }
    }

    private static Integer decodedSize(String base64) {
        Integer padding = base64.endsWith('==') ? 2 : (base64.endsWith('=') ? 1 : 0);
        return base64.length() / 4 * 3 - padding;
    }

    private static String safeFileName(String fileName) {
        String safe = fileName == null ? '' : fileName.replaceAll(UNSAFE_FILE_NAME_CHARACTERS, '');
        return String.isBlank(safe) ? DEFAULT_FILE_NAME : safe;
    }

    private static ProofOfDeliveryException failure(Reason reason, Exception cause) {
        ProofOfDeliveryException error = cause == null
            ? new ProofOfDeliveryException('Proof of delivery unavailable: ' + reason.name())
            : new ProofOfDeliveryException('Proof of delivery unavailable: ' + reason.name(), cause);
        error.reason = reason;
        return error;
    }
}
