/**
 * @description Logic of ShipmentTrigger. Before insert by a user whose UserType
 *              is not Standard (a customer or any other external user,
 *              odd/tasks/req-006-007-customer-shipments.md S1, AC-006.5): the
 *              shipment is forced to the running user's own account (BR-07), the
 *              BR-08 price and the BR-06 estimate of ShipmentRequestRules, and
 *              every internal field the user may have written (cost, notes,
 *              proof, delivery and tracking facts, reschedule count, hash, first
 *              estimate) is cleared, before the access code is issued; a broken
 *              rule (service type, weight, declared value, pickup date) is a
 *              generic field error, and a user without an account is refused, so
 *              a direct UI API or DML create obeys the same rules as
 *              ShipmentRequestController. Internal (Standard) users are not
 *              changed by this guard. Then every shipment starts as Requested
 *              (BR-09), gets a new delivery access code stored only as an
 *              iterated salted hash (D1) and keeps its first estimated
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
 *              Works on Trigger.new and Trigger.oldMap, no DML; its only SOQL
 *              is ShipmentRequestRules.customerAccountId (the running user's
 *              own AccountId, at most once per user and transaction), and only
 *              for a non-Standard user's insert.
 */
public with sharing class ShipmentTriggerHandler {

    @TestVisible
    private static final String INITIAL_STATUS = 'Requested';
    private static final String SENDER_PERMISSION = 'RutaCargo_EntregaYa_Sender';
    @TestVisible
    private static final String DIRECT_SENDER_UPDATE_MESSAGE =
        'Status updates from EntregaYa must use the status service.';
    private static final String INTERNAL_USER_TYPE = 'Standard';
    @TestVisible
    private static final String INVALID_FIELD_MESSAGE = 'Check this field.';
    @TestVisible
    private static final String NOT_A_CUSTOMER_MESSAGE = 'Shipments can be requested only by a customer account.';

    // Test seam (AC-006.5): the running user type the guard sees. Never set
    // outside tests.
    @TestVisible
    private static String runningUserTypeOverride;

    /**
     * @description Before insert.
     * @param newShipments Trigger.new
     */
    public static void beforeInsert(List<Shipment__c> newShipments) {
        // Before the code is issued: clearing the internal fields must never
        // wipe the new hash.
        if (isExternalUser()) {
            enforceCustomerRequest(newShipments);
        }
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

    // AC-006.5: the guard keys on the user type, never on a profile name, so
    // any external profile that ever receives Create is covered.
    private static Boolean isExternalUser() {
        String userType = runningUserTypeOverride ?? UserInfo.getUserType();
        return userType != INTERNAL_USER_TYPE;
    }

    // AC-006.5 (BR-07, BR-08, BR-09, X6): the controller's rules for a direct create.
    private static void enforceCustomerRequest(List<Shipment__c> newShipments) {
        Id accountId = ShipmentRequestRules.customerAccountId();
        for (Shipment__c shipment : newShipments) {
            clearInternalFields(shipment);
            shipment.Account__c = accountId;
            if (accountId == null) {
                shipment.addError(NOT_A_CUSTOMER_MESSAGE);
            } else if (hasValidRequestFields(shipment)) {
                shipment.Price__c = ShipmentRequestRules.price(
                    shipment.Service_Type__c, shipment.Weight_Kg__c, shipment.Declared_Value__c);
                shipment.Estimated_Delivery__c = ShipmentRequestRules.estimatedDelivery(
                    shipment.Service_Type__c, shipment.Pickup_Date__c);
            }
        }
    }

    // Values only RutaCargo, EntregaYa or the trigger set (BR-03, BR-09).
    private static void clearInternalFields(Shipment__c shipment) {
        shipment.Price__c = null;
        shipment.Estimated_Delivery__c = null;
        shipment.Original_Estimated_Delivery__c = null;
        shipment.Carrier_Cost__c = null;
        shipment.Internal_Notes__c = null;
        shipment.Proof_Id__c = null;
        shipment.Delivered_At__c = null;
        shipment.Last_Location__c = null;
        shipment.Last_Update__c = null;
        shipment.Reschedule_Count__c = 0;
        shipment.Delivery_Access_Code_Hash__c = null;
    }

    // Adds a generic error to each field that breaks a rule.
    private static Boolean hasValidRequestFields(Shipment__c shipment) {
        Boolean valid = true;
        if (!ShipmentRequestRules.isServiceType(shipment.Service_Type__c)) {
            shipment.Service_Type__c.addError(INVALID_FIELD_MESSAGE);
            valid = false;
        }
        if (!ShipmentRequestRules.isValidWeight(shipment.Weight_Kg__c)) {
            shipment.Weight_Kg__c.addError(INVALID_FIELD_MESSAGE);
            valid = false;
        }
        if (!ShipmentRequestRules.isValidDeclaredValue(shipment.Declared_Value__c)) {
            shipment.Declared_Value__c.addError(INVALID_FIELD_MESSAGE);
            valid = false;
        }
        if (!ShipmentRequestRules.isValidPickupDate(shipment.Pickup_Date__c)) {
            shipment.Pickup_Date__c.addError(INVALID_FIELD_MESSAGE);
            valid = false;
        }
        return valid;
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
