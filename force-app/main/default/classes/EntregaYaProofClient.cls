/**
 * GET {base URL}/proofs/{proofId} on EntregaYa. Base URL and API key live in the EntregaYa
 * Named Credential / External Credential (the key is sent as "Authorization: Bearer <key>"),
 * never in code. Timeout is the 10 seconds recommended by the provider.
 */
public inherited sharing class EntregaYaProofClient {
  public static final String NAMED_CREDENTIAL = 'callout:EntregaYa';
  public static final Integer TIMEOUT_MS = 10000;

  public class EntregaYaException extends Exception {
  }

  public class ProofOfDelivery {
    public String proofId;
    public String trackingNumber;
    public String signedBy;
    public String fileName;
    public String pdfBase64;
  }

  public static ProofOfDelivery getProof(String proofId) {
    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      NAMED_CREDENTIAL + '/proofs/' + EncodingUtil.urlEncode(proofId, 'UTF-8')
    );
    request.setMethod('GET');
    request.setHeader('Accept', 'application/json');
    request.setTimeout(TIMEOUT_MS);
    HttpResponse response;
    try {
      response = new Http().send(request);
    } catch (Exception e) {
      throw new EntregaYaException(
        'EntregaYa did not respond: ' + e.getMessage()
      );
    }
    Integer status = response.getStatusCode();
    if (status != 200) {
      // 401 wrong key, 404 unknown proof, 5xx unavailable
      throw new EntregaYaException(
        'EntregaYa returned HTTP ' + status + ' for proof ' + proofId
      );
    }
    ProofOfDelivery proof;
    try {
      proof = (ProofOfDelivery) JSON.deserialize(
        response.getBody(),
        ProofOfDelivery.class
      );
    } catch (JSONException e) {
      throw new EntregaYaException(
        'Invalid JSON from EntregaYa: ' + e.getMessage()
      );
    }
    if (proof == null || String.isBlank(proof.pdfBase64)) {
      throw new EntregaYaException('EntregaYa returned a proof without PDF');
    }
    return proof;
  }
}
