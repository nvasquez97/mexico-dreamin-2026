/**
 * Callout to EntregaYa for the proof of delivery (AC-002.4, AC-002.5).
 * Uses the legacy Named Credential EntregaYa (the guest user cannot hold External Credential principal access);
 * the API key lives only in its password field (never in code or metadata). Timeout is 10 seconds as the provider recommends.
 */
public with sharing class EntregaYaClient {
    public static final Integer TIMEOUT_MS = 10000;

    public class EntregaYaException extends Exception {
    }

    /** Parsed proof. */
    public class Proof {
        public String proofId;
        public String trackingNumber;
        public String signedBy;
        public String fileName;
        public String pdfBase64;
    }

    /**
     * @param proofId proof identifier stored on the shipment
     * @return the proof, held in memory only
     * @throws EntregaYaException on any non-200 response, timeout or malformed body
     */
    public static Proof fetchProof(String proofId) {
        if (String.isBlank(proofId) || !Pattern.matches('[A-Za-z0-9_-]{1,60}', proofId)) {
            throw new EntregaYaException('Invalid proof identifier.');
        }
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:EntregaYa/proofs/' + EncodingUtil.urlEncode(proofId, 'UTF-8'));
        request.setMethod('GET');
        // The API key is the Named Credential's password (entered in Setup, never in the repo); Salesforce merges it here.
        request.setHeader('Authorization', 'Bearer {!$Credential.Password}');
        request.setTimeout(TIMEOUT_MS);
        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (CalloutException e) {
            throw new EntregaYaException('EntregaYa did not respond.', e);
        }
        if (response.getStatusCode() != 200) {
            throw new EntregaYaException('EntregaYa returned status ' + response.getStatusCode() + '.');
        }
        try {
            Proof proof = (Proof) JSON.deserialize(response.getBody(), Proof.class);
            if (proof == null || String.isBlank(proof.pdfBase64)) {
                throw new EntregaYaException('EntregaYa returned an empty proof.');
            }
            return proof;
        } catch (JSONException e) {
            throw new EntregaYaException('EntregaYa returned an unreadable proof.', e);
        }
    }
}
