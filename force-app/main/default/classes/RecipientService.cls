/**
 * Recipient flows without login (REQ-002, REQ-003): delivery details, proof of delivery, reschedule.
 * The recipient is whoever knows the tracking number and the destination postal code (AC-002.1).
 *
 * SHARING JUSTIFICATION: system mode through ShipmentSelector (guest has no object permissions).
 * Every public method re-verifies the postal code on the server, so nothing is trusted from an
 * earlier call. Brute force of the 5-digit code is limited: after MAX_FAILURES wrong codes the
 * shipment locks for LOCK_MINUTES. Failure paths return an outcome (never throw) so the counter
 * update is committed.
 */
public without sharing class RecipientService {
    public static final Integer MAX_FAILURES = 5;
    public static final Integer LOCK_MINUTES = 15;
    public static final Integer MAX_RESCHEDULES = 2;
    public static final String MSG_MISMATCH = 'The details do not match this shipment';
    public static final String MSG_LOCKED = 'Too many attempts. Please try again in a few minutes.';
    public static final String MSG_PROOF_UNAVAILABLE = 'We could not get the proof of delivery, please try again later';

    /**
     * AC-002.1 to AC-002.3.
     * @param trackingNumber tracking number
     * @param postalCode destination postal code
     * @return details when verified; otherwise an outcome and message
     */
    public static RutaCargoDtos.DeliveryDetails getDetails(String trackingNumber, String postalCode) {
        Shipment__c shipment = verify(clean(trackingNumber), postalCode);
        if (!wasVerified) {
            return failure(lastOutcome, lastOutcome == RutaCargoDtos.LOCKED ? MSG_LOCKED : MSG_MISMATCH);
        }
        return toDetails(shipment);
    }

    /**
     * AC-003.1 to AC-003.5.
     * @param trackingNumber tracking number
     * @param postalCode destination postal code
     * @param newDate new estimated delivery date
     * @param instructions new delivery instructions
     * @return fresh details with outcome OK, or REJECTED with the reason
     */
    public static RutaCargoDtos.DeliveryDetails reschedule(String trackingNumber, String postalCode, Date newDate, String instructions) {
        Shipment__c shipment = verify(clean(trackingNumber), postalCode);
        if (!wasVerified) {
            return failure(lastOutcome, lastOutcome == RutaCargoDtos.LOCKED ? MSG_LOCKED : MSG_MISMATCH);
        }
        String reason = rescheduleBlocker(shipment, newDate, instructions);
        if (reason != null) {
            RutaCargoDtos.DeliveryDetails rejected = toDetails(shipment);
            rejected.outcome = RutaCargoDtos.REJECTED;
            rejected.message = reason;
            return rejected;
        }
        Delivery_Change__c change = new Delivery_Change__c(
            Shipment__c = shipment.Id,
            Previous_Date__c = shipment.Estimated_Delivery__c,
            New_Date__c = newDate,
            Previous_Instructions__c = shipment.Delivery_Instructions__c,
            New_Instructions__c = instructions
        );
        shipment.Estimated_Delivery__c = newDate;
        shipment.Delivery_Instructions__c = instructions;
        shipment.Reschedule_Count__c = (shipment.Reschedule_Count__c ?? 0) + 1;
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        Database.insert(change, AccessLevel.SYSTEM_MODE);
        return toDetails(shipment);
    }

    /**
     * AC-002.4, AC-002.5. The PDF is returned to the caller and never stored.
     * @param trackingNumber tracking number
     * @param postalCode destination postal code
     * @return the PDF as base64, or an outcome and message
     */
    public static RutaCargoDtos.ProofResult getProof(String trackingNumber, String postalCode) {
        Shipment__c shipment = verify(clean(trackingNumber), postalCode);
        RutaCargoDtos.ProofResult result = new RutaCargoDtos.ProofResult();
        if (!wasVerified) {
            result.outcome = lastOutcome;
            result.message = lastOutcome == RutaCargoDtos.LOCKED ? MSG_LOCKED : MSG_MISMATCH;
            return result;
        }
        if (shipment.Status__c != 'Delivered' || String.isBlank(shipment.Proof_Id__c)) {
            result.outcome = RutaCargoDtos.REJECTED;
            result.message = 'The proof of delivery is available once the shipment is delivered.';
            return result;
        }
        try {
            EntregaYaClient.Proof proof = EntregaYaClient.fetchProof(shipment.Proof_Id__c);
            result.outcome = RutaCargoDtos.OK;
            result.fileName = String.isBlank(proof.fileName) ? 'proof-of-delivery.pdf' : proof.fileName;
            result.pdfBase64 = proof.pdfBase64;
        } catch (EntregaYaClient.EntregaYaException e) {
            result.outcome = RutaCargoDtos.UNAVAILABLE;
            result.message = MSG_PROOF_UNAVAILABLE;
        }
        return result;
    }

    // ---- internals -------------------------------------------------------------------------

    // Transaction-scoped result of the last verify() call (one request handles one call).
    private static Boolean wasVerified = false;
    private static String lastOutcome = RutaCargoDtos.MISMATCH;

    private static String clean(String value) {
        return value == null ? null : value.trim();
    }

    private static Shipment__c verify(String trackingNumber, String postalCode) {
        wasVerified = false;
        lastOutcome = RutaCargoDtos.MISMATCH;
        if (String.isBlank(trackingNumber) || trackingNumber.length() > 20 || !ShipmentRules.isValidPostalCode(clean(postalCode))) {
            return null;
        }
        Shipment__c shipment = ShipmentSelector.forRecipientUpdate(trackingNumber);
        if (shipment == null) {
            return null;
        }
        Datetime now = Datetime.now();
        if (shipment.Locked_Until__c != null && shipment.Locked_Until__c > now) {
            lastOutcome = RutaCargoDtos.LOCKED;
            return shipment;
        }
        if (shipment.Destination_Postal_Code__c == clean(postalCode)) {
            wasVerified = true;
            lastOutcome = RutaCargoDtos.OK;
            if ((shipment.Failed_Verifications__c ?? 0) > 0 || shipment.Locked_Until__c != null) {
                shipment.Failed_Verifications__c = 0;
                shipment.Locked_Until__c = null;
                Database.update(shipment, AccessLevel.SYSTEM_MODE);
            }
            return shipment;
        }
        Decimal failures = (shipment.Failed_Verifications__c ?? 0) + 1;
        if (failures >= MAX_FAILURES) {
            shipment.Failed_Verifications__c = 0;
            shipment.Locked_Until__c = now.addMinutes(LOCK_MINUTES);
        } else {
            shipment.Failed_Verifications__c = failures;
        }
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        return shipment;
    }

    private static String rescheduleBlocker(Shipment__c shipment, Date newDate, String instructions) {
        if (shipment.Status__c != 'Picked up' && shipment.Status__c != 'In transit') {
            return 'Only shipments that were picked up or are in transit can be rescheduled.';
        }
        if ((shipment.Reschedule_Count__c ?? 0) >= MAX_RESCHEDULES) {
            return 'This delivery was already rescheduled ' + MAX_RESCHEDULES + ' times.';
        }
        if (!ShipmentRules.isValidRescheduleDate(newDate, shipment.Original_Estimated_Delivery__c ?? shipment.Estimated_Delivery__c)) {
            return 'Choose a date from tomorrow up to ' + ShipmentRules.MAX_RESCHEDULE_DAYS_AFTER_ORIGINAL + ' days after the original estimated date.';
        }
        if (instructions != null && instructions.length() > 1000) {
            return 'Delivery instructions can have up to 1000 characters.';
        }
        return null;
    }

    private static RutaCargoDtos.DeliveryDetails failure(String outcome, String message) {
        RutaCargoDtos.DeliveryDetails details = new RutaCargoDtos.DeliveryDetails();
        details.outcome = outcome;
        details.message = message;
        return details;
    }

    private static RutaCargoDtos.DeliveryDetails toDetails(Shipment__c shipment) {
        RutaCargoDtos.DeliveryDetails details = new RutaCargoDtos.DeliveryDetails();
        details.outcome = RutaCargoDtos.OK;
        details.trackingNumber = shipment.Name;
        details.status = shipment.Status__c;
        details.recipientName = shipment.Recipient_Name__c;
        details.recipientAddress = shipment.Recipient_Address__c;
        details.recipientPhone = shipment.Recipient_Phone__c;
        details.estimatedDelivery = shipment.Estimated_Delivery__c;
        details.deliveryInstructions = shipment.Delivery_Instructions__c;
        details.rescheduleCount = (shipment.Reschedule_Count__c ?? 0).intValue();
        details.hasProof = shipment.Status__c == 'Delivered' && !String.isBlank(shipment.Proof_Id__c);
        details.canReschedule = (shipment.Status__c == 'Picked up' || shipment.Status__c == 'In transit') &&
            details.rescheduleCount < MAX_RESCHEDULES;
        details.earliestRescheduleDate = ShipmentRules.today().addDays(1);
        Date original = shipment.Original_Estimated_Delivery__c ?? shipment.Estimated_Delivery__c;
        details.latestRescheduleDate = original?.addDays(ShipmentRules.MAX_RESCHEDULE_DAYS_AFTER_ORIGINAL);
        return details;
    }
}
