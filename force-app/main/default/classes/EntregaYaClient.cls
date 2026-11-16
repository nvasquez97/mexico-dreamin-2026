/**
 * Calls the EntregaYa API through the EntregaYa Named Credential. The API key
 * lives in the EntregaYa External Credential and is added by the platform; it
 * never appears in Apex, tests, metadata or logs.
 * GET {base URL}/proofs/{proofId}, 10-second timeout (provider recommendation).
 */
public inherited sharing class EntregaYaClient {
    public static final Integer TIMEOUT_MS = 10000;
    private static final String NAMED_CREDENTIAL = 'callout:EntregaYa';
    /** Base64 of "%PDF": every PDF starts with these bytes. */
    private static final String PDF_BASE64_PREFIX = 'JVBER';

    /** Any failure getting a proof. The message is internal; never show it on the site. */
    public class EntregaYaException extends Exception {}

    /** The proof PDF, kept in memory only (AC-002.4: not stored in Salesforce). */
    public class ProofFile {
        public String pdfBase64;
        public String signedBy;
    }

    private class ProofPayload {
        String proofId;
        String trackingNumber;
        String signedBy;
        String fileName;
        String pdfBase64;
    }

    /**
     * @param proofId proof identifier saved on the shipment (never taken from the browser)
     * @param expectedTrackingNumber tracking number the proof must belong to
     * @return the proof PDF
     * @throws EntregaYaException on timeout, non-200 answer, invalid body or a proof of another shipment
     */
    public static ProofFile getProof(String proofId, String expectedTrackingNumber) {
        if (String.isBlank(proofId)) {
            throw new EntregaYaException('Missing proof identifier');
        }
        HttpRequest request = new HttpRequest();
        request.setEndpoint(NAMED_CREDENTIAL + '/proofs/' + EncodingUtil.urlEncode(proofId, 'UTF-8'));
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(TIMEOUT_MS);
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException e) {
            throw new EntregaYaException('EntregaYa did not respond', e);
        }
        if (response.getStatusCode() != 200) {
            throw new EntregaYaException('EntregaYa answered HTTP ' + response.getStatusCode());
        }
        return parseProof(response.getBody(), expectedTrackingNumber);
    }

    private static ProofFile parseProof(String body, String expectedTrackingNumber) {
        ProofPayload payload;
        try {
            payload = (ProofPayload) JSON.deserialize(body, ProofPayload.class);
        } catch (JSONException e) {
            throw new EntregaYaException('Invalid EntregaYa body', e);
        }
        if (payload == null || payload.trackingNumber != expectedTrackingNumber) {
            throw new EntregaYaException('The proof does not belong to the shipment');
        }
        if (String.isBlank(payload.pdfBase64) || !payload.pdfBase64.startsWith(PDF_BASE64_PREFIX)) {
            throw new EntregaYaException('The proof is not a PDF');
        }
        ProofFile proof = new ProofFile();
        proof.pdfBase64 = payload.pdfBase64;
        proof.signedBy = payload.signedBy;
        return proof;
    }
}
