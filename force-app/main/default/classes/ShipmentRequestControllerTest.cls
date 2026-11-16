/**
 * Tests for ShipmentRequestController, run as a real customer site user with
 * the RutaCargo_Customer permission set. Today is fixed to Tuesday
 * 2026-11-17 in Mexico City.
 * Covers AC-006.1 to AC-006.6, BR-08 and BR-09.
 */
@IsTest
private class ShipmentRequestControllerTest {
    private static final Datetime TUESDAY_NOON_MX = Datetime.newInstanceGmt(2026, 11, 17, 18, 0, 0);
    private static final Date WEDNESDAY = Date.newInstance(2026, 11, 18);

    @TestSetup
    static void setup() {
        TestDataFactory.createCustomerUser('Request Test SA', 'Requester', 'RutaCargo_Customer');
    }

    private static User customer() {
        return [SELECT Id, Contact.AccountId FROM User WHERE LastName = 'Requester' AND IsActive = true WITH SYSTEM_MODE LIMIT 1];
    }

    private static ShipmentRequestController.RequestResult create(String serviceType, Decimal weightKg, Decimal declaredValue, Date pickupDate, String recipientPostalCode) {
        BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
        return ShipmentRequestController.createShipment(
            'Av. Juarez 100, Centro', 'Ciudad de Mexico', '06000', pickupDate,
            'Laura Garza', 'Calle Hidalgo 200, Centro', 'Monterrey', recipientPostalCode, '+52 81 5555 0101', 'laura.garza@example.com',
            serviceType, weightKg, 'Books', declaredValue, 'PO-123', 'Ring twice'
        );
    }

    private static void assertCreateRejected(String serviceType, Decimal weightKg, Decimal declaredValue, Date pickupDate, String postalCode, String expectedText) {
        System.runAs(customer()) {
            try {
                create(serviceType, weightKg, declaredValue, pickupDate, postalCode);
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().toLowerCase().contains(expectedText), 'Message should mention ' + expectedText + ': ' + e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WITH SYSTEM_MODE], 'Nothing created');
    }

    // Covers AC-006.2, AC-006.6, BR-08: the quote shows price and estimated delivery before confirming.
    @IsTest
    static void shouldReturnPriceAndEstimate_WhenQuoting() {
        ShipmentRequestController.QuoteResult quote;
        System.runAs(customer()) {
            BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
            Test.startTest();
            quote = ShipmentRequestController.getQuote('Standard', 2, 1000, WEDNESDAY);
            Test.stopTest();
        }
        Assert.areEqual(171.00, quote.price, '120 + 2 x 18 + 1.5% of 1,000');
        Assert.areEqual(Date.newInstance(2026, 11, 25), quote.estimatedDelivery, 'Wednesday + 5 business days');
    }

    // Covers AC-006.5, AC-006.1, BR-09: the shipment is created under the customer, Requested, with a tracking number.
    @IsTest
    static void shouldCreateRequestedShipmentUnderCustomer_WhenValid() {
        User requester = customer();
        ShipmentRequestController.RequestResult result;
        System.runAs(requester) {
            result = create('Standard', 2, 1000, WEDNESDAY, '64000');
        }
        Assert.isTrue(Pattern.matches('RC[0-9]{9}', result.trackingNumber), 'Tracking number RC + 9 digits: ' + result.trackingNumber);
        Shipment__c saved = [
            SELECT Name, Account__c, Status__c, Price__c, Estimated_Delivery__c, Original_Estimated_Delivery__c,
                Pickup_Date__c, Origin_City__c, Destination_City__c, Destination_Postal_Code__c, Customer_Reference__c,
                Delivery_Instructions__c, Recipient_Email__c, Weight_Kg__c, Declared_Value__c, Service_Type__c, Reschedule_Count__c
            FROM Shipment__c WITH SYSTEM_MODE LIMIT 1
        ];
        Assert.areEqual(result.trackingNumber, saved.Name, 'Tracking number shown is the saved one');
        Assert.areEqual(requester.Contact.AccountId, saved.Account__c, 'Under the customer account');
        Assert.areEqual('Requested', saved.Status__c, 'Requested status');
        Assert.areEqual(171.00, saved.Price__c, 'Price set by RutaCargo');
        Assert.areEqual('Ciudad de Mexico', saved.Origin_City__c, 'Origin city from pickup city');
        Assert.areEqual('Monterrey', saved.Destination_City__c, 'Destination city');
        Assert.areEqual('PO-123', saved.Customer_Reference__c, 'Reference');
        Assert.areEqual('Ring twice', saved.Delivery_Instructions__c, 'Instructions');
        Assert.areEqual(0, saved.Reschedule_Count__c, 'No reschedules');
    }

    // Covers AC-006.6: Standard = pickup + 5 business days; the original estimate is stored too.
    @IsTest
    static void shouldEstimateFiveBusinessDays_WhenStandard() {
        System.runAs(customer()) {
            create('Standard', 2, 1000, WEDNESDAY, '64000');
        }
        Shipment__c saved = [SELECT Estimated_Delivery__c, Original_Estimated_Delivery__c FROM Shipment__c WITH SYSTEM_MODE LIMIT 1];
        Assert.areEqual(Date.newInstance(2026, 11, 25), saved.Estimated_Delivery__c, 'Wednesday + 5 business days');
        Assert.areEqual(saved.Estimated_Delivery__c, saved.Original_Estimated_Delivery__c, 'Original estimate stored');
    }

