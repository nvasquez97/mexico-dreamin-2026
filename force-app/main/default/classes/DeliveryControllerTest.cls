/**
 * Tests for the delivery details of DeliveryController, run as the real site guest.
 * Covers AC-002.1, AC-002.2, AC-002.3 and BR-02 (recipient-only data, brute-force throttle).
 */
@IsTest
private class DeliveryControllerTest {
    private static final String RIGHT_POSTAL_CODE = '64000';

    @TestSetup
    static void setup() {
        Account acme = TestDataFactory.buildCustomerAccount('Acme Test');
        Database.insert(acme, AccessLevel.SYSTEM_MODE);
        Database.insert(TestDataFactory.buildShipment(acme.Id, 'In transit'), AccessLevel.SYSTEM_MODE);
    }

    private static Shipment__c loadShipment() {
        return [
            SELECT Id, Name, Failed_Verification_Attempts__c, Verification_Locked_Until__c
            FROM Shipment__c WITH SYSTEM_MODE LIMIT 1
        ];
    }

    private static DeliveryController.DeliveryResponse openAsGuest(String trackingNumber, String postalCode) {
        DeliveryController.DeliveryResponse response;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            response = DeliveryController.getDeliveryDetails(trackingNumber, postalCode);
        }
        return response;
    }

    // Covers AC-002.1, AC-002.2: the right postal code opens recipient name, address, phone, date and instructions.
    @IsTest
    static void shouldReturnDeliveryDetails_WhenPostalCodeMatches() {
        Shipment__c shipment = loadShipment();
        Test.startTest();
        DeliveryController.DeliveryResponse response = openAsGuest(shipment.Name, RIGHT_POSTAL_CODE);
        Test.stopTest();
        Assert.isTrue(response.success, 'Access granted');
        Assert.areEqual(shipment.Name, response.details.trackingNumber, 'Tracking number');
        Assert.areEqual('Laura Garza', response.details.recipientName, 'Recipient name');
        Assert.areEqual('Calle Hidalgo 200, Centro', response.details.recipientAddress, 'Delivery address');
        Assert.areEqual('+52 81 5555 0101', response.details.recipientPhone, 'Contact phone');
        Assert.areEqual(Date.newInstance(2026, 11, 23), response.details.estimatedDelivery, 'Estimated date');
        Assert.areEqual('Ring twice', response.details.deliveryInstructions, 'Instructions');
    }

    // Covers AC-002.1, AC-001.5: spaces around the postal code and lower-case tracking number are accepted.
    @IsTest
    static void shouldGrantAccess_WhenInputHasSpacesAndLowerCase() {
        Shipment__c shipment = loadShipment();
        DeliveryController.DeliveryResponse response = openAsGuest(' ' + shipment.Name.toLowerCase() + ' ', ' 64000 ');
        Assert.isTrue(response.success, 'Access granted');
    }

    // Covers AC-002.3: a wrong postal code shows the exact message and no details.
    @IsTest
    static void shouldShowMismatchMessage_WhenPostalCodeIsWrong() {
        Shipment__c shipment = loadShipment();
        DeliveryController.DeliveryResponse response = openAsGuest(shipment.Name, '01000');
        Assert.isFalse(response.success, 'Access denied');
        Assert.areEqual('The details do not match this shipment', response.message, 'Exact message');
        Assert.isNull(response.details, 'No details on mismatch');
    }

    // Covers AC-002.3, BR-02: an unknown tracking number gets the same message (no enumeration).
    @IsTest
    static void shouldShowSameMessage_WhenTrackingNumberUnknown() {
        DeliveryController.DeliveryResponse response = openAsGuest('RC999999999', RIGHT_POSTAL_CODE);
        Assert.isFalse(response.success, 'Access denied');
        Assert.areEqual('The details do not match this shipment', response.message, 'Same message');
    }

    // Covers BR-02, BR-03: the response never carries price, internal or customer data.
    @IsTest
    static void shouldNotExposePriceOrInternalData_WhenAccessGranted() {
        DeliveryController.DeliveryResponse response = openAsGuest(loadShipment().Name, RIGHT_POSTAL_CODE);
        Assert.isTrue(response.success, 'Access granted');
        String json = JSON.serialize(response);
        for (String secret : new List<String>{ '171', 'VIP', 'Acme', 'laura.garza@example.com', 'Books' }) {
            Assert.isFalse(json.contains(secret), 'Response must not contain ' + secret + ': ' + json);
        }
    }

    // Covers BR-02: each wrong postal code is counted on the shipment.
    @IsTest
    static void shouldCountFailedAttempt_WhenPostalCodeIsWrong() {
        Shipment__c shipment = loadShipment();
        openAsGuest(shipment.Name, '01000');
        Assert.areEqual(1, loadShipment().Failed_Verification_Attempts__c, 'One failed attempt recorded');
    }

    // Covers BR-02: after 5 wrong postal codes the shipment is locked, even for the right code.
    @IsTest
    static void shouldLockDetails_WhenFiveWrongAttempts() {
        Shipment__c shipment = loadShipment();
        for (Integer i = 0; i < 5; i++) {
            openAsGuest(shipment.Name, '0100' + i);
        }
        Assert.isNotNull(loadShipment().Verification_Locked_Until__c, 'Lock recorded');
        DeliveryController.DeliveryResponse response = openAsGuest(shipment.Name, RIGHT_POSTAL_CODE);
        Assert.isFalse(response.success, 'Locked even with the right code');
        Assert.isTrue(response.message.contains('Too many attempts'), 'Lock message: ' + response.message);
        Assert.isNull(response.details, 'No details while locked');
    }

    // Covers BR-02: once the 15-minute lock has passed, the right code works again.
    @IsTest
    static void shouldUnlock_WhenLockExpired() {
        Shipment__c shipment = loadShipment();
        shipment.Failed_Verification_Attempts__c = 0;
        shipment.Verification_Locked_Until__c = Datetime.now().addMinutes(-1);
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        DeliveryController.DeliveryResponse response = openAsGuest(shipment.Name, RIGHT_POSTAL_CODE);
        Assert.isTrue(response.success, 'Access granted after the lock expired');
    }

    // Covers BR-02: a successful verification clears earlier failed attempts.
    @IsTest
    static void shouldResetCounter_WhenPostalCodeMatches() {
        Shipment__c shipment = loadShipment();
        shipment.Failed_Verification_Attempts__c = 3;
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        openAsGuest(shipment.Name, RIGHT_POSTAL_CODE);
        Assert.areEqual(0, loadShipment().Failed_Verification_Attempts__c, 'Counter reset');
    }

    // Covers AC-002.3: blank inputs are rejected with the mismatch message.
    @IsTest
    static void shouldDeny_WhenInputsBlank() {
        DeliveryController.DeliveryResponse response = openAsGuest('', '');
        Assert.isFalse(response.success, 'Access denied');
        Assert.areEqual('The details do not match this shipment', response.message, 'Same message');
    }

    // Covers BR-02 (malicious input): SOQL-like text in the postal code does not grant access.
    @IsTest
    static void shouldDeny_WhenPostalCodeLooksLikeInjection() {
        DeliveryController.DeliveryResponse response = openAsGuest(loadShipment().Name, '\' OR Name != \'');
        Assert.isFalse(response.success, 'Access denied');
        Assert.isNull(response.details, 'No details');
    }

    // Covers BR-02 (security review M-1): 10 wrong codes in total lock the details for 24 hours.
    @IsTest
    static void shouldLockForADay_WhenTenWrongAttemptsInTotal() {
        Shipment__c shipment = loadShipment();
        shipment.Failed_Verification_Attempts__c = 9;
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        openAsGuest(shipment.Name, '01000');
        Datetime lockedUntil = loadShipment().Verification_Locked_Until__c;
        Assert.isNotNull(lockedUntil, 'Locked');
        Assert.isTrue(lockedUntil > Datetime.now().addHours(23), 'Locked for about 24 hours: ' + lockedUntil);
    }

    // Covers BR-02 (security review M-1): the failure count is kept across a 15-minute lock, so guesses escalate.
    @IsTest
    static void shouldKeepCountingAfterShortLock_WhenWrongAgain() {
        Shipment__c shipment = loadShipment();
        shipment.Failed_Verification_Attempts__c = 5;
        shipment.Verification_Locked_Until__c = Datetime.now().addMinutes(-1);
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        openAsGuest(shipment.Name, '01000');
        Assert.areEqual(6, loadShipment().Failed_Verification_Attempts__c, 'Count continues after the short lock');
    }
}
