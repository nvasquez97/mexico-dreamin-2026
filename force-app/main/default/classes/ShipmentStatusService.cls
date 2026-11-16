/**
 * Applies a carrier status change to a shipment (REQ-004).
 *
 * SHARING JUSTIFICATION: system mode. The only caller is EntregaYaStatusRestResource, which has
 * already authenticated the integration user (OAuth) and checked the EntregaYa_Status_Update custom
 * permission (BR-04). This service touches only five fields: status, last location, last update,
 * delivered-at and proof id. The row is locked while it is compared and updated (concurrency).
 */
public without sharing class ShipmentStatusService {
    public static final Set<String> CARRIER_STATUSES = new Set<String>{
        'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'
    };

    public enum Outcome {
        APPLIED, IGNORED_OLDER, NOT_FOUND, INVALID
    }

    /** Result of one update. */
    public class Result {
        public Outcome outcome;
        public String message;
    }

    /**
     * @param trackingNumber tracking number
     * @param status new status (carrier statuses only; Requested is invalid, BR-09)
     * @param location last reported location
     * @param timestamp ISO 8601 date-time with offset
     * @param proofId proof identifier (used with Delivered)
     * @return what happened
     */
    public static Result apply(String trackingNumber, String status, String location, String timestamp, String proofId) {
        Datetime occurredAt = parseTimestamp(timestamp);
        if (String.isBlank(trackingNumber)) {
            return result(Outcome.INVALID, 'trackingNumber is required.');
        }
        if (String.isBlank(status) || !CARRIER_STATUSES.contains(status)) {
            return result(Outcome.INVALID, 'Invalid status. Allowed: ' + String.join(new List<String>(CARRIER_STATUSES), ', ') + '.');
        }
        if (occurredAt == null) {
            return result(Outcome.INVALID, 'timestamp is required in ISO 8601 format, for example 2026-11-20T10:00:00-06:00.');
        }
        if (!String.isBlank(location) && location.length() > 120) {
            return result(Outcome.INVALID, 'location is too long (120 characters maximum).');
        }
        if (!String.isBlank(proofId) && !Pattern.matches('[A-Za-z0-9_-]{1,60}', proofId)) {
            return result(Outcome.INVALID, 'proofId has an invalid format.');
        }
        Shipment__c shipment = ShipmentSelector.forStatusUpdate(trackingNumber.trim());
        if (shipment == null) {
            return result(Outcome.NOT_FOUND, 'No shipment with tracking number ' + trackingNumber.trim() + '.');
        }
        if (shipment.Last_Update__c != null && occurredAt < shipment.Last_Update__c) {
            return result(Outcome.IGNORED_OLDER, 'Update ignored: it is older than the last recorded update.');
        }
        shipment.Status__c = status;
        shipment.Last_Location__c = location;
        shipment.Last_Update__c = occurredAt;
        if (status == 'Delivered') {
            shipment.Delivered_At__c = occurredAt;
            if (!String.isBlank(proofId)) {
                shipment.Proof_Id__c = proofId;
            }
        }
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        return result(Outcome.APPLIED, 'Update applied.');
    }

    private static Result result(Outcome outcome, String message) {
        Result r = new Result();
        r.outcome = outcome;
        r.message = message;
        return r;
    }

    private static Datetime parseTimestamp(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + value.trim().replace('"', '') + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }
}