    // Covers AC-006.6: Express = pickup + 2 business days.
    @IsTest
    static void shouldEstimateTwoBusinessDays_WhenExpress() {
        ShipmentRequestController.RequestResult result;
        System.runAs(customer()) {
            result = create('Express', 10, 50000, WEDNESDAY, '64000');
        }
        Assert.areEqual(Date.newInstance(2026, 11, 20), result.estimatedDelivery, 'Wednesday + 2 business days');
        Assert.areEqual(1270.00, result.price, 'Express price');
    }

    // Covers AC-006.3: a weekend pickup date is rejected.
    @IsTest
    static void shouldReject_WhenPickupOnWeekend() {
        assertCreateRejected('Standard', 2, 1000, Date.newInstance(2026, 11, 21), '64000', 'business day');
    }

    // Covers AC-006.3: today is rejected as pickup date.
    @IsTest
    static void shouldReject_WhenPickupToday() {
        assertCreateRejected('Standard', 2, 1000, Date.newInstance(2026, 11, 17), '64000', 'business day');
    }

    // Covers AC-006.3: more than 15 days ahead is rejected.
    @IsTest
    static void shouldReject_WhenPickupTooFar() {
        assertCreateRejected('Standard', 2, 1000, Date.newInstance(2026, 12, 3), '64000', 'business day');
    }

    // Covers AC-006.4: more than 30 kg is rejected.
    @IsTest
    static void shouldReject_WhenWeightAboveLimit() {
        assertCreateRejected('Standard', 31, 1000, WEDNESDAY, '64000', 'maximum weight');
    }

    // Covers AC-006.4: more than 50,000 MXN declared value is rejected.
    @IsTest
    static void shouldReject_WhenDeclaredValueAboveLimit() {
        assertCreateRejected('Standard', 2, 50001, WEDNESDAY, '64000', 'maximum declared value');
    }

    // Covers AC-006.1: an invalid postal code is rejected.
    @IsTest
    static void shouldReject_WhenPostalCodeInvalid() {
        assertCreateRejected('Standard', 2, 1000, WEDNESDAY, '6400A', 'postal code');
    }

    // Covers AC-006.1: an invalid service type is rejected.
    @IsTest
    static void shouldReject_WhenServiceTypeInvalid() {
        assertCreateRejected('Overnight', 2, 1000, WEDNESDAY, '64000', 'service type');
    }

    // Covers AC-006.1: required fields must be present.
    @IsTest
    static void shouldReject_WhenRequiredFieldMissing() {
        System.runAs(customer()) {
            BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
            try {
                ShipmentRequestController.createShipment(
                    '', 'Ciudad de Mexico', '06000', WEDNESDAY,
                    'Laura Garza', 'Calle Hidalgo 200', 'Monterrey', '64000', '+52 81 5555 0101', 'laura.garza@example.com',
                    'Standard', 2, 'Books', 1000, null, null
                );
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('pickup address'), 'Message: ' + e.getMessage());
            }
        }
    }

    // Covers AC-006.1: reference and instructions are optional.
    @IsTest
    static void shouldCreate_WhenOptionalFieldsBlank() {
        ShipmentRequestController.RequestResult result;
        System.runAs(customer()) {
            BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
            result = ShipmentRequestController.createShipment(
                'Av. Juarez 100', 'Ciudad de Mexico', '06000', WEDNESDAY,
                'Laura Garza', 'Calle Hidalgo 200', 'Monterrey', '64000', '+52 81 5555 0101', 'laura.garza@example.com',
                'Standard', 2, 'Books', 1000, null, ''
            );
        }
        Assert.isNotNull(result.trackingNumber, 'Created without optional fields');
    }

    // Covers BR-07: a user who is not a site customer cannot request shipments.
    @IsTest
    static void shouldReject_WhenUserIsNotACustomer() {
        try {
            create('Standard', 2, 1000, WEDNESDAY, '64000');
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('customer'), 'Message: ' + e.getMessage());
        }
    }

    // Covers BR-09: the customer cannot create a shipment directly, only through this controller.
    @IsTest
    static void shouldRejectDirectInsert_WhenCustomerUsesUserMode() {
        User requester = customer();
        System.runAs(requester) {
            try {
                Database.insert(new Shipment__c(Account__c = requester.Contact.AccountId, Status__c = 'Delivered', Price__c = 1), AccessLevel.USER_MODE);
                Assert.fail('Customer must not create shipments directly');
            } catch (Exception e) {
                Assert.isTrue(e.getMessage().length() > 0, 'Insert rejected: ' + e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WITH SYSTEM_MODE], 'Nothing created');
    }

    // Covers BR-09, BR-03: the customer cannot change the status of their own shipment directly.
    @IsTest
    static void shouldRejectDirectStatusChange_WhenCustomerUsesUserMode() {
        ShipmentRequestController.RequestResult result;
        System.runAs(customer()) {
            result = create('Standard', 2, 1000, WEDNESDAY, '64000');
            Shipment__c own = [SELECT Id FROM Shipment__c WHERE Name = :result.trackingNumber WITH USER_MODE];
            try {
                Database.update(new Shipment__c(Id = own.Id, Status__c = 'Delivered'), AccessLevel.USER_MODE);
                Assert.fail('Customer must not change the status');
            } catch (Exception e) {
                Assert.isTrue(e.getMessage().length() > 0, 'Update rejected: ' + e.getMessage());
            }
        }
        Assert.areEqual('Requested', [SELECT Status__c FROM Shipment__c WITH SYSTEM_MODE LIMIT 1].Status__c, 'Status unchanged');
    }
}
