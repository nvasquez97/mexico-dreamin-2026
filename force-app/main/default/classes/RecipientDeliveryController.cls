/**
 * @description Guest-callable entry point for recipients on the RutaCargo site
 *              (req-002-003 S2; BR-02, BR-03, BR-06; policy P1, P3, P10, P11, X5,
 *              X16). Every method takes the tracking number, the destination
 *              postal code and the delivery access code as individual Strings
 *              and re-verifies them through RecipientAccess on every call
 *              (stateless, E3); no method accepts a record Id or a record.
 *              Verification failures, the lock and reschedule rejections are
 *              RETURNED in a DeliveryResponse with a message from a closed list;
 *              only an unexpected error is thrown, as a generic
 *              AuraHandledException. Not cacheable: every call is verified and
 *              may write the attempt counter.
 *              The downloadProof method (T2) reuses RecipientAccess
 *              .verifyBeforeCallout and .resetAttempts.
 */
public with sharing class RecipientDeliveryController {

    public static final String OUTCOME_SUCCESS = 'SUCCESS';
    public static final String OUTCOME_NOT_MATCHED = 'NOT_MATCHED';
    public static final String OUTCOME_LOCKED = 'LOCKED';
    public static final String OUTCOME_REJECTED = 'REJECTED';

    public static final String WINDOW_MESSAGE = 'The new delivery date is outside the allowed rescheduling window.';
    public static final String STATUS_MESSAGE = 'This delivery cannot be rescheduled in its current status.';
    public static final String LIMIT_MESSAGE = 'This delivery has already been rescheduled the maximum number of times.';
    public static final String NO_ESTIMATE_MESSAGE = 'This delivery has no estimated date to reschedule from yet.';
    public static final String INSTRUCTIONS_MESSAGE = 'Delivery instructions must be 1000 characters or fewer.';
    public static final String GENERIC_ERROR_MESSAGE = 'We could not complete your request. Please try again later.';

    private static final Set<String> RESCHEDULABLE_STATUSES = new Set<String>{ 'Picked up', 'In transit' };
    private static final String DELIVERED = 'Delivered';
    private static final Integer MAX_RESCHEDULES = 2;
    private static final Integer DAYS_AFTER_ORIGINAL = 7;
    private static final Integer MAX_INSTRUCTIONS_LENGTH = 1000;
    private static final String MEXICO_CITY = 'America/Mexico_City';
    private static final Pattern ISO_DATE = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');

    // Test seam for "today" in America/Mexico_City (AC-003.2).
    @TestVisible
    private static Date todayOverride;

    // Test seam that raises an unexpected error inside the guarded block.
    @TestVisible
    private static Boolean simulateUnexpectedFailure = false;

    /**
     * @description The answer to a recipient: an outcome (SUCCESS, NOT_MATCHED,
     *              LOCKED, REJECTED), a message from a closed list (null on
     *              success) and the details (only after a successful
     *              verification).
     */
    public with sharing class DeliveryResponse {
        @AuraEnabled public String outcome;
        @AuraEnabled public String message;
        @AuraEnabled public RecipientDeliveryDetails details;
    }

    /**
     * @description Returns the delivery details of a verified recipient.
     * @param trackingNumber the tracking number
     * @param postalCode the destination postal code
     * @param accessCode the delivery access code
     * @return the response; failures are returned, not thrown
     * @throws AuraHandledException with a generic message on an unexpected error
     */
    @AuraEnabled
    public static DeliveryResponse getDeliveryDetails(String trackingNumber, String postalCode, String accessCode) {
        try {
            failIfSimulated();
            RecipientAccess.Verification verification = RecipientAccess.verify(trackingNumber, postalCode, accessCode);
            if (!verification.isVerified()) {
                return failure(verification);
            }
            return response(OUTCOME_SUCCESS, null, verification.shipment);
        } catch (Exception unexpected) {
            throw genericError();
        }
    }

    /**
     * @description Reschedules the delivery of a verified recipient: a new date
     *              between tomorrow (America/Mexico_City) and the original
     *              estimate + 7 days, new instructions (blank clears them), in
     *              Picked up or In transit, at most 2 times.
     * @param trackingNumber the tracking number
     * @param postalCode the destination postal code
     * @param accessCode the delivery access code
     * @param newDate the new date, ISO yyyy-MM-dd
     * @param instructions the new delivery instructions, at most 1000 characters
     * @return the response with the refreshed details; rejections are returned
     * @throws AuraHandledException with a generic message on an unexpected error
     */
    @AuraEnabled
    public static DeliveryResponse rescheduleDelivery(
        String trackingNumber, String postalCode, String accessCode, String newDate, String instructions
    ) {
        try {
            failIfSimulated();
            RecipientAccess.Verification verification = RecipientAccess.verify(trackingNumber, postalCode, accessCode);
            if (!verification.isVerified()) {
                return failure(verification);
            }
            Date requested = parseIsoDate(newDate);
            String text = String.isBlank(instructions) ? null : instructions;
            String rejection = rejectionOf(verification.shipment, requested, text);
            if (rejection != null) {
                return response(OUTCOME_REJECTED, rejection, verification.shipment);
            }
            // The rules are checked again on the locked row, which a concurrent
            // reschedule may have changed.
            Shipment__c locked = RecipientAccess.lockForReschedule(verification);
            rejection = rejectionOf(locked, requested, text);
            if (rejection != null) {
                return response(OUTCOME_REJECTED, rejection, locked);
            }
            Shipment__c saved = RecipientAccess.saveReschedule(verification, requested, text);
            return response(OUTCOME_SUCCESS, null, saved);
        } catch (Exception unexpected) {
            throw genericError();
        }
    }

    // ─── Rules ───────────────────────────────────────────────────────────

    // The first rule the reschedule breaks, or null when it is allowed.
    private static String rejectionOf(Shipment__c shipment, Date requested, String instructions) {
        if (!RESCHEDULABLE_STATUSES.contains(shipment.Status__c)) {
            return STATUS_MESSAGE;
        }
        if (reschedulesUsed(shipment) >= MAX_RESCHEDULES) {
            return LIMIT_MESSAGE;
        }
        if (shipment.Original_Estimated_Delivery__c == null) {
            return NO_ESTIMATE_MESSAGE;
        }
        if (instructions != null && instructions.length() > MAX_INSTRUCTIONS_LENGTH) {
            return INSTRUCTIONS_MESSAGE;
        }
        if (requested == null || requested < windowStart() || requested > windowEnd(shipment)) {
            return WINDOW_MESSAGE;
        }
        return null;
    }

    private static Integer reschedulesUsed(Shipment__c shipment) {
        return (shipment.Reschedule_Count__c ?? 0).intValue();
    }

    private static Date windowStart() {
        return today().addDays(1);
    }

    // D4: measured from the original estimate, never from the current one.
    private static Date windowEnd(Shipment__c shipment) {
        return shipment.Original_Estimated_Delivery__c?.addDays(DAYS_AFTER_ORIGINAL);
    }

    private static Boolean canReschedule(Shipment__c shipment) {
        return RESCHEDULABLE_STATUSES.contains(shipment.Status__c)
            && reschedulesUsed(shipment) < MAX_RESCHEDULES
            && shipment.Original_Estimated_Delivery__c != null
            && windowStart() <= windowEnd(shipment);
    }

    // BR-06: today in America/Mexico_City, whatever the server or user time zone.
    private static Date today() {
        if (todayOverride != null) {
            return todayOverride;
        }
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', MEXICO_CITY));
    }

    // A strict ISO date (yyyy-MM-dd that round-trips), or null.
    private static Date parseIsoDate(String value) {
        if (String.isBlank(value) || !ISO_DATE.matcher(value).matches()) {
            return null;
        }
        try {
            Date parsed = Date.valueOf(value);
            return String.valueOf(parsed) == value ? parsed : null;
        } catch (TypeException invalid) {
            return null;
        }
    }

    // ─── Responses ───────────────────────────────────────────────────────

    private static DeliveryResponse failure(RecipientAccess.Verification verification) {
        DeliveryResponse result = new DeliveryResponse();
        result.outcome = verification.outcome == RecipientAccess.Outcome.LOCKED ? OUTCOME_LOCKED : OUTCOME_NOT_MATCHED;
        result.message = verification.message;
        return result;
    }

    private static DeliveryResponse response(String outcome, String message, Shipment__c shipment) {
        DeliveryResponse result = new DeliveryResponse();
        result.outcome = outcome;
        result.message = message;
        result.details = detailsOf(shipment);
        return result;
    }

    private static RecipientDeliveryDetails detailsOf(Shipment__c shipment) {
        RecipientDeliveryDetails details = new RecipientDeliveryDetails();
        details.recipientName = shipment.Recipient_Name__c;
        details.deliveryAddress = addressOf(shipment);
        details.contactPhone = shipment.Recipient_Phone__c;
        details.estimatedDelivery = isoOf(shipment.Estimated_Delivery__c);
        details.deliveryInstructions = shipment.Delivery_Instructions__c;
        details.status = shipment.Status__c;
        details.canReschedule = canReschedule(shipment);
        details.reschedulesLeft = Math.max(0, MAX_RESCHEDULES - reschedulesUsed(shipment));
        details.rescheduleFrom = details.canReschedule ? isoOf(windowStart()) : null;
        details.rescheduleTo = details.canReschedule ? isoOf(windowEnd(shipment)) : null;
        details.proofAvailable = shipment.Status__c == DELIVERED && String.isNotBlank(shipment.Proof_Id__c);
        return details;
    }

    // "<street>, <postal code> <city>", skipping blank parts.
    private static String addressOf(Shipment__c shipment) {
        String locality = String.join(new List<String>{
            shipment.Destination_Postal_Code__c ?? '', shipment.Destination_City__c ?? ''
        }, ' ').trim();
        List<String> parts = new List<String>();
        for (String part : new List<String>{ shipment.Recipient_Address__c, locality }) {
            if (String.isNotBlank(part)) {
                parts.add(part.trim());
            }
        }
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String isoOf(Date value) {
        return value == null ? null : String.valueOf(value);
    }

    private static void failIfSimulated() {
        if (simulateUnexpectedFailure) {
            throw new RecipientAccess.RecipientAccessException('Simulated unexpected failure.');
        }
    }

    private static AuraHandledException genericError() {
        AuraHandledException error = new AuraHandledException(GENERIC_ERROR_MESSAGE);
        error.setMessage(GENERIC_ERROR_MESSAGE);
        return error;
    }
}
