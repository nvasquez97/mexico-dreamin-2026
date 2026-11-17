/**
 * @description Delivery details returned to a verified recipient by
 *              RecipientDeliveryController (req-002-003 S2, BR-02, BR-03).
 *              Exactly these eleven values: no record Id, price, cost, notes,
 *              account, e-mail or access code hash. Dates are ISO strings
 *              (yyyy-MM-dd); the reschedule window is in America/Mexico_City.
 */
public with sharing class RecipientDeliveryDetails {
    @AuraEnabled public String recipientName;
    @AuraEnabled public String deliveryAddress;
    @AuraEnabled public String contactPhone;
    @AuraEnabled public String estimatedDelivery;
    @AuraEnabled public String deliveryInstructions;
    @AuraEnabled public String status;
    @AuraEnabled public Boolean canReschedule;
    @AuraEnabled public Integer reschedulesLeft;
    @AuraEnabled public String rescheduleFrom;
    @AuraEnabled public String rescheduleTo;
    @AuraEnabled public Boolean proofAvailable;
}
