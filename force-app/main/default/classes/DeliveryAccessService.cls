/**
 * Verifies that a site visitor is the recipient of a shipment: tracking number
 * plus destination postal code (AC-002.1, BR-02). Every recipient operation
 * (details, proof of delivery, reschedule) calls verify() again on the server.
 *
 * Throttle (feature document L9): 5 wrong postal codes lock the shipment's
 * delivery details for 15 minutes, to limit guessing of the 5-digit code.
 *
 * WITHOUT SHARING and SYSTEM MODE on purpose: the caller is the site guest
 * user, who has no object permissions. Only the fields the recipient flows
 * need are selected, and only the throttle fields are written here.
 */
public without sharing class DeliveryAccessService {
    public static final String NOT_MATCHING = 'The details do not match this shipment';
    public static final String LOCKED = 'Too many attempts. Please try again in 15 minutes.';
    public static final Integer MAX_FAILED_ATTEMPTS = 5;
    public static final Integer LOCK_MINUTES = 15;
    private static final Pattern TRACKING_PATTERN = Pattern.compile('^RC[0-9]{9}$');
    private static final Pattern POSTAL_PATTERN = Pattern.compile('^[0-9]{5}$');

    @TestVisible
    private static Datetime nowOverride;

    /** Outcome of a verification. The shipment is set only when access is granted. */
    public class AccessResult {
        public Boolean granted = false;
        public String message;
        public Shipment__c shipment;
    }

    /**
     * Verifies the recipient and locks the shipment row for the rest of the
     * transaction, so a following write (reschedule) cannot race another one.
     * Never throws for a wrong code: the failed-attempt counter must be saved.
     * @param trackingNumber tracking number typed by the visitor
     * @param postalCode destination postal code typed by the visitor
     * @return granted with the shipment, or denied with a user-facing message
     */
    public static AccessResult verify(String trackingNumber, String postalCode) {
        AccessResult result = new AccessResult();
        result.message = NOT_MATCHING;
        String tracking = (trackingNumber ?? '').trim().toUpperCase();
        if (!TRACKING_PATTERN.matcher(tracking).matches()) {
            return result;
        }
        List<Shipment__c> rows = [
            SELECT Id, Name, Status__c, Recipient_Name__c, Recipient_Address__c, Recipient_Phone__c,
                Destination_Postal_Code__c, Delivery_Instructions__c, Estimated_Delivery__c,
                Original_Estimated_Delivery__c, Reschedule_Count__c, Proof_Id__c,
                Failed_Verification_Attempts__c, Verification_Locked_Until__c
            FROM Shipment__c
            WHERE Name = :tracking
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (rows.isEmpty()) {
            return result;
        }
        Shipment__c shipment = rows[0];
        Datetime now = nowOverride ?? Datetime.now();
        if (shipment.Verification_Locked_Until__c != null && shipment.Verification_Locked_Until__c > now) {
            result.message = LOCKED;
            return result;
        }
        if (!postalCodeMatches(shipment.Destination_Postal_Code__c, postalCode)) {
            recordFailedAttempt(shipment, now);
            return result;
        }
        clearFailedAttempts(shipment);
        result.granted = true;
        result.message = null;
        result.shipment = shipment;
        return result;
    }

    private static Boolean postalCodeMatches(String expected, String typed) {
        String normalized = (typed ?? '').deleteWhitespace();
        return POSTAL_PATTERN.matcher(normalized).matches() && normalized == expected;
    }

    private static void recordFailedAttempt(Shipment__c shipment, Datetime now) {
        Integer failures = (shipment.Failed_Verification_Attempts__c ?? 0).intValue() + 1;
        Shipment__c change = new Shipment__c(Id = shipment.Id);
        if (failures >= MAX_FAILED_ATTEMPTS) {
            change.Failed_Verification_Attempts__c = 0;
            change.Verification_Locked_Until__c = now.addMinutes(LOCK_MINUTES);
        } else {
            change.Failed_Verification_Attempts__c = failures;
        }
        Database.update(change, AccessLevel.SYSTEM_MODE);
    }

    private static void clearFailedAttempts(Shipment__c shipment) {
        if ((shipment.Failed_Verification_Attempts__c ?? 0) == 0 && shipment.Verification_Locked_Until__c == null) {
            return;
        }
        Database.update(
            new Shipment__c(Id = shipment.Id, Failed_Verification_Attempts__c = 0, Verification_Locked_Until__c = null),
            AccessLevel.SYSTEM_MODE
        );
    }
}
