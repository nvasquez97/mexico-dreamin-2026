/**
 * @description Logic of ShipmentTrigger. Before insert by a user whose UserType
 *              is not Standard (a customer or any other external user,
 *              odd/tasks/req-006-007-customer-shipments.md S1, AC-006.5): the
 *              shipment is forced to the running user's own account (BR-07), the
 *              BR-08 price and the BR-06 estimate of ShipmentRequestRules, and
 *              every internal field the user may have written (cost, notes,
 *              proof, delivery and tracking facts, reschedule count, hash, first
 *              estimate) is cleared, before the access code is issued; a broken
 *              rule (service type, weight, declared value, pickup date) or
 *              missing or invalid recipient data (name, address, phone, email,
 *              destination postal code and city) is a generic field error, and a
 *              user without an account is refused, so a direct UI API or DML
 *              create obeys the same rules as ShipmentRequestController. The
 *              customer has no FLS on the four recipient-owned fields (BR-02,
 *              G7): ShipmentRequestController stages their validated values for
 *              its one-row insert (stageRecipientValues) and this guard writes
 *              them, so a direct create, which cannot carry them, is refused.
 *              Internal (Standard) users are not changed by this guard. Then
 *              every shipment starts as Requested (BR-09), gets a new
 *              delivery access code stored only as an
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
    // CODE-003: the recipient data a customer insert must carry (AC-006.1).
    private static final List<Schema.SObjectField> REQUIRED_RECIPIENT_FIELDS = new List<Schema.SObjectField>{
        Shipment__c.Recipient_Name__c, Shipment__c.Recipient_Address__c, Shipment__c.Recipient_Phone__c,
        Shipment__c.Recipient_Email__c, Shipment__c.Destination_Postal_Code__c, Shipment__c.Destination_City__c
    };

    // Test seam (AC-006.5): the running user type the guard sees. Never set
    // outside tests.
    @TestVisible
    private static String runningUserTypeOverride;

    // SECURITY-JUSTIFICATION: BR-02 (G7) gives the customer no read or edit FLS
    // on Recipient_Address__c, Recipient_Phone__c, Recipient_Email__c and
    // Delivery_Instructions__c (the recipient may change them, REQ-003), yet
    // AC-006.1 stores them from the customer's request. Why: the user-mode
    // insert of DeliveryAccessCode.insertWithCodes cannot carry fields without
    // FLS, so this before-insert guard (trigger context, system mode) writes
    // them. Scope: only these four fields, only values staged by
    // ShipmentRequestController.submitRequest after its full server validation,
    // only on the next customer (non-Standard) insert of exactly one row, used
    // once and cleared by the controller in a finally block; nothing is read
    // back to the customer. Compensating controls: the stage is private to Apex
    // (no client can set it), the guard re-checks the recipient data, and
    // CustomerShipmentAccessTest proves the customer reads neither the fields
    // nor their history. (pending owner approval, 2026-11-18)
    private static Shipment__c stagedRecipientValues;

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

    /**
     * @description Stages the validated recipient-owned values of one customer
     *              request for the guard of the next one-row customer insert
     *              (BR-02, G7, AC-006.1). Only ShipmentRequestController calls it,
     *              after its full validation, and clears it in a finally block.
     * @param recipientAddress the recipient's address
     * @param recipientPhone the recipient's phone
     * @param recipientEmail the recipient's email
     * @param deliveryInstructions the optional delivery instructions
     */
    public static void stageRecipientValues(
        String recipientAddress, String recipientPhone, String recipientEmail, String deliveryInstructions
    ) {
        stagedRecipientValues = new Shipment__c(
            Recipient_Address__c = recipientAddress,
            Recipient_Phone__c = recipientPhone,
            Recipient_Email__c = recipientEmail,
            Delivery_Instructions__c = deliveryInstructions
        );
    }

    /**
     * @description Discards any staged recipient values (the controller's finally block).
     */
    public static void clearStagedRecipientValues() {
        stagedRecipientValues = null;
    }

    // AC-006.5: the guard keys on the user type, never on a profile name, so
    // any external profile that ever receives Create is covered.
    private static Boolean isExternalUser() {
        String userType = runningUserTypeOverride ?? UserInfo.getUserType();
        return userType != INTERNAL_USER_TYPE;
    }

    // AC-006.5 (BR-07, BR-08, BR-09, X6): the controller's rules for a direct create.
    private static void enforceCustomerRequest(List<Shipment__c> newShipments) {
        applyStagedRecipientValues(newShipments);
        Id accountId = ShipmentRequestRules.customerAccountId();
        for (Shipment__c shipment : newShipments) {
            clearInternalFields(shipment);
            shipment.Account__c = accountId;
            if (accountId == null) {
                shipment.addError(NOT_A_CUSTOMER_MESSAGE);
            } else if (hasValidRequestAndRecipientFields(shipment)) {
                shipment.Price__c = ShipmentRequestRules.price(
                    shipment.Service_Type__c, shipment.Weight_Kg__c, shipment.Declared_Value__c);
                shipment.Estimated_Delivery__c = ShipmentRequestRules.estimatedDelivery(
                    shipment.Service_Type__c, shipment.Pickup_Date__c);
            }
        }
    }

    // The staged values fill exactly one inserted row, once (see stagedRecipientValues).
    private static void applyStagedRecipientValues(List<Shipment__c> newShipments) {
        Shipment__c staged = stagedRecipientValues;
        stagedRecipientValues = null;
        if (staged == null || newShipments.size() != 1) {
            return;
        }
        Shipment__c shipment = newShipments[0];
        shipment.Recipient_Address__c = staged.Recipient_Address__c;
        shipment.Recipient_Phone__c = staged.Recipient_Phone__c;
        shipment.Recipient_Email__c = staged.Recipient_Email__c;
        shipment.Delivery_Instructions__c = staged.Delivery_Instructions__c;
    }

    // Both checks run, so every broken field gets its error.
    private static Boolean hasValidRequestAndRecipientFields(Shipment__c shipment) {
        Boolean validRecipient = hasValidRecipientFields(shipment);
        Boolean validRequest = hasValidRequestFields(shipment);
        return validRecipient && validRequest;
    }

    // CODE-003 (X6): the recipient data submitRequest requires; a generic
    // error on each missing or invalid field.
    private static Boolean hasValidRecipientFields(Shipment__c shipment) {
        Boolean valid = true;
        for (Schema.SObjectField field : REQUIRED_RECIPIENT_FIELDS) {
            if (String.isBlank((String) shipment.get(field))) {
                shipment.addError(field, INVALID_FIELD_MESSAGE);
                valid = false;
            }
        }
        if (String.isNotBlank(shipment.Recipient_Email__c) && !ShipmentRequestRules.isValidEmail(shipment.Recipient_Email__c)) {
            shipment.Recipient_Email__c.addError(INVALID_FIELD_MESSAGE);
            valid = false;
        }
        return valid;
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
