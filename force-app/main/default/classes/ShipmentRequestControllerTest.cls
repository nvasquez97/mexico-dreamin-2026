/**
 * @description Proves ShipmentRequestController (odd/tasks/req-006-007-customer-shipments.md,
 *              S3) as the seeded customer Ana López (Abarrotes Acme) with the
 *              permission set RutaCargo_Customer: every AC-006.1 field is stored,
 *              a missing or too long field is refused with a generic field error
 *              and nothing is created (AC-006.1); getQuote returns the BR-08 price
 *              and submitRequest stores exactly that price (AC-006.2); weight,
 *              declared value and pickup date limits on the server (AC-006.3,
 *              AC-006.4); the confirmation (AC-006.5) and the estimate (AC-006.6);
 *              the site guest and an internal user are refused (AC-006.8). "Today"
 *              is fixed with ShipmentRequestRules.todayOverride.
 */
@IsTest
private with sharing class ShipmentRequestControllerTest {

    private static final Pattern TRACKING_FORMAT = Pattern.compile('^RC\\d{9}$');
    private static final Pattern CODE_FORMAT = Pattern.compile('^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$');
    private static final Date WEDNESDAY = Date.newInstance(2026, 11, 18);
    private static final Date THURSDAY = Date.newInstance(2026, 11, 19);

    // ─── Helpers ────────────────────────────────────────────────────────────

    private static User ana() {
        return TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
    }

    private static ShipmentRequestController.Confirmation submitAs(User actor, ShipmentRequestController.ShipmentRequest request) {
        ShipmentRequestController.Confirmation confirmation;
        System.runAs(actor) {
            confirmation = ShipmentRequestController.submitRequest(request);
        }
        return confirmation;
    }

    // Returns the refusal message of submitRequest, or fails when it succeeds.
    private static String refusalOf(User actor, ShipmentRequestController.ShipmentRequest request) {
        String message;
        System.runAs(actor) {
            try {
                ShipmentRequestController.submitRequest(request);
                Assert.fail('submitRequest must refuse this request');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        return message;
    }

    private static List<Shipment__c> storedShipments() {
        return [
            SELECT Id, Name, Account__c, Status__c, Price__c, Estimated_Delivery__c, Original_Estimated_Delivery__c,
                Pickup_Address__c, Origin_City__c, Pickup_Postal_Code__c, Pickup_Date__c, Recipient_Name__c,
                Recipient_Address__c, Destination_City__c, Destination_Postal_Code__c, Recipient_Phone__c,
                Recipient_Email__c, Service_Type__c, Weight_Kg__c, Package_Description__c, Declared_Value__c,
                Customer_Reference__c, Delivery_Instructions__c, Delivery_Access_Code_Hash__c
            FROM Shipment__c
            WITH SYSTEM_MODE
        ];
    }

    private static Shipment__c theOnlyStoredShipment() {
        List<Shipment__c> stored = storedShipments();
        Assert.areEqual(1, stored.size(), 'Exactly one shipment must be created');
        return stored[0];
    }

    // ─── AC-006.1: the entered fields ───────────────────────────────────────

    @IsTest
    static void submitRequest_storesEveryEnteredField() {
        // AC-006.1: a customer submits all AC-006.1 fields → the shipment stores each one
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        Test.startTest();
        submitAs(ana(), request);
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        String expected = String.join(new List<Object>{
            request.pickupAddress, request.pickupCity, request.pickupPostalCode, request.pickupDate,
            request.recipientName, request.recipientAddress, request.recipientCity, request.recipientPostalCode,
            request.recipientPhone, request.recipientEmail, request.serviceType, request.weightKg,
            request.packageDescription, request.declaredValue, request.customerReference, request.deliveryInstructions
        }, '|');
        String actual = String.join(new List<Object>{
            stored.Pickup_Address__c, stored.Origin_City__c, stored.Pickup_Postal_Code__c, stored.Pickup_Date__c,
            stored.Recipient_Name__c, stored.Recipient_Address__c, stored.Destination_City__c, stored.Destination_Postal_Code__c,
            stored.Recipient_Phone__c, stored.Recipient_Email__c, stored.Service_Type__c, stored.Weight_Kg__c,
            stored.Package_Description__c, stored.Declared_Value__c, stored.Customer_Reference__c, stored.Delivery_Instructions__c
        }, '|');
        Assert.areEqual(expected, actual, 'Every AC-006.1 field must be stored as entered');
    }

    @IsTest
    static void submitRequest_storesTheRecipientOwnedFieldsOfASecondRequest() {
        // AC-006.1 (BR-02, G7): the customer has no FLS on the recipient's address,
        // phone, email and instructions, yet submitRequest stores the entered ones
        // (trimmed): a second set of values
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.recipientAddress = '  Calle Morelos 12, San Pedro ';
        request.recipientPhone = '+52 81 1111 2222';
        request.recipientEmail = ' pedro.ruiz@example.com';
        request.deliveryInstructions = 'Leave at the front desk';
        Test.startTest();
        submitAs(ana(), request);
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.areEqual('Calle Morelos 12, San Pedro|+52 81 1111 2222|pedro.ruiz@example.com|Leave at the front desk',
            stored.Recipient_Address__c + '|' + stored.Recipient_Phone__c + '|' + stored.Recipient_Email__c + '|'
                + stored.Delivery_Instructions__c,
            'The recipient-owned fields of the request must be stored, trimmed');
    }

    @IsTest
    static void submitRequest_leavesNoStagedRecipientValues() {
        // AC-006.5 (BR-02, X6): after submitRequest, a direct user-mode create by
        // the same customer in the same transaction gets none of the request's
        // recipient values and is refused; only the request's shipment exists
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        User customer = ana();
        List<Shipment__c> direct = TestDataFactory.newCustomerCreateableShipments(1);
        Boolean directSaved;
        Test.startTest();
        System.runAs(customer) {
            ShipmentRequestController.submitRequest(TestDataFactory.newShipmentRequest());
            directSaved = Database.insert(direct, false, AccessLevel.USER_MODE)[0].isSuccess();
        }
        Test.stopTest();
        Assert.areEqual('false|1', directSaved + '|' + storedShipments().size(),
            'The direct create must be refused and only the requested shipment stored');
    }

    @IsTest
    static void submitRequest_acceptsARequestWithoutTheOptionalFields() {
        // AC-006.1: order reference and delivery instructions are optional
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.customerReference = null;
        request.deliveryInstructions = '  ';
        Test.startTest();
        submitAs(ana(), request);
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.areEqual('null|null', stored.Customer_Reference__c + '|' + stored.Delivery_Instructions__c,
            'Omitted optional fields must be stored blank');
    }

    @IsTest
    static void submitRequest_refusesAndCreatesNothing_whenTheRecipientEmailIsMissing() {
        // AC-006.1: a missing required field → generic field error, nothing created
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.recipientEmail = ' ';
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: recipientEmail', message, 'A missing recipient email must be a field error');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }

    @IsTest
    static void submitRequest_refusesAndCreatesNothing_whenThePickupAddressAndCityAreMissing() {
        // AC-006.1: missing required fields → one generic error naming each field, nothing created
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.pickupAddress = null;
        request.pickupCity = '';
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: pickupAddress, pickupCity', message, 'Missing pickup fields must be field errors');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }

    @IsTest
    static void submitRequest_refusesAndCreatesNothing_whenTheDescriptionExceedsItsLength() {
        // AC-006.1: Package_Description__c holds 255 characters; 256 are refused
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.packageDescription = 'x'.repeat(256);
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: packageDescription', message, 'A 256-character description must be a field error');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }

    @IsTest
    static void submitRequest_refusesAndCreatesNothing_whenTheReferenceExceedsItsLength() {
        // AC-006.1: Customer_Reference__c holds 50 characters; 51 are refused
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.customerReference = 'R'.repeat(51);
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: customerReference', message, 'A 51-character reference must be a field error');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }

    @IsTest
    static void submitRequest_refusesAndCreatesNothing_whenTheRecipientEmailIsNotAnEmail() {
        // AC-006.1: the recipient email must be an email address
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.recipientEmail = 'laura.gomez at example';
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: recipientEmail', message, 'An invalid email must be a field error');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }

    // ─── AC-006.2 (BR-08): quote and stored price ───────────────────────────

    @IsTest
    static void getQuote_returnsTheStandardPriceAndThePickupWindow() {
        // AC-006.2: Standard 2.5 kg, declared 1,000.00 → 180.00; T = Thursday
        // 2026-11-19 → pickup window 2026-11-20 to 2026-12-04
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.Quote quote;
        Test.startTest();
        System.runAs(ana()) {
            quote = ShipmentRequestController.getQuote('Standard', 2.5, 1000);
        }
        Test.stopTest();
        Assert.areEqual(180.00, quote.price, 'Standard 2.5 kg declared 1,000.00 must be quoted 180.00');
        Assert.areEqual(new List<Date>{ Date.newInstance(2026, 11, 20), Date.newInstance(2026, 12, 4) },
            new List<Date>{ quote.earliestPickupDate, quote.latestPickupDate }, 'The pickup window must be T+1 to T+15');
    }

    @IsTest
    static void getQuote_returnsTheExpressPriceAtTheLimits() {
        // AC-006.2 / AC-006.4: Express 30 kg, declared 50,000.00 → 1,870.00
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.Quote quote;
        Test.startTest();
        System.runAs(ana()) {
            quote = ShipmentRequestController.getQuote('Express', 30.00, 50000.00);
        }
        Test.stopTest();
        Assert.areEqual(1870.00, quote.price, 'Express 30 kg declared 50,000.00 must be quoted 1,870.00');
    }

    @IsTest
    static void getQuote_refuses_whenTheWeightHasThreeDecimals() {
        // AC-006.2 (G6): 1.333 kg is rejected
        String message;
        Test.startTest();
        System.runAs(ana()) {
            try {
                ShipmentRequestController.getQuote('Standard', 1.333, 1000);
                Assert.fail('A weight of 1.333 kg must be refused');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        Test.stopTest();
        Assert.areEqual('Check these fields: weightKg', message, 'A 3-decimal weight must be a field error');
    }

    @IsTest
    static void submitRequest_storesExactlyTheQuotedPrice_roundedHalfUp() {
        // AC-006.2: Standard 1.25 kg, declared 333.33 → quote 147.50; the stored price is the quote
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.weightKg = 1.25;
        request.declaredValue = 333.33;
        ShipmentRequestController.Quote quote;
        Test.startTest();
        System.runAs(ana()) {
            quote = ShipmentRequestController.getQuote(request.serviceType, request.weightKg, request.declaredValue);
            ShipmentRequestController.submitRequest(request);
        }
        Test.stopTest();
        Assert.areEqual(147.50, quote.price, 'The quote must be 147.50');
        Assert.areEqual(quote.price, theOnlyStoredShipment().Price__c, 'The stored price must be exactly the quoted price');
    }

    @IsTest
    static void submitRequest_storesExactlyTheQuotedPrice_forExpress() {
        // AC-006.2: Express 2.5 kg, declared 1,000.00 → quote 310.00; the stored price is the quote
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.serviceType = 'Express';
        ShipmentRequestController.Quote quote;
        Test.startTest();
        System.runAs(ana()) {
            quote = ShipmentRequestController.getQuote(request.serviceType, request.weightKg, request.declaredValue);
            ShipmentRequestController.submitRequest(request);
        }
        Test.stopTest();
        Assert.areEqual(310.00, quote.price, 'The quote must be 310.00');
        Assert.areEqual(quote.price, theOnlyStoredShipment().Price__c, 'The stored price must be exactly the quoted price');
    }

    // ─── AC-006.3, AC-006.4: limits on the server ───────────────────────────

    @IsTest
    static void submitRequest_acceptsThirtyKilogramsAndFiftyThousandDeclared() {
        // AC-006.4: weight 30.00 and declared 50,000.00 are accepted
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.weightKg = 30.00;
        request.declaredValue = 50000.00;
        Test.startTest();
        submitAs(ana(), request);
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.areEqual('30.00|50000.00', stored.Weight_Kg__c + '|' + stored.Declared_Value__c, 'The limits must be stored');
    }

    @IsTest
    static void submitRequest_refuses_whenTheWeightIsAboveThirtyKilograms() {
        // AC-006.4: 30.01 kg is rejected on the server
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.weightKg = 30.01;
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: weightKg', message, '30.01 kg must be a field error');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }

    @IsTest
    static void submitRequest_refuses_whenTheWeightIsZero() {
        // AC-006.4: a weight of 0 is rejected on the server
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.weightKg = 0;
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: weightKg', message, '0 kg must be a field error');
    }

    @IsTest
    static void submitRequest_refuses_whenTheDeclaredValueIsAboveTheMaximum() {
        // AC-006.4: 50,000.01 declared is rejected on the server
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.declaredValue = 50000.01;
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: declaredValue', message, '50,000.01 must be a field error');
    }

    @IsTest
    static void submitRequest_refuses_whenTheDeclaredValueIsNegative() {
        // AC-006.4: a negative declared value is rejected on the server
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.declaredValue = -1;
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: declaredValue', message, 'A negative declared value must be a field error');
    }

    @IsTest
    static void submitRequest_refuses_whenThePickupDateIsASaturday() {
        // AC-006.3: T = Thursday 2026-11-19; Saturday 2026-11-21 is rejected on the server
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.pickupDate = Date.newInstance(2026, 11, 21);
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: pickupDate', message, 'A Saturday pickup must be a field error');
    }

    @IsTest
    static void submitRequest_refuses_whenTheServiceTypeIsUnknown() {
        // AC-006.1: the service type is Standard or Express
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.serviceType = 'Overnight';
        Test.startTest();
        String message = refusalOf(ana(), request);
        Test.stopTest();
        Assert.areEqual('Check these fields: serviceType', message, 'An unknown service type must be a field error');
    }

    // ─── AC-006.5 (BR-07, BR-09, A1): the confirmation ──────────────────────

    @IsTest
    static void submitRequest_createsTheShipmentUnderTheCustomersAccountAsRequested() {
        // AC-006.5: one Shipment__c with Account__c = Ana's account, Status Requested, Name RC + 9 digits
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        Test.startTest();
        submitAs(ana(), TestDataFactory.newShipmentRequest());
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.areEqual(TestDataFactory.seededCustomerAccountId(TestDataFactory.SEEDED_CUSTOMER_EMAIL), stored.Account__c,
            'The shipment must belong to the customer\'s account');
        Assert.areEqual('Requested', stored.Status__c, 'A new shipment must be Requested');
        Assert.isTrue(TRACKING_FORMAT.matcher(stored.Name).matches(), 'The tracking number must be RC + 9 digits: ' + stored.Name);
    }

    @IsTest
    static void submitRequest_returnsTheTrackingNumberPriceAndEstimate() {
        // AC-006.5: the response shows the stored tracking number, price and estimate
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.Confirmation confirmation;
        Test.startTest();
        confirmation = submitAs(ana(), TestDataFactory.newShipmentRequest());
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.areEqual(stored.Name + '|180.00|2026-11-27',
            confirmation.trackingNumber + '|' + confirmation.price + '|' + String.valueOf(confirmation.estimatedDelivery),
            'The confirmation must show the stored tracking number, 180.00 and Friday 2026-11-27');
        Assert.areEqual(stored.Price__c + '|' + stored.Estimated_Delivery__c,
            confirmation.price + '|' + confirmation.estimatedDelivery, 'The confirmation must match the stored values');
    }

    @IsTest
    static void submitRequest_returnsAWorkingAccessCodeThatIsNotStoredInClear() {
        // AC-006.5 (A1): the 12-character access code is shown once and only its hash is stored
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.Confirmation confirmation;
        Test.startTest();
        confirmation = submitAs(ana(), TestDataFactory.newShipmentRequest());
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.isTrue(CODE_FORMAT.matcher(confirmation.accessCode).matches(), 'The access code must have 12 characters of the alphabet');
        Assert.isTrue(DeliveryAccessCode.verify(stored.Id, confirmation.accessCode), 'The returned code must open the shipment');
        Assert.isFalse(JSON.serialize(stored).contains(confirmation.accessCode), 'The clear code must not be stored in any field');
    }

    // ─── AC-006.6 (BR-06): the estimate ─────────────────────────────────────

    @IsTest
    static void submitRequest_estimatesTheFollowingThursday_forStandardFromAThursday() {
        // AC-006.6: T = Wednesday 2026-11-18; pickup Thursday 2026-11-19, Standard →
        // estimate Thursday 2026-11-26, and Original_Estimated_Delivery__c equals it
        ShipmentRequestRules.todayOverride = WEDNESDAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.pickupDate = THURSDAY;
        Test.startTest();
        submitAs(ana(), request);
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.areEqual(Date.newInstance(2026, 11, 26), stored.Estimated_Delivery__c, 'Standard from Thursday must arrive the next Thursday');
        Assert.areEqual(stored.Estimated_Delivery__c, stored.Original_Estimated_Delivery__c, 'The original estimate must be the first estimate');
    }

    @IsTest
    static void submitRequest_estimatesTheTuesday_forExpressFromAFriday() {
        // AC-006.6: pickup Friday 2026-11-20, Express → estimate Tuesday 2026-11-24
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        ShipmentRequestController.ShipmentRequest request = TestDataFactory.newShipmentRequest();
        request.serviceType = 'Express';
        Test.startTest();
        submitAs(ana(), request);
        Test.stopTest();
        Shipment__c stored = theOnlyStoredShipment();
        Assert.areEqual(Date.newInstance(2026, 11, 24), stored.Estimated_Delivery__c, 'Express from Friday must arrive on Tuesday');
        Assert.areEqual(stored.Estimated_Delivery__c, stored.Original_Estimated_Delivery__c, 'The original estimate must be the first estimate');
    }

    // ─── AC-006.8: only customers ───────────────────────────────────────────

    @IsTest
    static void submitRequest_refusesTheSiteGuestAndCreatesNothing() {
        // AC-006.8: the real site guest user is refused with a generic error
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        Test.startTest();
        String message = refusalOf(TestDataFactory.siteGuestUser(), TestDataFactory.newShipmentRequest());
        Test.stopTest();
        Assert.areEqual(ShipmentRequestController.NOT_AVAILABLE_MESSAGE, message, 'The guest must get the generic refusal');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }

    @IsTest
    static void getQuote_refusesTheSiteGuest() {
        // AC-006.8: the guest cannot use the customer request service at all
        String message;
        Test.startTest();
        System.runAs(TestDataFactory.siteGuestUser()) {
            try {
                ShipmentRequestController.getQuote('Standard', 2.5, 1000);
                Assert.fail('The guest must be refused');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        Test.stopTest();
        Assert.areEqual(ShipmentRequestController.NOT_AVAILABLE_MESSAGE, message, 'The guest must get the generic refusal');
    }

    @IsTest
    static void submitRequest_refusesAnInternalUserWithoutACustomerAccount() {
        // AC-006.5 (BR-07): only a user with a customer account requests through the site
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        Test.startTest();
        String message = refusalOf(new User(Id = UserInfo.getUserId()), TestDataFactory.newShipmentRequest());
        Test.stopTest();
        Assert.areEqual(ShipmentRequestController.NOT_AVAILABLE_MESSAGE, message, 'An internal user must get the generic refusal');
        Assert.areEqual(0, storedShipments().size(), 'Nothing must be created');
    }
}
