/**
 * Inbound status changes from the last-mile carrier EntregaYa (REQ-004).
 * POST /services/apexrest/entregaya/v1/shipment-status, one call per change:
 *   {"trackingNumber": "RC000001042", "status": "Out for delivery",
 *    "location": "Monterrey, NL", "timestamp": "2026-11-20T10:00:00-06:00", "proofId": null}
 *
 * Authentication: OAuth 2.0 client credentials through the EntregaYa external
 * client app, which runs as the EntregaYa integration user. Only the
 * EntregaYa_Integration permission set grants access to this class (BR-04).
 * WITHOUT SHARING and SYSTEM MODE on purpose (security review L-3): the
 * integration user has NO object permissions, so it cannot edit shipments
 * through the standard API and skip this endpoint's rules (carrier statuses
 * only, older updates ignored, proof id on Delivered). This endpoint is the
 * only write path, and it writes exactly the five carrier fields below.
 *
 * Responses: 200 {"result":"updated"} or {"result":"ignored"} (older update,
 * AC-004.4); 400/404 {"result":"rejected","code":...,"message":...} (AC-004.3).
 */
@RestResource(urlMapping='/entregaya/v1/shipment-status')
global without sharing class EntregaYaStatusResource {
    /** Statuses the carrier may send. Requested is set only at creation (BR-09). */
    @TestVisible
    private static final List<String> CARRIER_STATUSES = new List<String>{
        'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'
    };
    private static final Pattern TRACKING_PATTERN = Pattern.compile('^RC[0-9]{9}$');
    private static final Pattern TIMESTAMP_PATTERN = Pattern.compile(
        '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,3})?(Z|[+-][0-9]{2}:[0-9]{2})$'
    );
    private static final Integer MAX_LOCATION_LENGTH = 255;
    private static final Integer MAX_PROOF_ID_LENGTH = 50;

    /** Request body sent by EntregaYa. */
    private class StatusChange {
        String trackingNumber;
        String status;
        String location;
        String timestamp;
        String proofId;
    }

    /** Thrown for any rejected request; carries the HTTP status and a stable code. */
    private class RejectedException extends Exception {
        Integer httpStatus;
        String code;

        RejectedException(Integer httpStatus, String code, String message) {
            this(message);
            this.httpStatus = httpStatus;
            this.code = code;
        }
    }

    /** Receives one status change and applies it to the shipment. */
    @HttpPost
    global static void receiveStatus() {
        try {
            StatusChange change = parse(RestContext.request.requestBody);
            Datetime eventTime = validate(change);
            Boolean applied = apply(change, eventTime);
            respond(200, new Map<String, Object>{
                'result' => applied ? 'updated' : 'ignored',
                'message' => applied
                    ? 'Shipment ' + change.trackingNumber + ' updated to ' + change.status + '.'
                    : 'Ignored: an update with the same or a later timestamp is already recorded for ' + change.trackingNumber + '.'
            });
        } catch (RejectedException e) {
            respond(e.httpStatus, new Map<String, Object>{ 'result' => 'rejected', 'code' => e.code, 'message' => e.getMessage() });
        } catch (Exception e) {
            // No internal details for the partner (security review L-2). The only DML is the last statement of apply(), so nothing was saved.
            respond(500, new Map<String, Object>{
                'result' => 'error', 'code' => 'INTERNAL_ERROR',
                'message' => 'The update could not be saved. Retry later; contact RutaCargo if it persists.'
            });
        }
    }

    private static StatusChange parse(Blob body) {
        try {
            StatusChange change = (StatusChange) JSON.deserialize(body?.toString() ?? '', StatusChange.class);
            if (change == null) {
                throw new RejectedException(400, 'INVALID_BODY', 'The body must be a JSON object.');
            }
            return change;
        } catch (JSONException e) {
            throw new RejectedException(400, 'INVALID_BODY', 'The body must be a JSON object with trackingNumber, status, location and timestamp.');
        }
    }

    private static Datetime validate(StatusChange change) {
        if (String.isBlank(change.trackingNumber) || String.isBlank(change.status) ||
            String.isBlank(change.location) || String.isBlank(change.timestamp)) {
            throw new RejectedException(400, 'MISSING_FIELD', 'trackingNumber, status, location and timestamp are required.');
        }
        if (!TRACKING_PATTERN.matcher(change.trackingNumber).matches()) {
            throw new RejectedException(404, 'UNKNOWN_TRACKING_NUMBER', 'Tracking number ' + change.trackingNumber.left(20) + ' does not exist.');
        }
        if (!CARRIER_STATUSES.contains(change.status)) {
            throw new RejectedException(400, 'INVALID_STATUS',
                'Invalid status. Valid values: ' + String.join(CARRIER_STATUSES, ', ') + '.');
        }
        if (change.location.length() > MAX_LOCATION_LENGTH) {
            throw new RejectedException(400, 'INVALID_LOCATION', 'location can have up to 255 characters.');
        }
        if (change.status == 'Delivered' &&
            (String.isBlank(change.proofId) || change.proofId.length() > MAX_PROOF_ID_LENGTH)) {
            throw new RejectedException(400, 'MISSING_PROOF_ID', 'proofId (up to 50 characters) is required when status is Delivered.');
        }
        return parseTimestamp(change.timestamp);
    }

    private static Datetime parseTimestamp(String value) {
        if (!TIMESTAMP_PATTERN.matcher(value).matches()) {
            throw new RejectedException(400, 'INVALID_TIMESTAMP', 'timestamp must be ISO 8601 with a time zone, for example 2026-11-20T10:00:00-06:00.');
        }
        try {
            return (Datetime) JSON.deserialize('"' + value + '"', Datetime.class);
        } catch (JSONException e) {
            throw new RejectedException(400, 'INVALID_TIMESTAMP', 'timestamp is not a valid date and time.');
        }
    }

    /** @return false when the change is older than (or as old as) the last one recorded (AC-004.4). */
    private static Boolean apply(StatusChange change, Datetime eventTime) {
        List<Shipment__c> rows = [
            SELECT Id, Last_Update__c
            FROM Shipment__c
            WHERE Name = :change.trackingNumber
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            throw new RejectedException(404, 'UNKNOWN_TRACKING_NUMBER', 'Tracking number ' + change.trackingNumber + ' does not exist.');
        }
        Shipment__c shipment = rows[0];
        if (shipment.Last_Update__c != null && eventTime <= shipment.Last_Update__c) {
            return false;
        }
        Shipment__c updated = new Shipment__c(
            Id = shipment.Id,
            Status__c = change.status,
            Last_Location__c = change.location,
            Last_Update__c = eventTime
        );
        if (change.status == 'Delivered') {
            updated.Delivered_At__c = eventTime;
            updated.Proof_Id__c = change.proofId;
        }
        Database.update(updated, AccessLevel.SYSTEM_MODE);
        return true;
    }

    private static void respond(Integer statusCode, Map<String, Object> payload) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(payload));
    }
}
