/**
 * Tests for MyShipmentsController, run as two real customer site users of
 * different accounts. Shipments are owned by an internal user, so customers
 * only see them through the sharing set.
 * Covers AC-007.1 to AC-007.3, BR-03 and BR-07.
 */
@IsTest
private class MyShipmentsControllerTest {

    @TestSetup
    static void setup() {
        User owner = TestDataFactory.createAccountOwner('MyShip');
        User ana = TestDataFactory.createCustomerUser('Acme Mine', 'Anacustomer', 'RutaCargo_Customer', owner);
        User marta = TestDataFactory.createCustomerUser('Globex Mine', 'Martacustomer', 'RutaCargo_Customer', owner);
        Id anaAccount = [SELECT Contact.AccountId FROM User WHERE Id = :ana.Id WITH SYSTEM_MODE].Contact.AccountId;
        Id martaAccount = [SELECT Contact.AccountId FROM User WHERE Id = :marta.Id WITH SYSTEM_MODE].Contact.AccountId;
        List<Shipment__c> shipments = new List<Shipment__c>();
        Shipment__c oldest = TestDataFactory.buildShipment(anaAccount, 'Delivered');
        oldest.Recipient_Name__c = 'Pedro Paramo';
        oldest.Customer_Reference__c = 'ACME-001';
        Shipment__c middle = TestDataFactory.buildShipment(anaAccount, 'In transit');
        middle.Recipient_Name__c = 'Laura Garza';
        middle.Customer_Reference__c = 'ACME-002';
        Shipment__c newest = TestDataFactory.buildShipment(anaAccount, 'Requested');
        newest.Recipient_Name__c = 'Juan Preciado';
        newest.Customer_Reference__c = '100%_OFF';
        Shipment__c other = TestDataFactory.buildShipment(martaAccount, 'In transit');
        other.Recipient_Name__c = 'Laura Garza';
        shipments.addAll(new List<Shipment__c>{ oldest, middle, newest, other });
        System.runAs(owner) {
            Database.insert(shipments, AccessLevel.SYSTEM_MODE);
        }
        Test.setCreatedDate(oldest.Id, Datetime.newInstanceGmt(2026, 11, 1, 12, 0, 0));
        Test.setCreatedDate(middle.Id, Datetime.newInstanceGmt(2026, 11, 5, 12, 0, 0));
        Test.setCreatedDate(newest.Id, Datetime.newInstanceGmt(2026, 11, 10, 12, 0, 0));
        Test.setCreatedDate(other.Id, Datetime.newInstanceGmt(2026, 11, 12, 12, 0, 0));
    }

