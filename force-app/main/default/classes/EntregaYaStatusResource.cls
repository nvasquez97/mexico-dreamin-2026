/**
 * @description Inbound endpoint for EntregaYa shipment status updates
 *              (POST /services/apexrest/entregaya/v1/status, decision D2, req-004 S2).
 *              A thin controller:
 *              1. the caller must hold the custom permission
 *                 RutaCargo_EntregaYa_Sender (BR-04), otherwise 403 FORBIDDEN and
 *                 nothing is parsed or changed;
 *              2. the body must be a JSON object whose five known keys
 *                 (trackingNumber, status, location, timestamp, proofId) hold
 *                 strings or null, otherwise 400 INVALID_JSON; other keys are
 *                 ignored and nothing is ever mapped into an SObject (X6);
 *              3. EntregaYaStatusService.apply validates and saves in user mode,
 *                 and its outcome becomes the HTTP answer: 200 updated / 200
 *                 ignored / 404 / 400 / 503 (retry) / 500.
 *              Every answer is application/json; an error body is
 *              {"error":{"code":"…","message":"…"}} with a closed code and a fixed
 *              message, never exception text, a type name or a field API name
 *              (X7). Any exception escaping the parsing or the mapping answers 500
 *              INTERNAL_ERROR.
 *              Limits: 1 SOQL and 1 DML per call (those of the service).
 */
@RestResource(urlMapping='/entregaya/v1/status/*')
global with sharing class EntregaYaStatusResource {

    private static final String SENDER_PERMISSION = 'RutaCargo_EntregaYa_Sender';
    private static final String CONTENT_TYPE = 'application/json';
    private static final Integer HTTP_FORBIDDEN = 403;
    private static final String FORBIDDEN_CODE = 'FORBIDDEN';
    private static final String FORBIDDEN_MESSAGE = 'This user may not send EntregaYa status updates.';

    private static final String TRACKING_NUMBER = 'trackingNumber';
    private static final String STATUS = 'status';
    private static final String LOCATION = 'location';
    private static final String TIMESTAMP = 'timestamp';
    private static final String PROOF_ID = 'proofId';
    private static final List<String> KNOWN_KEYS = new List<String>{ TRACKING_NUMBER, STATUS, LOCATION, TIMESTAMP, PROOF_ID };

    private static final Map<EntregaYaStatusService.Outcome, Integer> HTTP_STATUS =
        new Map<EntregaYaStatusService.Outcome, Integer>{
            EntregaYaStatusService.Outcome.UPDATED => 200,
            EntregaYaStatusService.Outcome.IGNORED => 200,
            EntregaYaStatusService.Outcome.NOT_FOUND => 404,
            EntregaYaStatusService.Outcome.INVALID => 400,
            EntregaYaStatusService.Outcome.RETRYABLE => 503,
            EntregaYaStatusService.Outcome.INTERNAL => 500
        };

    private static final Map<EntregaYaStatusService.Outcome, String> RESULTS =
        new Map<EntregaYaStatusService.Outcome, String>{
            EntregaYaStatusService.Outcome.UPDATED => 'updated',
            EntregaYaStatusService.Outcome.IGNORED => 'ignored'
        };

    /** @description An HTTP answer: status code and JSON body. */
    private class Reply {
        private final Integer statusCode;
        private final String body;

        private Reply(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
    }

    /**
     * @description Applies one EntregaYa status change and answers with the HTTP
     *              contract of D2. Never lets an exception reach the caller.
     * @example
     * POST /services/apexrest/entregaya/v1/status
     * {"trackingNumber":"RC000000001","status":"Out for delivery","location":"Monterrey, NL",
     *  "timestamp":"2026-11-20T10:00:00-06:00","proofId":null}
     */
    @HttpPost
    global static void post() {
        Reply reply;
        try {
            reply = handle(RestContext.request);
        } catch (Exception unexpected) {
            // X7: the caller gets the closed code and the fixed message only; the
            // exception is not rethrown, so no type name or stack trace leaks.
            reply = replyFor(EntregaYaStatusService.failure(EntregaYaStatusService.ErrorCode.INTERNAL_ERROR));
        }
        RestResponse response = RestContext.response;
        response.statusCode = reply.statusCode;
        response.addHeader('Content-Type', CONTENT_TYPE);
        response.responseBody = Blob.valueOf(reply.body);
    }

    private static Reply handle(RestRequest request) {
        if (!FeatureManagement.checkPermission(SENDER_PERMISSION)) {
            return new Reply(HTTP_FORBIDDEN, errorBody(FORBIDDEN_CODE, FORBIDDEN_MESSAGE));
        }
        EntregaYaStatusRequest statusRequest = parse(request.requestBody);
        return replyFor(statusRequest == null
            ? EntregaYaStatusService.failure(EntregaYaStatusService.ErrorCode.INVALID_JSON)
            : EntregaYaStatusService.apply(statusRequest));
    }

    private static Reply replyFor(EntregaYaStatusService.Result result) {
        Integer statusCode = HTTP_STATUS.get(result.outcome);
        if (RESULTS.containsKey(result.outcome)) {
            return new Reply(statusCode, JSON.serialize(new Map<String, Object>{ 'result' => RESULTS.get(result.outcome) }));
        }
        return new Reply(statusCode, errorBody(result.errorCode.name(), result.message));
    }

    private static String errorBody(String code, String message) {
        return JSON.serialize(new Map<String, Object>{
            'error' => new Map<String, Object>{ 'code' => code, 'message' => message }
        });
    }

    // The request of a JSON object whose known keys hold strings or null; null when
    // the body is not one (invalid JSON, not an object, or a known key of another type).
    private static EntregaYaStatusRequest parse(Blob body) {
        Map<String, Object> fields = parseObject(body);
        if (fields == null) {
            return null;
        }
        for (String key : KNOWN_KEYS) {
            Object value = fields.get(key);
            if (value != null && !(value instanceof String)) {
                return null;
            }
        }
        EntregaYaStatusRequest request = new EntregaYaStatusRequest();
        request.trackingNumber = (String) fields.get(TRACKING_NUMBER);
        request.status = (String) fields.get(STATUS);
        request.location = (String) fields.get(LOCATION);
        request.timestamp = (String) fields.get(TIMESTAMP);
        request.proofId = (String) fields.get(PROOF_ID);
        return request;
    }

    private static Map<String, Object> parseObject(Blob body) {
        if (body == null) {
            return null;
        }
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(body.toString());
        } catch (JSONException malformed) {
            return null;
        } catch (StringException notText) {
            return null;
        }
        return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
    }
}
