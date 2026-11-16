/**
 * Inbound service for EntregaYa status changes: POST /services/apexrest/entregaya/v1/status.
 * Authentication is OAuth 2.0 (client credentials via an External Client App). Authorization:
 * the caller must hold the EntregaYa_Status_Update custom permission (BR-04).
 *
 * SHARING JUSTIFICATION: system mode is isolated in ShipmentStatusService; this thin resource only
 * authenticates, parses and maps outcomes to HTTP status codes.
 */
@RestResource(urlMapping='/entregaya/v1/status')
global with sharing class EntregaYaStatusRestResource {
    /** Request body sent by EntregaYa. */
    global class StatusRequest {
        public String trackingNumber;
        public String status;
        public String location;
        public String timestamp;
        public String proofId;
    }

    /** Response body. */
    global class StatusResponse {
        public Boolean success;
        public String message;
    }

    /**
     * Applies one status change (AC-004.1 to AC-004.4).
     */
    @HttpPost
    global static void post() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');
        if (!FeatureManagement.checkPermission('EntregaYa_Status_Update')) {
            write(response, 403, false, 'This identity is not allowed to send status updates.');
            return;
        }
        StatusRequest body;
        try {
            body = (StatusRequest) JSON.deserialize(RestContext.request.requestBody.toString(), StatusRequest.class);
        } catch (Exception e) {
            write(response, 400, false, 'The body must be valid JSON with trackingNumber, status, location, timestamp and proofId.');
            return;
        }
        ShipmentStatusService.Result result = ShipmentStatusService.apply(
            body.trackingNumber, body.status, body.location, body.timestamp, body.proofId
        );
        switch on result.outcome {
            when APPLIED, IGNORED_OLDER {
                write(response, 200, true, result.message);
            }
            when NOT_FOUND {
                write(response, 404, false, result.message);
            }
            when else {
                write(response, 400, false, result.message);
            }
        }
    }

    private static void write(RestResponse response, Integer code, Boolean success, String message) {
        StatusResponse body = new StatusResponse();
        body.success = success;
        body.message = message;
        response.statusCode = code;
        response.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
