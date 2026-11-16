/**
 * Door-to-door shipment requests by registered customers (REQ-006).
 *
 * WITH SHARING. The account comes from the session (CustomerContext), never
 * from the browser (BR-07). Inputs are individual fields validated here.
 * The insert runs in SYSTEM MODE on purpose: the customer has read-only
 * access to Shipment__c, because the price, the status and the tracking
 * number are set by RutaCargo, not by the customer (BR-08, BR-09, BR-05).
 * Only the fields listed in buildShipment() are written.
 */
public with sharing class ShipmentRequestController {
    private static final Pattern POSTAL_PATTERN = Pattern.compile('^[0-9]{5}$');
    private static final Pattern PHONE_PATTERN = Pattern.compile('^\\+?[0-9 ()\\-]{7,20}$');
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$');

    /** Price and estimated delivery shown before confirming (AC-006.2, AC-006.6). */
    public class QuoteResult {
        @AuraEnabled public Decimal price;
        @AuraEnabled public Date estimatedDelivery;
    }

    /** Created shipment as shown on screen (AC-006.5). */
    public class RequestResult {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Date estimatedDelivery;
    }

    /**
     * @return price with the current rate and estimated delivery date
     * @throws AuraHandledException with a user-facing message on invalid input
     */
    @AuraEnabled
    public static QuoteResult getQuote(String serviceType, Decimal weightKg, Decimal declaredValue, Date pickupDate) {
        CustomerContext.getCurrentAccountId();
        validatePickupDate(pickupDate);
        return quote(serviceType, weightKg, declaredValue, pickupDate);
    }

    /**
     * Creates the shipment under the current customer in Requested status (AC-006.5).
     * @return tracking number, price and estimated delivery
     * @throws AuraHandledException with a user-facing message on invalid input
     */
    @AuraEnabled
    public static RequestResult createShipment(
        String pickupAddress, String pickupCity, String pickupPostalCode, Date pickupDate,
        String recipientName, String recipientAddress, String recipientCity, String recipientPostalCode,
        String recipientPhone, String recipientEmail, String serviceType, Decimal weightKg,
        String packageDescription, Decimal declaredValue, String customerReference, String deliveryInstructions
    ) {
        Id accountId = CustomerContext.getCurrentAccountId();
        requireText(pickupAddress, 'pickup address', 1000);
        requireText(pickupCity, 'pickup city', 80);
        requirePostalCode(pickupPostalCode, 'pickup postal code');
        validatePickupDate(pickupDate);
        requireText(recipientName, 'recipient name', 120);
        requireText(recipientAddress, 'recipient address', 1000);
        requireText(recipientCity, 'recipient city', 80);
        requirePostalCode(recipientPostalCode, 'recipient postal code');
        if (String.isBlank(recipientPhone) || !PHONE_PATTERN.matcher(recipientPhone.trim()).matches()) {
            throw AuraErrors.of('Enter a valid recipient phone.');
        }
        if (String.isBlank(recipientEmail) || !EMAIL_PATTERN.matcher(recipientEmail.trim()).matches()) {
            throw AuraErrors.of('Enter a valid recipient email.');
        }
        requireText(packageDescription, 'description of the contents', 255);
        optionalText(customerReference, 'order reference', 50);
        optionalText(deliveryInstructions, 'delivery instructions', 1000);
        QuoteResult priced = quote(serviceType, weightKg, declaredValue, pickupDate);

        Shipment__c shipment = new Shipment__c(
            Account__c = accountId,
            Status__c = 'Requested',
            Service_Type__c = serviceType,
            Pickup_Address__c = pickupAddress.trim(),
            Origin_City__c = pickupCity.trim(),
            Pickup_Postal_Code__c = pickupPostalCode.trim(),
            Pickup_Date__c = pickupDate,
            Recipient_Name__c = recipientName.trim(),
            Recipient_Address__c = recipientAddress.trim(),
            Destination_City__c = recipientCity.trim(),
            Destination_Postal_Code__c = recipientPostalCode.trim(),
            Recipient_Phone__c = recipientPhone.trim(),
            Recipient_Email__c = recipientEmail.trim().toLowerCase(),
            Package_Description__c = packageDescription.trim(),
            Weight_Kg__c = weightKg,
            Declared_Value__c = declaredValue,
            Customer_Reference__c = String.isBlank(customerReference) ? null : customerReference.trim(),
            Delivery_Instructions__c = String.isBlank(deliveryInstructions) ? null : deliveryInstructions.trim(),
            Price__c = priced.price,
            Estimated_Delivery__c = priced.estimatedDelivery,
            Original_Estimated_Delivery__c = priced.estimatedDelivery,
            Reschedule_Count__c = 0
        );
        // System mode: see class comment.
        Database.insert(shipment, AccessLevel.SYSTEM_MODE);
        Shipment__c saved = [SELECT Name FROM Shipment__c WHERE Id = :shipment.Id WITH SYSTEM_MODE];
        RequestResult result = new RequestResult();
        result.trackingNumber = saved.Name;
        result.price = priced.price;
        result.estimatedDelivery = priced.estimatedDelivery;
        return result;
    }

    private static QuoteResult quote(String serviceType, Decimal weightKg, Decimal declaredValue, Date pickupDate) {
        QuoteResult result = new QuoteResult();
        try {
            result.price = PricingService.calculatePrice(serviceType, weightKg, declaredValue);
            result.estimatedDelivery = BusinessCalendar.addBusinessDays(pickupDate, PricingService.getTransitBusinessDays(serviceType));
        } catch (PricingService.PricingException e) {
            throw AuraErrors.of(e.getMessage());
        }
        return result;
    }

    private static void validatePickupDate(Date pickupDate) {
        if (!BusinessCalendar.isValidPickupDate(pickupDate)) {
            throw AuraErrors.of('The pickup date must be a business day between tomorrow and 15 days from today.');
        }
    }

    private static void requireText(String value, String label, Integer maxLength) {
        if (String.isBlank(value)) {
            throw AuraErrors.of('Enter the ' + label + '.');
        }
        optionalText(value, label, maxLength);
    }

    private static void optionalText(String value, String label, Integer maxLength) {
        if (value != null && value.trim().length() > maxLength) {
            throw AuraErrors.of('The ' + label + ' can have up to ' + maxLength + ' characters.');
        }
    }

    private static void requirePostalCode(String value, String label) {
        if (value == null || !POSTAL_PATTERN.matcher(value.trim()).matches()) {
            throw AuraErrors.of('Enter a valid ' + label + ' (5 digits).');
        }
    }
}
