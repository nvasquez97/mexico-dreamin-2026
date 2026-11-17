trigger ShipmentTrigger on Shipment__c(before insert) {
  ShipmentTriggerHandler.beforeInsert(Trigger.new);
}
