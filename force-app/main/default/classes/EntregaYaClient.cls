/**
 * Callout to the last-mile carrier: GET /proofs/{proofId} (Named Credential EntregaYa).
 * The API key lives in the External Credential, never in code.
 */
public with sharing class EntregaYaClient {
    public class Proof {
        public String proofId;
        public String trackingNumber;
        public String signedBy;
        public String fileName;
        public String pdfBase64;
    }

    public class ProofException extends Exception {
    }

    @TestVisible
    private static final Integer TIMEOUT_MS = 10000;

    public static Proof getProof(String proofId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:EntregaYa/proofs/' + EncodingUtil.urlEncode(proofId, 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            // Timeout, DNS, missing credential access... never leak details to the site.
            System.debug(LoggingLevel.WARN, 'EntregaYa callout failed: ' + e.getMessage());
            throw new ProofException('EntregaYa unreachable: ' + e.getTypeName() + ': ' + e.getMessage());
        }
        if (res.getStatusCode() != 200) {
            System.debug(LoggingLevel.WARN, 'EntregaYa returned HTTP ' + res.getStatusCode());
            throw new ProofException('EntregaYa HTTP ' + res.getStatusCode());
        }
        try {
            Proof p = (Proof) JSON.deserialize(res.getBody(), Proof.class);
            if (p == null || String.isBlank(p.pdfBase64)) {
                throw new ProofException('Empty proof');
            }
            return p;
        } catch (JSONException e) {
            throw new ProofException('Invalid EntregaYa response');
        }
    }
}
