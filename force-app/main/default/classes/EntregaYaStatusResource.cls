/**
 * @description Inbound endpoint for EntregaYa shipment status updates
 *              (POST /services/apexrest/entregaya/v1/status, decision D2).
 *              STUB of req-004 T1: it exists so the RutaCargo_EntregaYa_Integration
 *              permission set can grant class access. It changes nothing and
 *              answers 501 NOT_IMPLEMENTED with a generic body; T3 replaces it
 *              with the caller check, the parsing and the HTTP error contract.
 */
@RestResource(urlMapping='/entregaya/v1/status/*')
global with sharing class EntregaYaStatusResource {

    @TestVisible
    private static final Integer NOT_IMPLEMENTED = 501;
    @TestVisible
    private static final String NOT_IMPLEMENTED_BODY =
        '{"error":{"code":"NOT_IMPLEMENTED","message":"This service is not available yet."}}';

    /**
     * @description Answers 501 with a generic JSON error body; reads nothing and
     *              writes nothing.
     */
    @HttpPost
    global static void post() {
        RestResponse response = RestContext.response;
        response.statusCode = NOT_IMPLEMENTED;
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(NOT_IMPLEMENTED_BODY);
    }
}
