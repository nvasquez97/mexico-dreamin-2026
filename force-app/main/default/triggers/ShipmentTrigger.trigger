/**
 * The only trigger on Shipment__c: event routing only, logic in ShipmentTriggerHandler.
 */
trigger ShipmentTrigger on Shipment__c (before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        ShipmentTriggerHandler.beforeInsert(Trigger.new);
    } else if (Trigger.isBefore && Trigger.isUpdate) {
        ShipmentTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    }
}
