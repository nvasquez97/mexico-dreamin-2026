/**
 * Recipient self-service for site visitors without login: delivery details
 * (REQ-002), proof of delivery (AC-002.4) and rescheduling (REQ-003).
 *
 * WITHOUT SHARING: the caller is the site guest user, who has no object
 * permissions. Access to a shipment is granted only by
 * DeliveryAccessService.verify (tracking number + destination postal code),
 * repeated on every call. Responses carry only the recipient fields of
 * AC-002.2; never price, cost, margin, notes or customer data (BR-02, BR-03).
 */
public without sharing class DeliveryController {
    public static final Set<String> RESCHEDULABLE_STATUSES = new Set<String>{ 'Picked up', 'In transit' };
    public static final Integer MAX_RESCHEDULES = 2;
    public static final Integer RESCHEDULE_WINDOW_DAYS = 7;

    /** Response for every recipient operation; failures carry a user-facing message. */
    public class DeliveryResponse {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String message;
        @AuraEnabled public DeliveryDetails details;
    }

    /** Recipient view of a shipment (AC-002.2) plus what the recipient may do next. */
    public class DeliveryDetails {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String recipientAddress;
        @AuraEnabled public String recipientPhone;
        @AuraEnabled public Date estimatedDelivery;
        @AuraEnabled public String deliveryInstructions;
        @AuraEnabled public Boolean canDownloadProof;
        @AuraEnabled public Boolean canReschedule;
        @AuraEnabled public Integer reschedulesLeft;
        @AuraEnabled public Date minRescheduleDate;
        @AuraEnabled public Date maxRescheduleDate;
    }

    /** Proof of delivery download result (AC-002.4, AC-002.5). */
    public class ProofResponse {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String message;
        @AuraEnabled public String fileName;
        @AuraEnabled public String pdfBase64;
    }

    public static final String PROOF_UNAVAILABLE = 'We could not get the proof of delivery, please try again later';
    public static final String PROOF_NOT_READY = 'The proof of delivery is available once the shipment is delivered.';

    /**
     * Fetches the signed proof of delivery from EntregaYa for a Delivered
     * shipment (AC-002.4). The PDF is returned to the browser and never stored.
     * @param trackingNumber tracking number of the shipment
     * @param postalCode destination postal code typed by the recipient
     * @return the PDF as base64, or a user-facing message (AC-002.5)
     */
    @AuraEnabled
    public static ProofResponse downloadProof(String trackingNumber, String postalCode) {
        ProofResponse response = new ProofResponse();
        DeliveryAccessService.AccessResult access = DeliveryAccessService.verifyBeforeCallout(trackingNumber, postalCode);
        if (!access.granted) {
            response.message = access.message;
            return response;
        }
        Shipment__c shipment = access.shipment;
        if (shipment.Status__c != 'Delivered' || String.isBlank(shipment.Proof_Id__c)) {
            response.message = PROOF_NOT_READY;
            return response;
        }
        try {
            EntregaYaClient.ProofFile proof = EntregaYaClient.getProof(shipment.Proof_Id__c, shipment.Name);
            response.success = true;
            response.pdfBase64 = proof.pdfBase64;
            response.fileName = 'proof-of-delivery-' + shipment.Name + '.pdf';
        } catch (EntregaYaClient.EntregaYaException e) {
            // Provider details stay on the server; the visitor sees the AC-002.5 message.
            response.message = PROOF_UNAVAILABLE;
        }
        DeliveryAccessService.clearFailedAttempts(shipment);
        return response;
    }

    /**
     * @param trackingNumber tracking number of the shipment
     * @param postalCode destination postal code typed by the recipient (AC-002.1)
     * @return the delivery details, or "The details do not match this shipment" (AC-002.3)
     */
    @AuraEnabled
    public static DeliveryResponse getDeliveryDetails(String trackingNumber, String postalCode) {
        DeliveryAccessService.AccessResult access = DeliveryAccessService.verify(trackingNumber, postalCode);
        if (!access.granted) {
            return failure(access.message);
        }
        DeliveryResponse response = new DeliveryResponse();
        response.success = true;
        response.details = toDetails(access.shipment);
        return response;
    }

    public static final Integer MAX_INSTRUCTIONS_LENGTH = 1000;

    /**
     * Changes the delivery date and instructions (REQ-003). Every rule is
     * checked here on the server with the shipment row locked. The change is
     * recorded by field history on the shipment (AC-003.5).
     * @param trackingNumber tracking number of the shipment
     * @param postalCode destination postal code typed by the recipient
     * @param newDate new delivery date: from tomorrow (Mexico City) to the original estimate + 7 days
     * @param instructions new delivery instructions, at most 1,000 characters
     * @return the updated details, or a user-facing message
     */
    @AuraEnabled
    public static DeliveryResponse reschedule(String trackingNumber, String postalCode, Date newDate, String instructions) {
        DeliveryAccessService.AccessResult access = DeliveryAccessService.verify(trackingNumber, postalCode);
        if (!access.granted) {
            return failure(access.message);
        }
        Shipment__c shipment = access.shipment;
        String problem = validateReschedule(shipment, newDate, instructions);
        if (problem != null) {
            return failure(problem);
        }
        shipment.Original_Estimated_Delivery__c = shipment.Original_Estimated_Delivery__c ?? shipment.Estimated_Delivery__c;
        shipment.Estimated_Delivery__c = newDate;
        shipment.Delivery_Instructions__c = instructions?.trim();
        shipment.Reschedule_Count__c = (shipment.Reschedule_Count__c ?? 0) + 1;
        // System mode: the guest has no object permissions (see class comment). Only these four fields change.
        Database.update(
            new Shipment__c(
                Id = shipment.Id,
                Original_Estimated_Delivery__c = shipment.Original_Estimated_Delivery__c,
                Estimated_Delivery__c = shipment.Estimated_Delivery__c,
                Delivery_Instructions__c = shipment.Delivery_Instructions__c,
                Reschedule_Count__c = shipment.Reschedule_Count__c
            ),
            AccessLevel.SYSTEM_MODE
        );
        DeliveryResponse response = new DeliveryResponse();
        response.success = true;
        response.details = toDetails(shipment);
        return response;
    }

    private static String validateReschedule(Shipment__c shipment, Date newDate, String instructions) {
        if (!RESCHEDULABLE_STATUSES.contains(shipment.Status__c)) {
            return 'Only shipments that are picked up or in transit can be rescheduled.';
        }
        if ((shipment.Reschedule_Count__c ?? 0) >= MAX_RESCHEDULES) {
            return 'This delivery has already been rescheduled 2 times.';
        }
        DeliveryDetails window = toDetails(shipment);
        if (newDate == null || window.maxRescheduleDate == null ||
            newDate < window.minRescheduleDate || newDate > window.maxRescheduleDate) {
            return 'Choose a date between ' + formatDate(window.minRescheduleDate) + ' and ' + formatDate(window.maxRescheduleDate) + '.';
        }
        if (instructions != null && instructions.trim().length() > MAX_INSTRUCTIONS_LENGTH) {
            return 'Delivery instructions can have up to 1,000 characters.';
        }
        return null;
    }

    private static String formatDate(Date value) {
        return value == null ? '' : Datetime.newInstanceGmt(value, Time.newInstance(12, 0, 0, 0)).formatGmt('MMM d, yyyy');
    }

    @TestVisible
    private static DeliveryResponse failure(String message) {
        DeliveryResponse response = new DeliveryResponse();
        response.message = message;
        return response;
    }

    @TestVisible
    private static DeliveryDetails toDetails(Shipment__c shipment) {
        DeliveryDetails details = new DeliveryDetails();
        details.trackingNumber = shipment.Name;
        details.status = shipment.Status__c;
        details.recipientName = shipment.Recipient_Name__c;
        details.recipientAddress = shipment.Recipient_Address__c;
        details.recipientPhone = shipment.Recipient_Phone__c;
        details.estimatedDelivery = shipment.Estimated_Delivery__c;
        details.deliveryInstructions = shipment.Delivery_Instructions__c;
        details.canDownloadProof = shipment.Status__c == 'Delivered' && String.isNotBlank(shipment.Proof_Id__c);
        Integer used = (shipment.Reschedule_Count__c ?? 0).intValue();
        details.reschedulesLeft = Math.max(0, MAX_RESCHEDULES - used);
        details.canReschedule = RESCHEDULABLE_STATUSES.contains(shipment.Status__c) && details.reschedulesLeft > 0;
        details.minRescheduleDate = BusinessCalendar.todayInMexicoCity().addDays(1);
        Date anchor = shipment.Original_Estimated_Delivery__c ?? shipment.Estimated_Delivery__c;
        details.maxRescheduleDate = anchor?.addDays(RESCHEDULE_WINDOW_DAYS);
        return details;
    }
}
