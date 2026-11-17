/**
 * @description Logic of ShipmentTrigger. Before insert: every shipment starts
 *              as Requested (BR-09), gets a new delivery access code stored only
 *              as an iterated salted hash (D1) and keeps its first estimated
 *              delivery (D4). After insert: the clear codes issued for
 *              DeliveryAccessCode.insertWithCodes are bound to the new record
 *              Ids. Before update: the access code hash and a filled original
 *              estimated delivery cannot be changed; a blank original estimate
 *              follows the first estimate. Works only on Trigger.new and
 *              Trigger.oldMap: no SOQL, no DML.
 */
public with sharing class ShipmentTriggerHandler {

    @TestVisible
    private static final String INITIAL_STATUS = 'Requested';

    /**
     * @description Before insert.
     * @param newShipments Trigger.new
     */
    public static void beforeInsert(List<Shipment__c> newShipments) {
        DeliveryAccessCode.issueCodes(newShipments);
        for (Shipment__c shipment : newShipments) {
            shipment.Status__c = INITIAL_STATUS;
            shipment.Original_Estimated_Delivery__c = shipment.Estimated_Delivery__c;
        }
    }

    /**
     * @description After insert.
     * @param newShipments Trigger.new
     */
    public static void afterInsert(List<Shipment__c> newShipments) {
        DeliveryAccessCode.bindCodes(newShipments);
    }

    /**
     * @description Before update.
     * @param newShipments Trigger.new
     * @param oldShipments Trigger.oldMap
     */
    public static void beforeUpdate(List<Shipment__c> newShipments, Map<Id, Shipment__c> oldShipments) {
        for (Shipment__c shipment : newShipments) {
            Shipment__c previous = oldShipments.get(shipment.Id);
            if (previous == null) {
                continue;
            }
            revertProtectedFields(shipment, previous);
            fillOriginalEstimate(shipment, previous);
        }
    }

    // Keeps the stored hash and a filled original estimated delivery.
    private static void revertProtectedFields(Shipment__c shipment, Shipment__c previous) {
        shipment.Delivery_Access_Code_Hash__c = previous.Delivery_Access_Code_Hash__c;
        if (previous.Original_Estimated_Delivery__c != null) {
            shipment.Original_Estimated_Delivery__c = previous.Original_Estimated_Delivery__c;
        }
    }

    // While the original estimate is blank, it follows the estimate and nothing else.
    private static void fillOriginalEstimate(Shipment__c shipment, Shipment__c previous) {
        if (previous.Original_Estimated_Delivery__c == null) {
            shipment.Original_Estimated_Delivery__c = shipment.Estimated_Delivery__c;
        }
    }
}
