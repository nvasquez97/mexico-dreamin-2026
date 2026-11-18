/**
 * @description Proves MyShipmentsController (odd/tasks/req-006-007-customer-shipments.md,
 *              S4) as the seeded customers Ana López (A, Abarrotes Acme) and Marta
 *              Ruiz (B, Globex Farma): the list returns only the customer's own
 *              shipments, newest first, with exactly the seven AC-007.1 fields and
 *              at most 200 rows (AC-007.1); the status filter and the literal,
 *              bound search (AC-007.2); the detail without the recipient's contact
 *              data or any internal field, and the same "not found" for another
 *              customer's or an unknown tracking number (AC-007.3); the site guest
 *              (AC-006.8) and a signed-in user without a customer account (BR-07)
 *              are refused.
 */
@IsTest
private with sharing class MyShipmentsControllerTest {

    private static final String IN_TRANSIT = 'In transit';
    private static final String ANA_REQUESTED = 'Lucía Fernández';
    private static final String ANA_IN_TRANSIT = 'Carlos Pérez';
    private static final String ANA_NEWEST = 'Diana O\'Neil';
    private static final String MARTA_IN_TRANSIT = 'Carlos Méndez';
    private static final String MARTA_REQUESTED = 'Pedro Ruiz';
    private static final String WILDCARD_REFERENCE = 'PO-100%_X';
    private static final String MARTA_BULK = 'Marta Bulk Recipient';
    private static final Integer MAX_ROWS = 200;
    private static final Integer BULK_SIZE = 251;
    private static final Set<String> LIST_FIELDS = new Set<String>{
        'trackingNumber', 'requestDate', 'recipientName', 'destinationCity', 'status', 'serviceType', 'price'
    };
    private static final Set<String> DETAIL_FIELDS = new Set<String>{
        'trackingNumber', 'requestDate', 'status', 'serviceType', 'price', 'estimatedDelivery', 'lastUpdate',
        'lastLocation', 'pickupAddress', 'pickupCity', 'pickupPostalCode', 'pickupDate', 'recipientName',
        'destinationCity', 'destinationPostalCode', 'weightKg', 'packageDescription', 'declaredValue', 'customerReference'
    };

    @TestSetup
    static void setupShipments() {
        Id anaAccount = TestDataFactory.seededCustomerAccountId(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Id martaAccount = TestDataFactory.seededCustomerAccountId(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> shipments = new List<Shipment__c>{
            shipment(anaAccount, ANA_REQUESTED, WILDCARD_REFERENCE, 'Guadalajara'),
            shipment(anaAccount, ANA_IN_TRANSIT, 'ORD-7', 'Monterrey'),
            shipment(anaAccount, ANA_NEWEST, 'ABC-3', 'Puebla'),
            shipment(martaAccount, MARTA_IN_TRANSIT, 'ORD-7', 'Merida'),
            shipment(martaAccount, MARTA_REQUESTED, WILDCARD_REFERENCE, 'Leon')
        };
        // AC-007.3: Marta's shipment carries pickup and package values other than
        // the factory's, so the detail check has two different inputs.
        Shipment__c martas = shipments[3];
        martas.Pickup_Address__c = 'Calle 60 No. 500, Centro';
        martas.Origin_City__c = 'Cancun';
        martas.Pickup_Postal_Code__c = '77500';
        martas.Pickup_Date__c = Date.newInstance(2026, 12, 2);
        martas.Destination_Postal_Code__c = '97000';
        martas.Package_Description__c = 'Lab samples';
        martas.Weight_Kg__c = 4.25;
        martas.Declared_Value__c = 2500.00;
        martas.Price__c = 230.00;
        martas.Estimated_Delivery__c = Date.newInstance(2026, 12, 9);
        TestDataFactory.insertShipmentsWithCodes(shipments);
        // The trigger forces Requested on insert; the carrier moves two of each later.
        shipments[1].Status__c = IN_TRANSIT;
        shipments[2].Status__c = IN_TRANSIT;
        shipments[2].Last_Update__c = Datetime.newInstanceGmt(2026, 11, 16, 1, 5, 0);
        shipments[2].Last_Location__c = 'Puebla hub';
        shipments[3].Status__c = IN_TRANSIT;
        shipments[3].Last_Update__c = Datetime.newInstanceGmt(2026, 11, 17, 20, 45, 0);
        shipments[3].Last_Location__c = 'Merida hub';
        TestDataFactory.updateAsSystem(shipments);
        List<Datetime> created = new List<Datetime>{
            Datetime.newInstanceGmt(2026, 11, 10, 15, 0, 0),
            Datetime.newInstanceGmt(2026, 11, 12, 15, 0, 0),
            Datetime.newInstanceGmt(2026, 11, 15, 18, 30, 0),
            Datetime.newInstanceGmt(2026, 11, 16, 15, 0, 0),
            Datetime.newInstanceGmt(2026, 11, 17, 15, 0, 0)
        };
        for (Integer i = 0; i < shipments.size(); i++) {
            Test.setCreatedDate(shipments[i].Id, created[i]);
        }
    }

    private static Shipment__c shipment(Id accountId, String recipient, String reference, String city) {
        Shipment__c shipment = TestDataFactory.newShipment(accountId);
        shipment.Recipient_Name__c = recipient;
        shipment.Customer_Reference__c = reference;
        shipment.Destination_City__c = city;
        shipment.Declared_Value__c = 1000.00;
        shipment.Price__c = 165.00;
        shipment.Estimated_Delivery__c = Date.newInstance(2026, 12, 8);
        shipment.Carrier_Cost__c = 90.00;
        shipment.Internal_Notes__c = 'internal only';
        return shipment;
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    private static User ana() {
        return TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
    }

    private static User marta() {
        return TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
    }

    private static String trackingOf(String recipient) {
        // SECURITY-JUSTIFICATION: test setup read as the test's administrator,
        // outside System.runAs, to learn the tracking numbers the trigger gave
        // the fixture shipments. Scope: this test class only; compensating
        // control: every call under test runs inside System.runAs as a customer,
        // in user mode. (pending owner approval, 2026-11-18)
        return [SELECT Name FROM Shipment__c WHERE Recipient_Name__c = :recipient WITH SYSTEM_MODE LIMIT 1].Name;
    }

    private static List<String> trackingNumbersOf(List<String> recipients) {
        List<String> trackingNumbers = new List<String>();
        for (String recipient : recipients) {
            trackingNumbers.add(trackingOf(recipient));
        }
        return trackingNumbers;
    }

    private static List<MyShipmentsController.ShipmentRow> listAs(User actor, String status, String searchTerm) {
        List<MyShipmentsController.ShipmentRow> rows;
        System.runAs(actor) {
            rows = MyShipmentsController.listShipments(status, searchTerm);
        }
        return rows;
    }

    private static List<String> trackingNumbersIn(List<MyShipmentsController.ShipmentRow> rows) {
        List<String> trackingNumbers = new List<String>();
        for (MyShipmentsController.ShipmentRow row : rows) {
            trackingNumbers.add(row.trackingNumber);
        }
        return trackingNumbers;
    }

    private static String listRefusalAs(User actor, String status, String searchTerm) {
        String message;
        System.runAs(actor) {
            try {
                MyShipmentsController.listShipments(status, searchTerm);
                Assert.fail('listShipments must refuse this call');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        return message;
    }

    private static String detailRefusalAs(User actor, String trackingNumber) {
        String message;
        System.runAs(actor) {
            try {
                MyShipmentsController.getShipment(trackingNumber);
                Assert.fail('getShipment must refuse this call');
            } catch (AuraHandledException e) {
                message = e.getMessage();
            }
        }
        return message;
    }

    private static Set<String> keysOf(Object dto) {
        return ((Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(dto))).keySet();
    }

    // ─── AC-007.1 (BR-03, BR-07): the list ──────────────────────────────────

    @IsTest
    static void listShipments_returnsOnlyAnasShipments_newestFirst() {
        // AC-007.1: A gets only A's shipments, most recent CreatedDate first, none of B's
        List<String> expected = trackingNumbersOf(new List<String>{ ANA_NEWEST, ANA_IN_TRANSIT, ANA_REQUESTED });
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, null);
        Test.stopTest();
        Assert.areEqual(expected, trackingNumbersIn(rows), 'Ana must get exactly her 3 shipments, newest first');
    }

    @IsTest
    static void listShipments_returnsOnlyMartasShipments_newestFirst() {
        // AC-007.1: B gets only B's shipments, most recent first, none of A's
        List<String> expected = trackingNumbersOf(new List<String>{ MARTA_REQUESTED, MARTA_IN_TRANSIT });
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(marta(), '', ' ');
        Test.stopTest();
        Assert.areEqual(expected, trackingNumbersIn(rows), 'Marta must get exactly her 2 shipments, newest first');
    }

    @IsTest
    static void listShipments_returnsExactlyTheSevenListFields() {
        // AC-007.1 (BR-03, BR-06): each row has exactly the seven list fields; the
        // request date is Mexico City time (2026-11-15 18:30 GMT → 12:30)
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, null);
        Test.stopTest();
        MyShipmentsController.ShipmentRow newest = rows[0];
        Assert.areEqual(LIST_FIELDS, keysOf(newest), 'A row must have exactly the seven AC-007.1 fields');
        Assert.areEqual(
            trackingOf(ANA_NEWEST) + '|2026-11-15 12:30|' + ANA_NEWEST + '|Puebla|In transit|Standard|165.00',
            String.join(new List<Object>{ newest.trackingNumber, newest.requestDate, newest.recipientName,
                newest.destinationCity, newest.status, newest.serviceType, newest.price }, '|'),
            'The row must carry the newest shipment\'s values');
    }

    // The tracking numbers of an account's shipments in the list's order (newest first), at most maxRows.
    private static List<String> newestTrackingNumbersOf(Id accountId, Integer maxRows) {
        List<String> trackingNumbers = new List<String>();
        for (Shipment__c own : [
            SELECT Name FROM Shipment__c WHERE Account__c = :accountId
            // SECURITY-JUSTIFICATION: the expected rows, read as the test's
            // administrator outside System.runAs (the customer cannot filter on
            // Account__c). Scope: this test class only; compensating control: the
            // call under test runs as the customer in user mode. (pending owner approval, 2026-11-18)
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Name DESC LIMIT :maxRows
        ]) {
            trackingNumbers.add(own.Name);
        }
        return trackingNumbers;
    }

    @IsTest
    static void listShipments_returnsAtMost200Shipments() {
        // AC-007.1 (G3): 251 more shipments for Ana → the list returns 200
        TestDataFactory.insertShipmentsWithCodes(TestDataFactory.newShipments(
            TestDataFactory.seededCustomerAccountId(TestDataFactory.SEEDED_CUSTOMER_EMAIL), BULK_SIZE));
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, null);
        Test.stopTest();
        Assert.areEqual(MAX_ROWS, rows.size(), 'The list must stop at 200 shipments');
    }

    @IsTest
    static void listShipments_returnsAnasNewest200_andNoneOfMartas() {
        // AC-007.1 (G3, BR-07): with 251 more shipments for Ana and 251 more for
        // Marta (recipient MARTA_BULK), Ana's list is exactly her 200 newest, in
        // order, and no row is one of Marta's. Marta's rows are told apart by
        // their recipient: inside a test method the Name auto-number restarts
        // below the @TestSetup rows, so a tracking number can repeat.
        Id anaAccount = TestDataFactory.seededCustomerAccountId(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Id martaAccount = TestDataFactory.seededCustomerAccountId(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> more = TestDataFactory.newShipments(anaAccount, BULK_SIZE);
        List<Shipment__c> martas = TestDataFactory.newShipments(martaAccount, BULK_SIZE);
        for (Shipment__c shipment : martas) {
            shipment.Recipient_Name__c = MARTA_BULK;
        }
        more.addAll(martas);
        TestDataFactory.insertShipmentsWithCodes(more);
        List<String> expected = newestTrackingNumbersOf(anaAccount, MAX_ROWS);
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, null);
        Test.stopTest();
        Set<String> recipients = new Set<String>();
        for (MyShipmentsController.ShipmentRow row : rows) {
            recipients.add(row.recipientName);
        }
        Assert.isFalse(recipients.contains(MARTA_BULK), 'None of Marta\'s shipments may be in Ana\'s list');
        Assert.areEqual(expected, trackingNumbersIn(rows), 'Ana must get exactly her 200 newest shipments, newest first');
    }

    // ─── AC-007.2 (P6, P8): filter and search ───────────────────────────────

    @IsTest
    static void listShipments_filtersByStatus() {
        // AC-007.2: status "In transit" → only Ana's In transit shipments
        List<String> expected = trackingNumbersOf(new List<String>{ ANA_NEWEST, ANA_IN_TRANSIT });
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), IN_TRANSIT, null);
        Test.stopTest();
        Assert.areEqual(expected, trackingNumbersIn(rows), 'Only Ana\'s 2 In transit shipments must return');
    }

    @IsTest
    static void listShipments_filtersByTheRequestedStatus() {
        // AC-007.2: status "Requested" → only Ana's Requested shipment (not Marta's)
        List<String> expected = trackingNumbersOf(new List<String>{ ANA_REQUESTED });
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), 'Requested', null);
        Test.stopTest();
        Assert.areEqual(expected, trackingNumbersIn(rows), 'Only Ana\'s Requested shipment must return');
    }

    @IsTest
    static void listShipments_findsATrackingNumber() {
        // AC-007.2: search by a full tracking number
        String tracking = trackingOf(ANA_IN_TRANSIT);
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, tracking);
        Test.stopTest();
        Assert.areEqual(new List<String>{ tracking }, trackingNumbersIn(rows), 'The tracking number must find its shipment');
    }

    @IsTest
    static void listShipments_findsByTrackingPrefix() {
        // AC-007.2: a tracking-number prefix finds every own shipment that starts with it
        String prefix = trackingOf(ANA_REQUESTED).left(10);
        Id anaAccount = TestDataFactory.seededCustomerAccountId(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        String pattern = prefix + '%';
        List<String> expected = new List<String>();
        for (Shipment__c own : [
            SELECT Name FROM Shipment__c WHERE Account__c = :anaAccount AND Name LIKE :pattern
            // SECURITY-JUSTIFICATION: the expected rows, read as the test's
            // administrator outside System.runAs (the customer cannot filter on
            // Account__c). Scope: this test only; compensating control: the call
            // under test runs as Ana in user mode. (pending owner approval, 2026-11-18)
            WITH SYSTEM_MODE ORDER BY CreatedDate DESC, Name DESC
        ]) {
            expected.add(own.Name);
        }
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, prefix);
        Test.stopTest();
        Assert.isFalse(expected.isEmpty(), 'Setup must give the prefix at least one shipment');
        Assert.areEqual(expected, trackingNumbersIn(rows), 'The prefix ' + prefix + ' must find Ana\'s matching shipments');
    }

    @IsTest
    static void listShipments_findsARecipientFragmentInAnyCase() {
        // AC-007.2: "cARLOS" finds Ana's Carlos Pérez and not Marta's Carlos Méndez
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, 'cARLOS');
        Test.stopTest();
        Assert.areEqual(trackingNumbersOf(new List<String>{ ANA_IN_TRANSIT }), trackingNumbersIn(rows),
            'The recipient fragment must find only Ana\'s Carlos');
    }

    @IsTest
    static void listShipments_findsAReference() {
        // AC-007.2: the reference "ord-7" finds Ana's ORD-7 shipment and not Marta's
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, 'ord-7');
        Test.stopTest();
        Assert.areEqual(trackingNumbersOf(new List<String>{ ANA_IN_TRANSIT }), trackingNumbersIn(rows),
            'The reference must find only Ana\'s ORD-7 shipment');
    }

    @IsTest
    static void listShipments_combinesTheStatusFilterAndTheSearch() {
        // AC-007.2: status "In transit" and search "o'neil" → Ana's newest shipment
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), IN_TRANSIT, 'o\'neil');
        Test.stopTest();
        Assert.areEqual(trackingNumbersOf(new List<String>{ ANA_NEWEST }), trackingNumbersIn(rows),
            'Filter and search must both apply');
    }

    @IsTest
    static void listShipments_refusesAStatusOutsideThePicklist() {
        // AC-007.2: a status outside the picklist → a generic error
        Test.startTest();
        String message = listRefusalAs(ana(), 'Lost\' OR Name != \'', null);
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.INVALID_FILTER_MESSAGE, message, 'An unknown status must get the generic error');
    }

    @IsTest
    static void listShipments_refusesASearchLongerThan50Characters() {
        // AC-007.2 (P6): the search term has at most 50 characters
        Test.startTest();
        String message = listRefusalAs(ana(), null, 'a'.repeat(51));
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.INVALID_FILTER_MESSAGE, message, 'A 51-character search must get the generic error');
    }

    @IsTest
    static void listShipments_matchesAPercentSignLiterally() {
        // AC-007.2 (P8): "%" is not a wildcard: only the reference PO-100%_X matches
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, '%');
        Test.stopTest();
        Assert.areEqual(trackingNumbersOf(new List<String>{ ANA_REQUESTED }), trackingNumbersIn(rows),
            '"%" must match only the shipment whose reference contains a percent sign');
    }

    @IsTest
    static void listShipments_matchesAnUnderscoreLiterally() {
        // AC-007.2 (P8): "_" is not a wildcard: only the reference PO-100%_X matches
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, '_');
        Test.stopTest();
        Assert.areEqual(trackingNumbersOf(new List<String>{ ANA_REQUESTED }), trackingNumbersIn(rows),
            '"_" must match only the shipment whose reference contains an underscore');
    }

    @IsTest
    static void listShipments_matchesAQuoteLiterally() {
        // AC-007.2 (P8): "'" is bound, not injected: only O'Neil matches, no error
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs(ana(), null, '\'');
        Test.stopTest();
        Assert.areEqual(trackingNumbersOf(new List<String>{ ANA_NEWEST }), trackingNumbersIn(rows),
            'A quote must match only the recipient O\'Neil');
    }

    // ─── AC-007.3 (BR-02, BR-03, BR-07): the detail ─────────────────────────

    @IsTest
    static void getShipment_returnsTheDetailFieldsOnly() {
        // AC-007.3 (G7): the detail has the entered fields except the recipient's
        // address, phone, email and instructions, plus price, status, estimate and
        // last update; no cost, margin, notes, hash, proof, account or record Id
        String tracking = trackingOf(ANA_NEWEST);
        MyShipmentsController.ShipmentDetail detail;
        Test.startTest();
        System.runAs(ana()) {
            detail = MyShipmentsController.getShipment(tracking);
        }
        Test.stopTest();
        Assert.areEqual(DETAIL_FIELDS, keysOf(detail), 'The detail must have exactly the AC-007.3 fields');
    }

    // The 19 values of the detail, in the order of DETAIL_FIELDS.
    private static String detailValues(MyShipmentsController.ShipmentDetail detail) {
        return String.join(new List<Object>{ detail.trackingNumber, detail.requestDate, detail.status, detail.serviceType,
            detail.price, String.valueOf(detail.estimatedDelivery), detail.lastUpdate, detail.lastLocation,
            detail.pickupAddress, detail.pickupCity, detail.pickupPostalCode, String.valueOf(detail.pickupDate),
            detail.recipientName, detail.destinationCity, detail.destinationPostalCode, detail.weightKg,
            detail.packageDescription, detail.declaredValue, detail.customerReference }, '|');
    }

    private static MyShipmentsController.ShipmentDetail detailAs(User actor, String trackingNumber) {
        MyShipmentsController.ShipmentDetail detail;
        System.runAs(actor) {
            detail = MyShipmentsController.getShipment(trackingNumber);
        }
        return detail;
    }

    @IsTest
    static void getShipment_returnsTheShipmentsValuesInMexicoCityTime() {
        // AC-007.3 (BR-06): all 19 values of Ana's newest shipment; created
        // 2026-11-15 18:30 GMT → 12:30 and last update 2026-11-16 01:05 GMT →
        // 2026-11-15 19:05 Mexico City
        String tracking = trackingOf(ANA_NEWEST);
        Test.startTest();
        MyShipmentsController.ShipmentDetail detail = detailAs(ana(), tracking);
        Test.stopTest();
        Assert.areEqual(
            tracking + '|2026-11-15 12:30|In transit|Standard|165.00|2026-12-08|2026-11-15 19:05|Puebla hub|'
                + 'Av. Reforma 100, Col. Juarez|Ciudad de Mexico|06600|2026-12-01|'
                + ANA_NEWEST + '|Puebla|44160|1.50|Test package|1000.00|ABC-3',
            detailValues(detail), 'The detail must carry all 19 values of Ana\'s shipment');
    }

    @IsTest
    static void getShipment_returnsMartasOwnShipmentsValues() {
        // AC-007.3 (second input): all 19 values of Marta's own shipment, whose
        // pickup and package values differ from Ana's; created 2026-11-16 15:00
        // GMT → 09:00 and last update 2026-11-17 20:45 GMT → 14:45 Mexico City
        String tracking = trackingOf(MARTA_IN_TRANSIT);
        Test.startTest();
        MyShipmentsController.ShipmentDetail detail = detailAs(marta(), tracking);
        Test.stopTest();
        Assert.areEqual(
            tracking + '|2026-11-16 09:00|In transit|Standard|230.00|2026-12-09|2026-11-17 14:45|Merida hub|'
                + 'Calle 60 No. 500, Centro|Cancun|77500|2026-12-02|'
                + MARTA_IN_TRANSIT + '|Merida|97000|4.25|Lab samples|2500.00|ORD-7',
            detailValues(detail), 'The detail must carry all 19 values of Marta\'s shipment');
    }

    @IsTest
    static void getShipment_saysNotFound_forAnotherCustomersShipment() {
        // AC-007.3 (BR-07): A asks for B's tracking number → "not found"
        String martas = trackingOf(MARTA_IN_TRANSIT);
        Test.startTest();
        String message = detailRefusalAs(ana(), martas);
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.NOT_FOUND_MESSAGE, message, 'Another customer\'s shipment must be "not found"');
    }

    @IsTest
    static void getShipment_saysNotFound_forAnUnknownTrackingNumber() {
        // AC-007.3: an unknown tracking number gets the same "not found"
        Test.startTest();
        String message = detailRefusalAs(ana(), 'RC999999999');
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.NOT_FOUND_MESSAGE, message, 'An unknown tracking number must be "not found"');
    }

    @IsTest
    static void getShipment_saysNotFound_forAMalformedTrackingNumber() {
        // AC-007.3 (P8): a malformed value gets the same "not found"
        Test.startTest();
        String message = detailRefusalAs(ana(), 'RC%\' OR Name != \'');
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.NOT_FOUND_MESSAGE, message, 'A malformed tracking number must be "not found"');
    }

    // ─── AC-006.8: the site guest ───────────────────────────────────────────

    @IsTest
    static void listShipments_refusesTheSiteGuest() {
        // AC-006.8: the real site guest user is refused with a generic error
        Test.startTest();
        String message = listRefusalAs(TestDataFactory.siteGuestUser(), null, null);
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.NOT_AVAILABLE_MESSAGE, message, 'The guest must get the generic refusal');
    }

    @IsTest
    static void getShipment_refusesTheSiteGuest() {
        // AC-006.8: the real site guest user is refused with a generic error
        String tracking = trackingOf(ANA_NEWEST);
        Test.startTest();
        String message = detailRefusalAs(TestDataFactory.siteGuestUser(), tracking);
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.NOT_AVAILABLE_MESSAGE, message, 'The guest must get the generic refusal');
    }

    // ─── BR-07 (P2): a signed-in user without a customer account ───────────

    @IsTest
    static void listShipments_refusesASignedInUserWithoutACustomerAccount() {
        // BR-07 (P2): the internal user running the test has no User.AccountId → generic refusal
        Test.startTest();
        String message = listRefusalAs(new User(Id = UserInfo.getUserId()), null, null);
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.NOT_AVAILABLE_MESSAGE, message, 'A user without a customer account must get the generic refusal');
    }

    @IsTest
    static void getShipment_refusesASignedInUserWithoutACustomerAccount() {
        // BR-07 (P2): the same user asking for Ana's shipment → generic refusal, not the detail
        String tracking = trackingOf(ANA_NEWEST);
        Test.startTest();
        String message = detailRefusalAs(new User(Id = UserInfo.getUserId()), tracking);
        Test.stopTest();
        Assert.areEqual(MyShipmentsController.NOT_AVAILABLE_MESSAGE, message, 'A user without a customer account must get the generic refusal');
    }
}