    private static User userNamed(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND ContactId != null WITH SYSTEM_MODE LIMIT 1];
    }

    private static List<MyShipmentsController.ShipmentRow> listAs(String lastName, String status, String search) {
        List<MyShipmentsController.ShipmentRow> rows;
        System.runAs(userNamed(lastName)) {
            rows = MyShipmentsController.getMyShipments(status, search);
        }
        return rows;
    }

    // Covers AC-007.1, BR-07: the list shows only the customer's shipments, most recent first, with the listed columns.
    @IsTest
    static void shouldListOwnShipmentsMostRecentFirst_WhenCustomerOpensList() {
        Test.startTest();
        List<MyShipmentsController.ShipmentRow> rows = listAs('Anacustomer', null, null);
        Test.stopTest();
        Assert.areEqual(3, rows.size(), 'Only Ana shipments');
        Assert.areEqual('Juan Preciado', rows[0].recipientName, 'Newest first');
        Assert.areEqual('Laura Garza', rows[1].recipientName, 'Then middle');
        Assert.areEqual('Pedro Paramo', rows[2].recipientName, 'Oldest last');
        MyShipmentsController.ShipmentRow first = rows[0];
        Assert.isTrue(Pattern.matches('RC[0-9]{9}', first.trackingNumber), 'Tracking number');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 10, 12, 0, 0), first.requestDate, 'Request date');
        Assert.areEqual('Monterrey', first.destinationCity, 'Destination city');
        Assert.areEqual('Requested', first.status, 'Status');
        Assert.areEqual('Standard', first.serviceType, 'Service type');
        Assert.areEqual(171, first.price, 'Price visible to the requesting customer (BR-03)');
    }

    // Covers BR-07: the other customer sees only their own shipment.
    @IsTest
    static void shouldNotShowOtherCustomersShipments_WhenAnotherCustomerLists() {
        List<MyShipmentsController.ShipmentRow> rows = listAs('Martacustomer', null, null);
        Assert.areEqual(1, rows.size(), 'Only Marta shipment');
    }

    // Covers AC-007.2: filter by status.
    @IsTest
    static void shouldFilterByStatus_WhenStatusGiven() {
        List<MyShipmentsController.ShipmentRow> rows = listAs('Anacustomer', 'In transit', null);
        Assert.areEqual(1, rows.size(), 'One in transit');
        Assert.areEqual('Laura Garza', rows[0].recipientName, 'The in-transit shipment');
    }

    // Covers AC-007.2: a status outside the closed list is rejected.
    @IsTest
    static void shouldReject_WhenStatusFilterNotAllowed() {
        try {
            listAs('Anacustomer', 'Delivered\' OR Name != \'', null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('status'), 'Message: ' + e.getMessage());
        }
    }

    // Covers AC-007.2: search by recipient.
    @IsTest
    static void shouldSearchByRecipient_WhenTermGiven() {
        List<MyShipmentsController.ShipmentRow> rows = listAs('Anacustomer', null, 'paramo');
        Assert.areEqual(1, rows.size(), 'Found by recipient');
        Assert.areEqual('Pedro Paramo', rows[0].recipientName, 'Recipient');
    }

    // Covers AC-007.2: search by reference.
    @IsTest
    static void shouldSearchByReference_WhenTermGiven() {
        List<MyShipmentsController.ShipmentRow> rows = listAs('Anacustomer', null, 'ACME-002');
        Assert.areEqual(1, rows.size(), 'Found by reference');
        Assert.areEqual('Laura Garza', rows[0].recipientName, 'Recipient');
    }

    // Covers AC-007.2: search by tracking number.
    @IsTest
    static void shouldSearchByTrackingNumber_WhenTermGiven() {
        List<MyShipmentsController.ShipmentRow> all = listAs('Anacustomer', null, null);
        List<MyShipmentsController.ShipmentRow> rows = listAs('Anacustomer', null, all[2].trackingNumber);
        Assert.areEqual(1, rows.size(), 'Found by tracking number');
        Assert.areEqual(all[2].trackingNumber, rows[0].trackingNumber, 'Same shipment');
    }

    // Covers AC-007.2: wildcard characters are searched literally, not as patterns.
    @IsTest
    static void shouldTreatWildcardsLiterally_WhenSearching() {
        Assert.areEqual(1, listAs('Anacustomer', null, '100%_OFF').size(), 'Literal match');
        Assert.areEqual(1, listAs('Anacustomer', null, '%').size(), 'A bare % matches only the value with a literal %, not all 3');
    }

    // Covers AC-007.2, BR-07: searching for another customer's recipient returns only own shipments.
    @IsTest
    static void shouldOnlySearchOwnShipments_WhenTermMatchesOtherCustomer() {
        List<MyShipmentsController.ShipmentRow> rows = listAs('Martacustomer', null, 'Laura');
        Assert.areEqual(1, rows.size(), 'Only Marta own Laura Garza');
    }

    // Covers AC-007.3: the detail page shows the entered data, the price and the current status.
    @IsTest
    static void shouldReturnDetail_WhenOwnShipment() {
        List<MyShipmentsController.ShipmentRow> rows = listAs('Anacustomer', null, null);
        MyShipmentsController.ShipmentDetail detail;
        System.runAs(userNamed('Anacustomer')) {
            detail = MyShipmentsController.getShipmentDetail(rows[1].id);
        }
        Assert.areEqual(rows[1].trackingNumber, detail.trackingNumber, 'Tracking number');
        Assert.areEqual('In transit', detail.status, 'Current status');
        Assert.areEqual(171, detail.price, 'Price');
        Assert.areEqual('Av. Juarez 100, Centro', detail.pickupAddress, 'Pickup address');
        Assert.areEqual('06000', detail.pickupPostalCode, 'Pickup postal code');
        Assert.areEqual('Laura Garza', detail.recipientName, 'Recipient');
        Assert.areEqual('Calle Hidalgo 200, Centro', detail.recipientAddress, 'Recipient address');
        Assert.areEqual('64000', detail.destinationPostalCode, 'Recipient postal code');
        Assert.areEqual('laura.garza@example.com', detail.recipientEmail, 'Recipient email');
        Assert.areEqual(2, detail.weightKg, 'Weight');
        Assert.areEqual(1000, detail.declaredValue, 'Declared value');
        Assert.areEqual('ACME-002', detail.customerReference, 'Reference');
    }

    // Covers BR-03: the detail never carries carrier cost, margin, internal notes or credit data.
    @IsTest
    static void shouldNotExposeInternalData_WhenOpeningDetail() {
        List<MyShipmentsController.ShipmentRow> rows = listAs('Anacustomer', null, null);
        MyShipmentsController.ShipmentDetail detail;
        System.runAs(userNamed('Anacustomer')) {
            detail = MyShipmentsController.getShipmentDetail(rows[0].id);
        }
        String json = JSON.serialize(detail) + JSON.serialize(rows);
        Assert.isFalse(json.contains('VIP'), 'No internal notes');
        Assert.isFalse(json.contains('"90') || json.contains(':90'), 'No carrier cost');
        Assert.isFalse(json.contains('100000'), 'No credit limit');
        Assert.isFalse(json.contains('High'), 'No credit risk');
    }

    // Covers BR-07: a customer cannot open another customer's shipment, even with its id.
    @IsTest
    static void shouldReject_WhenOpeningAnotherCustomersShipment() {
        Id otherId = [SELECT Id FROM Shipment__c WHERE Account__r.Name = 'Globex Mine' WITH SYSTEM_MODE LIMIT 1].Id;
        System.runAs(userNamed('Anacustomer')) {
            try {
                MyShipmentsController.getShipmentDetail(otherId);
                Assert.fail('Expected AuraHandledException');
            } catch (AuraHandledException e) {
                Assert.areEqual('Shipment not found.', e.getMessage(), 'Same message as a missing shipment');
            }
        }
    }

    // Covers BR-07: an internal user without a customer account cannot use the list.
    @IsTest
    static void shouldReject_WhenUserIsNotACustomer() {
        try {
            MyShipmentsController.getMyShipments(null, null);
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('customers'), 'Message: ' + e.getMessage());
        }
    }

    // Covers BR-07: the site guest (not logged in) cannot list or open customer shipments.
    @IsTest
    static void shouldReject_WhenSiteGuestOpensMyShipments() {
        Id anyShipment = [SELECT Id FROM Shipment__c WITH SYSTEM_MODE LIMIT 1].Id;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            try {
                MyShipmentsController.getMyShipments(null, null);
                Assert.fail('Expected AuraHandledException for the list');
            } catch (AuraHandledException e) {
                Assert.areEqual('Only registered customers can use this page.', e.getMessage(), 'List rejected');
            }
            try {
                MyShipmentsController.getShipmentDetail(anyShipment);
                Assert.fail('Expected AuraHandledException for the detail');
            } catch (AuraHandledException e) {
                Assert.areEqual('Only registered customers can use this page.', e.getMessage(), 'Detail rejected');
            }
        }
    }

    // Covers BR-07: the customer-only classes are granted only to RutaCargo_Customer (and System Administrator), never to the guest.
    @IsTest
    static void shouldGrantCustomerClassesOnlyToCustomerPermissionSet() {
        Set<String> grantees = new Set<String>();
        for (SetupEntityAccess grant : [
            SELECT Parent.Name, Parent.IsOwnedByProfile, Parent.Profile.Name FROM SetupEntityAccess
            WHERE SetupEntityId IN (SELECT Id FROM ApexClass WHERE Name IN ('MyShipmentsController', 'ShipmentRequestController'))
            WITH SYSTEM_MODE
        ]) {
            grantees.add(grant.Parent.IsOwnedByProfile ? 'profile:' + grant.Parent.Profile.Name : grant.Parent.Name);
        }
        grantees.remove('profile:System Administrator');
        Assert.areEqual(new Set<String>{ 'RutaCargo_Customer' }, grantees, 'Only the customer permission set: ' + grantees);
    }
}
