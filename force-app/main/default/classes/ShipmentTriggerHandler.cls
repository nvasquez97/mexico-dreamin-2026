public without sharing class ShipmentTriggerHandler {
  public static void beforeInsert(List<Shipment__c> shipments) {
    for (Shipment__c shipment : shipments) {
      if (String.isBlank(shipment.Status__c)) {
        // BR-09: a new shipment starts in Requested status.
        shipment.Status__c = ShipmentConstants.STATUS_REQUESTED;
      }
      if (shipment.Reschedule_Count__c == null) {
        shipment.Reschedule_Count__c = 0;
      }
      if (shipment.Last_Update__c == null) {
        shipment.Last_Update__c = RutaCargoDates.now();
      }
    }
  }
}
