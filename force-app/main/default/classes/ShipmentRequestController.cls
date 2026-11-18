/**
 * @description Shipment requests of registered customers on the site
 *              (odd/tasks/req-006-007-customer-shipments.md, S3; REQ-006).
 *              getQuote returns the BR-08 price and the pickup window before the
 *              customer confirms; submitRequest validates every AC-006.1 field,
 *              inserts the shipment in user mode through
 *              DeliveryAccessCode.insertWithCodes and returns the tracking number,
 *              the stored price and estimate, and the clear access code, shown
 *              once (A1). The request carries only the entered fields: the
 *              account, price, estimate and status are never taken from the
 *              client; ShipmentTriggerHandler sets them for every customer insert
 *              with the same ShipmentRequestRules (P2, P5, X6). The customer
 *              has no FLS on the four recipient-owned fields (recipient's
 *              address, phone, email, delivery instructions: BR-02, G7), so
 *              their validated values are staged for that guard
 *              (ShipmentTriggerHandler.stageRecipientValues), which writes them
 *              on this one-row insert only. Only a signed-in user with a
 *              customer account may call it (BR-07); errors are generic (no
 *              internal detail).
 */
public with sharing class ShipmentRequestController {

    /** @description The generic refusal for a caller without a customer account (guest, internal user). */
    public static final String NOT_AVAILABLE_MESSAGE = 'This service is available only to signed-in customers.';
    /** @description The generic message when the shipment cannot be saved. */
    public static final String SAVE_FAILED_MESSAGE = 'Your request could not be saved. Check the fields and try again.';

    private static final String INVALID_FIELDS_PREFIX = 'Check these fields: ';
    private static final String FIELD_SEPARATOR = ', ';
    private static final String GUEST_USER_TYPE = 'Guest';

    /**
     * @description The AC-006.1 fields of a request, one property per entered
     *              field (never a Shipment__c from the client).
     */
    public class ShipmentRequest {
        @AuraEnabled public String pickupAddress { get; set; }
        @AuraEnabled public String pickupCity { get; set; }
        @AuraEnabled public String pickupPostalCode { get; set; }
        @AuraEnabled public Date pickupDate { get; set; }
        @AuraEnabled public String recipientName { get; set; }
        @AuraEnabled public String recipientAddress { get; set; }
        @AuraEnabled public String recipientCity { get; set; }
        @AuraEnabled public String recipientPostalCode { get; set; }
        @AuraEnabled public String recipientPhone { get; set; }
        @AuraEnabled public String recipientEmail { get; set; }
        @AuraEnabled public String serviceType { get; set; }
        @AuraEnabled public Decimal weightKg { get; set; }
        @AuraEnabled public String packageDescription { get; set; }
        @AuraEnabled public Decimal declaredValue { get; set; }
        @AuraEnabled public String customerReference { get; set; }
        @AuraEnabled public String deliveryInstructions { get; set; }
    }

    /** @description The price at the current rate and the valid pickup window. */
    public class Quote {
        @AuraEnabled public Decimal price;
        @AuraEnabled public Date earliestPickupDate;
        @AuraEnabled public Date latestPickupDate;
    }

    /** @description What the customer sees once, after confirming. */
    public class Confirmation {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Date estimatedDelivery;
        @AuraEnabled public String accessCode;
    }

    /**
     * @description The BR-08 price of a request and the valid pickup window (AC-006.2, AC-006.3).
     * @param serviceType Standard or Express
     * @param weightKg the weight in kg (more than 0, at most 30, 2 decimals)
     * @param declaredValue the declared value in MXN (0 to 50,000)
     * @return the quote
     * @throws AuraHandledException a generic refusal or the invalid field names
     */
    @AuraEnabled
    public static Quote getQuote(String serviceType, Decimal weightKg, Decimal declaredValue) {
        requireCustomerAccount();
        List<String> invalidFields = new List<String>();
        addIfFalse(invalidFields, ShipmentRequestRules.isServiceType(serviceType), 'serviceType');
        addIfFalse(invalidFields, ShipmentRequestRules.isValidWeight(weightKg), 'weightKg');
        addIfFalse(invalidFields, ShipmentRequestRules.isValidDeclaredValue(declaredValue), 'declaredValue');
        throwIfInvalid(invalidFields);
        Quote quote = new Quote();
        quote.price = ShipmentRequestRules.price(serviceType, weightKg, declaredValue);
        quote.earliestPickupDate = ShipmentRequestRules.earliestPickupDate();
        quote.latestPickupDate = ShipmentRequestRules.latestPickupDate();
        return quote;
    }

    /**
     * @description Validates and creates the customer's shipment (AC-006.1 to AC-006.6).
     * @param request the entered fields
     * @return the tracking number, price, estimate and the clear access code (shown once)
     * @throws AuraHandledException a generic refusal or the invalid field names
     */
    @AuraEnabled
    public static Confirmation submitRequest(ShipmentRequest request) {
        requireCustomerAccount();
        ShipmentRequest entered = request ?? new ShipmentRequest();
        throwIfInvalid(invalidFieldsOf(entered));
        Shipment__c shipment = toShipment(entered);
        Map<Id, String> codes;
        Shipment__c saved;
        try {
            // SECURITY-JUSTIFICATION: see ShipmentTriggerHandler.stagedRecipientValues:
            // the four recipient-owned fields (no customer FLS, BR-02) of this
            // validated request only, written by the guard on this one-row
            // insert and cleared below. (pending owner approval, 2026-11-18)
            ShipmentTriggerHandler.stageRecipientValues(
                clean(entered.recipientAddress), clean(entered.recipientPhone),
                clean(entered.recipientEmail), clean(entered.deliveryInstructions));
            codes = DeliveryAccessCode.insertWithCodes(new List<Shipment__c>{ shipment });
            saved = [
                SELECT Name, Price__c, Estimated_Delivery__c FROM Shipment__c
                WHERE Id = :shipment.Id
                WITH USER_MODE
                LIMIT 1
            ];
        } catch (DmlException e) {
            throw userError(SAVE_FAILED_MESSAGE);
        } catch (QueryException e) {
            throw userError(SAVE_FAILED_MESSAGE);
        } catch (System.SecurityException e) {
            throw userError(NOT_AVAILABLE_MESSAGE);
        } finally {
            ShipmentTriggerHandler.clearStagedRecipientValues();
        }
        Confirmation confirmation = new Confirmation();
        confirmation.trackingNumber = saved.Name;
        confirmation.price = saved.Price__c;
        confirmation.estimatedDelivery = saved.Estimated_Delivery__c;
        confirmation.accessCode = codes.get(shipment.Id);
        return confirmation;
    }

    // BR-07: only a signed-in user with a customer account (User.AccountId).
    private static void requireCustomerAccount() {
        if (UserInfo.getUserType() == GUEST_USER_TYPE) {
            throw userError(NOT_AVAILABLE_MESSAGE);
        }
        if (ShipmentRequestRules.customerAccountId() == null) {
            throw userError(NOT_AVAILABLE_MESSAGE);
        }
    }

    // The names of the invalid fields, in the order of the form (AC-006.1, AC-006.3, AC-006.4).
    private static List<String> invalidFieldsOf(ShipmentRequest request) {
        List<String> invalidFields = new List<String>();
        addIfFalse(invalidFields, fits(request.pickupAddress, Shipment__c.Pickup_Address__c, true), 'pickupAddress');
        addIfFalse(invalidFields, fits(request.pickupCity, Shipment__c.Origin_City__c, true), 'pickupCity');
        addIfFalse(invalidFields, fits(request.pickupPostalCode, Shipment__c.Pickup_Postal_Code__c, true), 'pickupPostalCode');
        addIfFalse(invalidFields, ShipmentRequestRules.isValidPickupDate(request.pickupDate), 'pickupDate');
        addIfFalse(invalidFields, fits(request.recipientName, Shipment__c.Recipient_Name__c, true), 'recipientName');
        addIfFalse(invalidFields, fits(request.recipientAddress, Shipment__c.Recipient_Address__c, true), 'recipientAddress');
        addIfFalse(invalidFields, fits(request.recipientCity, Shipment__c.Destination_City__c, true), 'recipientCity');
        addIfFalse(invalidFields, fits(request.recipientPostalCode, Shipment__c.Destination_Postal_Code__c, true), 'recipientPostalCode');
        addIfFalse(invalidFields, fits(request.recipientPhone, Shipment__c.Recipient_Phone__c, true), 'recipientPhone');
        addIfFalse(invalidFields, fits(request.recipientEmail, Shipment__c.Recipient_Email__c, true)
            && ShipmentRequestRules.isValidEmail(request.recipientEmail), 'recipientEmail');
        addIfFalse(invalidFields, ShipmentRequestRules.isServiceType(request.serviceType), 'serviceType');
        addIfFalse(invalidFields, ShipmentRequestRules.isValidWeight(request.weightKg), 'weightKg');
        addIfFalse(invalidFields, fits(request.packageDescription, Shipment__c.Package_Description__c, true), 'packageDescription');
        addIfFalse(invalidFields, ShipmentRequestRules.isValidDeclaredValue(request.declaredValue), 'declaredValue');
        addIfFalse(invalidFields, fits(request.customerReference, Shipment__c.Customer_Reference__c, false), 'customerReference');
        addIfFalse(invalidFields, fits(request.deliveryInstructions, Shipment__c.Delivery_Instructions__c, false), 'deliveryInstructions');
        return invalidFields;
    }

    // A text value is present when required and fits the field's length.
    private static Boolean fits(String value, Schema.SObjectField field, Boolean required) {
        if (String.isBlank(value)) {
            return !required;
        }
        return value.trim().length() <= field.getDescribe().getLength();
    }

    private static void addIfFalse(List<String> invalidFields, Boolean valid, String fieldName) {
        if (!valid) {
            invalidFields.add(fieldName);
        }
    }

    private static void throwIfInvalid(List<String> invalidFields) {
        if (!invalidFields.isEmpty()) {
            throw userError(INVALID_FIELDS_PREFIX + String.join(invalidFields, FIELD_SEPARATOR));
        }
    }

    // Only the entered fields the customer may write: Account__c, Price__c,
    // Estimated_Delivery__c and Status__c are set by ShipmentTriggerHandler (S3),
    // and so are the four staged recipient-owned fields (BR-02, G7).
    private static Shipment__c toShipment(ShipmentRequest request) {
        return new Shipment__c(
            Pickup_Address__c = clean(request.pickupAddress),
            Origin_City__c = clean(request.pickupCity),
            Pickup_Postal_Code__c = clean(request.pickupPostalCode),
            Pickup_Date__c = request.pickupDate,
            Recipient_Name__c = clean(request.recipientName),
            Destination_City__c = clean(request.recipientCity),
            Destination_Postal_Code__c = clean(request.recipientPostalCode),
            Service_Type__c = request.serviceType,
            Weight_Kg__c = request.weightKg,
            Package_Description__c = clean(request.packageDescription),
            Declared_Value__c = request.declaredValue,
            Customer_Reference__c = clean(request.customerReference)
        );
    }

    private static String clean(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
