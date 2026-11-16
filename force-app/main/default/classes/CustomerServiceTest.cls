/**
 * Tests for sign-up, shipment request and "my shipments" (REQ-005, REQ-006, REQ-007).
 */
@IsTest
private class CustomerServiceTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantSupportAccess();
        TestDataFactory.createRegistrationOwner();
    }

    private static RutaCargoDtos.ActionResult register(String email, String password) {
        return CustomerService.register('Business', 'Acme SA', 'Ana', 'Lopez', email, '8112345678', password);
    }

    private static Date nextBusinessDay() {
        Date d = ShipmentRules.today().addDays(1);
        while (!ShipmentRules.isBusinessDay(d)) {
            d = d.addDays(1);
        }
        return d;
    }

    private static RutaCargoDtos.ActionResult request(String service, Decimal weight, Decimal value, Date pickup) {
        return CustomerService.createShipment(
            'Av. Juarez 100', 'Ciudad de Mexico', '06000', pickup, 'Luis Perez', 'Calle Hidalgo 45', 'Monterrey', '64000',
            '8187654321', 'luis@example.com', service, weight, 'Books', value, 'ORD-77', 'Ring twice'
        );
    }

    // ---- sign-up -----------------------------------------------------------------------------

    @IsTest
    static void signUpCreatesAccountContactAndUser_AC_005_1_AC_005_2() {
        Test.startTest();
        RutaCargoDtos.ActionResult result = register('ana@acme.test', 'passw0rd-long1');
        Test.stopTest();
        Assert.isTrue(result.success);
        Account account = [SELECT Name, Customer_Type__c, Owner.UserRole.DeveloperName FROM Account WHERE Name = 'Acme SA'];
        Assert.areEqual('Business', account.Customer_Type__c);
        Assert.areEqual('RutaCargo_Customer_Owner', account.Owner.UserRole.DeveloperName);
        Contact contact = [SELECT FirstName, LastName, Email, AccountId FROM Contact WHERE Email = 'ana@acme.test'];
        Assert.areEqual(account.Id, contact.AccountId);
        Assert.areEqual('Lopez', contact.LastName);
        User user = [SELECT Username, Profile.Name, IsActive FROM User WHERE ContactId = :contact.Id];
        Assert.areEqual('RutaCargo Customer', user.Profile.Name);
        Assert.isTrue(user.IsActive);
        Assert.areEqual('ana@acme.test' + CustomerService.USERNAME_SUFFIX, user.Username);
        Assert.areEqual(user.Username, CustomerService.usernameFor(' ANA@acme.test '), 'login by email, case-insensitive');
    }

    @IsTest
    static void emailCanOnlyHaveOneAccount_AC_005_3() {
        Assert.isTrue(register('dup@acme.test', 'passw0rd-long1').success);
        RutaCargoDtos.ActionResult second = register('DUP@acme.test', 'passw0rd-long1');
        Assert.isFalse(second.success);
        Assert.areEqual('ALREADY_REGISTERED', second.message);
        Assert.areEqual(1, [SELECT COUNT() FROM Account WHERE Name = 'Acme SA']);
    }

    @IsTest
    static void weakPasswordRejected_AC_005_4() {
        for (String weak : new List<String>{ 'short1', 'onlyletterslong', '12345678901', null }) {
            RutaCargoDtos.ActionResult result = register('weak@acme.test', weak);
            Assert.isFalse(result.success, 'password ' + weak);
            Assert.isTrue(result.message.contains('at least 10 characters'));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Name = 'Acme SA']);
    }

    @IsTest
    static void signUpRequiresAllFields_AC_005_1() {
        Assert.isFalse(CustomerService.register('Other', 'A', 'B', 'C', 'x@y.test', '1', 'passw0rd-long1').success, 'type');
        Assert.isFalse(CustomerService.register('Individual', '', 'B', 'C', 'x@y.test', '1', 'passw0rd-long1').success, 'name');
        Assert.isFalse(CustomerService.register('Individual', 'A', 'B', 'C', 'not-an-email', '1', 'passw0rd-long1').success, 'email');
        Assert.isFalse(CustomerService.register('Individual', 'A', 'B', 'C', 'x@y.test', '', 'passw0rd-long1').success, 'phone');
    }

    @IsTest
    static void unknownEmailHasNoUsername_AC_005_5() {
        Assert.isNull(CustomerService.usernameFor('nobody@acme.test'));
        Assert.isNull(CustomerService.usernameFor(null));
    }

    @IsTest
    static void forgotPasswordAnswersTheSameForAnyEmail_AC_005_6() {
        String known = RutaCargoController.forgotPassword('nobody@acme.test');
        Assert.isTrue(known.contains('If that email has an account'));
    }

    @IsTest
    static void loginWithUnknownEmailGivesGenericError_AC_005_5() {
        try {
            RutaCargoController.login('nobody@acme.test', 'passw0rd-long1', '/');
            Assert.fail('expected exception');
        } catch (AuraHandledException e) {
            Assert.areEqual('Script-thrown exception', e.getMessage(), 'AuraHandledException message is masked in tests');
        }
    }

    // ---- request a shipment ------------------------------------------------------------------

    @IsTest
    static void customerRequestsShipmentWithServerPrice_AC_006_2_AC_006_5_AC_006_6_BR_08_BR_09() {
        User customer = TestDataFactory.registerCustomer('req@acme.test');
        Date pickup = nextBusinessDay();
        RutaCargoDtos.ActionResult result;
        System.runAs(customer) {
            RutaCargoDtos.ActionResult quote = CustomerService.quote('Express', 3, 2000);
            Assert.areEqual(340.00, quote.price, 'quote: 220 + 90 + 30');
            result = request('Express', 3, 2000, pickup);
        }
        Assert.isTrue(result.success);
        Assert.isTrue(Pattern.matches('RC[0-9]{9}', result.trackingNumber), 'tracking number format (BR-05)');
        Assert.areEqual(340.00, result.price);
        Shipment__c saved = [SELECT Account__c, Status__c, Price__c, Estimated_Delivery__c, Original_Estimated_Delivery__c, Customer_Reference__c, Origin_City__c, Destination_City__c FROM Shipment__c WHERE Name = :result.trackingNumber];
        Assert.areEqual(customer.Contact.AccountId, saved.Account__c, 'created under the customer');
        Assert.areEqual('Requested', saved.Status__c);
        Assert.areEqual(340.00, saved.Price__c);
        Assert.areEqual(ShipmentRules.estimatedDelivery(pickup, 'Express'), saved.Estimated_Delivery__c);
        Assert.areEqual(saved.Estimated_Delivery__c, saved.Original_Estimated_Delivery__c);
        Assert.areEqual('ORD-77', saved.Customer_Reference__c);
        Assert.areEqual('Ciudad de Mexico', saved.Origin_City__c);
        Assert.areEqual('Monterrey', saved.Destination_City__c);
    }

    @IsTest
    static void trackingNumbersAreConsecutive_BR_05() {
        User customer = TestDataFactory.registerCustomer('seq@acme.test');
        Date pickup = nextBusinessDay();
        RutaCargoDtos.ActionResult first;
        RutaCargoDtos.ActionResult second;
        System.runAs(customer) {
            first = request('Standard', 1, 100, pickup);
            second = request('Standard', 1, 100, pickup);
        }
        Assert.areEqual(Integer.valueOf(first.trackingNumber.substring(2)) + 1, Integer.valueOf(second.trackingNumber.substring(2)));
    }

    @IsTest
    static void limitsEnforcedOnServer_AC_006_4() {
        User customer = TestDataFactory.registerCustomer('lim@acme.test');
        Date pickup = nextBusinessDay();
        System.runAs(customer) {
            Assert.isFalse(request('Standard', 30.5, 100, pickup).success, 'too heavy');
            Assert.isFalse(request('Standard', 10, 50001, pickup).success, 'too valuable');
            Assert.isTrue(request('Standard', 30, 50000, pickup).success, 'limits are inclusive');
        }
    }

    @IsTest
    static void pickupDateRulesEnforcedOnServer_AC_006_3() {
        User customer = TestDataFactory.registerCustomer('date@acme.test');
        System.runAs(customer) {
            Assert.isFalse(request('Standard', 1, 100, ShipmentRules.today()).success, 'today');
            Date saturday = ShipmentRules.today().addDays(1);
            while (ShipmentRules.isBusinessDay(saturday)) {
                saturday = saturday.addDays(1);
            }
            Assert.isFalse(request('Standard', 1, 100, saturday).success, 'weekend');
            Assert.isFalse(request('Standard', 1, 100, ShipmentRules.today().addDays(16)).success, 'too far');
            Assert.isFalse(request('Standard', 1, 100, null).success, 'missing');
        }
    }

    @IsTest
    static void invalidFieldsRejected_AC_006_1() {
        User customer = TestDataFactory.registerCustomer('fld@acme.test');
        Date pickup = nextBusinessDay();
        System.runAs(customer) {
            RutaCargoDtos.ActionResult badPostal = CustomerService.createShipment(
                'A', 'B', '6000', pickup, 'R', 'Addr', 'City', '64000', '1', 'r@y.test', 'Standard', 1, 'Books', 100, null, null
            );
            Assert.isFalse(badPostal.success);
            RutaCargoDtos.ActionResult badService = request('Overnight', 1, 100, pickup);
            Assert.isFalse(badService.success);
            RutaCargoDtos.ActionResult missing = CustomerService.createShipment(
                '', 'B', '06000', pickup, 'R', 'Addr', 'City', '64000', '1', 'r@y.test', 'Standard', 1, 'Books', 100, null, null
            );
            Assert.isFalse(missing.success);
        }
    }

    @IsTest
    static void guestOrInternalUserCannotRequest_BR_07() {
        try {
            CustomerService.quote('Standard', 1, 100);
            Assert.fail('a user without a contact must be refused');
        } catch (CustomerService.CustomerException e) {
            Assert.isTrue(e.getMessage().contains('log in'));
        }
    }

    // ---- my shipments ------------------------------------------------------------------------

    @IsTest
    static void customerSeesOnlyOwnShipments_AC_007_1_BR_07() {
        User ana = TestDataFactory.registerCustomer('mine1@acme.test');
        User marta = TestDataFactory.registerCustomer('mine2@acme.test');
        Shipment__c mine = TestDataFactory.createShipment(ana.Contact.AccountId, 'In transit', 'MINE-1');
        Shipment__c theirs = TestDataFactory.createShipment(marta.Contact.AccountId, 'In transit', 'THEIRS-1');
        System.runAs(ana) {
            List<RutaCargoDtos.MyShipment> rows = CustomerService.listMine(null, null);
            Assert.areEqual(1, rows.size());
            Assert.areEqual(TestDataFactory.trackingOf(mine.Id), rows[0].trackingNumber);
            Assert.areEqual('Luis Perez', rows[0].recipientName);
            Assert.areEqual('Monterrey', rows[0].destinationCity);
            Assert.areEqual('Standard', rows[0].serviceType);
            Assert.areEqual(171, rows[0].price);
            Assert.isNotNull(rows[0].requestedOn);
            Assert.isNull(CustomerService.getMine(TestDataFactory.trackingOf(theirs.Id)), 'another customer\'s shipment is invisible');
        }
    }

    @IsTest
    static void listIsNewestFirstAndFilterable_AC_007_1_AC_007_2() {
        User ana = TestDataFactory.registerCustomer('list@acme.test');
        Shipment__c older = TestDataFactory.createShipment(ana.Contact.AccountId, 'Delivered', 'OLD-1');
        Shipment__c newer = TestDataFactory.createShipment(ana.Contact.AccountId, 'In transit', 'NEW-1');
        System.runAs(ana) {
            List<RutaCargoDtos.MyShipment> all = CustomerService.listMine(null, null);
            Assert.areEqual(2, all.size());
            Assert.areEqual(TestDataFactory.trackingOf(newer.Id), all[0].trackingNumber, 'newest first');
            Assert.areEqual(1, CustomerService.listMine('Delivered', null).size());
            Assert.areEqual(1, CustomerService.listMine(null, 'OLD-1').size(), 'by reference');
            Assert.areEqual(1, CustomerService.listMine(null, TestDataFactory.trackingOf(older.Id)).size(), 'by tracking number');
            Assert.areEqual(2, CustomerService.listMine(null, 'luis').size(), 'by recipient');
            Assert.areEqual(0, CustomerService.listMine(null, 'zzz').size());
            try {
                CustomerService.listMine('Bogus', null);
                Assert.fail('status must come from the closed list');
            } catch (CustomerService.CustomerException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    @IsTest
    static void detailShowsEnteredDataAndPriceButNoInternalFields_AC_007_3_BR_03() {
        User ana = TestDataFactory.registerCustomer('detail@acme.test');
        Shipment__c shipment = TestDataFactory.createShipment(ana.Contact.AccountId, 'In transit', 'D-1');
        System.runAs(ana) {
            RutaCargoDtos.ShipmentDetail detail = CustomerService.getMine(TestDataFactory.trackingOf(shipment.Id));
            Assert.areEqual('Av. Juarez 100', detail.pickupAddress);
            Assert.areEqual('Calle Hidalgo 45', detail.recipientAddress);
            Assert.areEqual('Books', detail.packageDescription);
            Assert.areEqual(171, detail.summary.price);
            Assert.areEqual('In transit', detail.summary.status);
            String json = JSON.serialize(detail).toLowerCase();
            for (String forbidden : new List<String>{ 'carriercost', 'margin', 'internalnotes', 'credit' }) {
                Assert.isFalse(json.contains(forbidden), 'customer DTO must not contain ' + forbidden);
            }
        }
    }
}
