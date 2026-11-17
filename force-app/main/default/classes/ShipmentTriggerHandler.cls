/**
 * @description Logic of ShipmentTrigger. Before insert: every shipment starts
 *              as Requested (BR-09), gets a new delivery access code stored only
 *              as an iterated salted hash (D1) and keeps its first estimated
 *              delivery (D4). After insert: the clear codes issued for
 *              DeliveryAccessCode.insertWithCodes are bound to the new record
 *              Ids. Before update: the access code hash and a filled original
 *              estimated delivery cannot be changed; a blank original estimate
 *              follows the first estimate; only the shipments of an active
 *              DeliveryAccessCode.reissueCodes call get a new code and hash.
 *              A holder of the custom permission RutaCargo_EntregaYa_Sender (the
 *              EntregaYa integration user) may update shipments only through
 *              EntregaYaStatusService: any other update by that user is refused
 *              on every row with a generic error (req-004 AC-004.9, BR-04).
 *              Agents and administrators without the permission are unaffected
 *              (BR-09).
 *              Works only on Trigger.new and Trigger.oldMap: no SOQL, no DML.
 */
public with sharing class ShipmentTriggerHandler {

    @TestVisible
    private static final String INITIAL_STATUS = 'Requested';
    private static final String SENDER_PERMISSION = 'RutaCargo_EntregaYa_Sender';
    @TestVisible
    private static final String DIRECT_SENDER_UPDATE_MESSAGE =
        'Status updates from EntregaYa must use the status service.';

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
        if (refuseDirectSenderUpdate(newShipments)) {
            return;
        }
        for (Shipment__c shipment : newShipments) {
            Shipment__c previous = oldShipments.get(shipment.Id);
            if (previous == null) {
                continue;
            }
            revertProtectedFields(shipment, previous);
            fillOriginalEstimate(shipment, previous);
        }
        DeliveryAccessCode.replaceReissuedCodes(newShipments);
    }

    // AC-004.9: a RutaCargo_EntregaYa_Sender holder writes only through
    // EntregaYaStatusService. One permission check per trigger batch.
    private static Boolean refuseDirectSenderUpdate(List<Shipment__c> newShipments) {
        if (EntregaYaStatusService.isApplying() || !FeatureManagement.checkPermission(SENDER_PERMISSION)) {
            return false;
        }
        for (Shipment__c shipment : newShipments) {
            shipment.addError(DIRECT_SENDER_UPDATE_MESSAGE);
        }
        return true;
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
