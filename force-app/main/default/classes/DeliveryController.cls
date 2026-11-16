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
