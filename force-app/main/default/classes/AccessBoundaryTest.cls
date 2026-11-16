/**
 * Access-boundary tests: the same code paths exercised as the real site guest user and as a logged-in
 * customer, not as the admin. Covers BR-01, BR-02, BR-04, BR-07, BR-09 and the guest rule from CLAUDE.md
 * ("the guest user receives no object permissions"). Requires the RutaCargo site (its guest user) to be deployed.
 */
@IsTest
private class AccessBoundaryTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantSupportAccess();
        TestDataFactory.createRegistrationOwner();
        TestDataFactory.createShipment(null, 'In transit', 'G-1');
    }

    private static User guest() {
        List<Site> sites = [SELECT GuestUserId FROM Site WHERE Name = 'RutaCargo' LIMIT 1];
        Assert.areEqual(1, sites.size(), 'the RutaCargo site must be deployed for these tests');
        return [SELECT Id, UserType FROM User WHERE Id = :sites[0].GuestUserId];
    }

    private static String tn() {
        return [SELECT Name FROM Shipment__c WHERE Customer_Reference__c = 'G-1'].Name;
    }

    private static void post(String trackingNumber) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/entregaya/v1/status';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"trackingNumber":"' + trackingNumber + '","status":"Delivered","location":"x","timestamp":"2026-11-20T10:00:00-06:00","proofId":"PRF-1"}');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        EntregaYaStatusRestResource.post();
    }

    // ---- guest: public flows work and nothing else is reachable ----------------------------------

    @IsTest
    static void guestCanTrackAndOpenDetailsThroughTheController_BR_01_AC_002_1() {
        String number1 = tn();
        System.runAs(guest()) {
            Assert.areEqual('Guest', UserInfo.getUserType());
            RutaCargoDtos.TrackingResponse tracking = RutaCargoController.trackShipments('trackingNumber', number1, null);
            Assert.areEqual(1, tracking.found.size());
            Assert.areEqual('Monterrey', tracking.found[0].destinationCity);
            RutaCargoDtos.DeliveryDetails details = RutaCargoController.getDeliveryDetails(number1, TestDataFactory.POSTAL);
            Assert.areEqual('OK', details.outcome);
            RutaCargoDtos.DeliveryDetails wrong = RutaCargoController.getDeliveryDetails(number1, '00000');
            Assert.areEqual('MISMATCH', wrong.outcome);
            Assert.isNull(wrong.recipientName);
        }
    }

    @IsTest
    static void guestTrackingByReferenceExposesOnlyPublicFields_BR_01_BR_03() {
        System.runAs(guest()) {
            RutaCargoDtos.TrackingResponse tracking = RutaCargoController.trackShipments('reference', 'g-1', null);
            Assert.areEqual(1, tracking.found.size());
            Map<String, Object> row = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(tracking.found[0]));
            Assert.areEqual(
                new Set<String>{ 'trackingNumber', 'status', 'originCity', 'destinationCity', 'lastLocation', 'lastUpdate', 'estimatedDelivery' },
                row.keySet(),
                'exactly the AC-001.2 fields'
            );
        }
    }

    @IsTest
    static void guestHasNoObjectAccess_CLAUDE_security_rule() {
        Id shipmentId = [SELECT Id FROM Shipment__c LIMIT 1].Id;
        System.runAs(guest()) {
            for (String soql : new List<String>{
                'SELECT Id FROM Shipment__c', 'SELECT Id FROM Delivery_Change__c', 'SELECT Id FROM Account', 'SELECT Id FROM Contact'
            }) {
                try {
                    Database.query(soql, AccessLevel.USER_MODE);
                    Assert.fail('guest must not read: ' + soql);
                } catch (Exception e) {
                    Assert.isTrue(e instanceof System.SecurityException || e instanceof QueryException, 'blocked: ' + e.getTypeName());
                }
            }
            try {
                Database.insert(new Shipment__c(Status__c = 'Delivered'), AccessLevel.USER_MODE);
                Assert.fail('guest must not create shipments');
            } catch (Exception e) {
                Assert.isTrue(e instanceof DmlException || e instanceof System.SecurityException, 'blocked: ' + e.getTypeName());
            }
            try {
                Database.update(new Shipment__c(Id = shipmentId, Status__c = 'Delivered'), AccessLevel.USER_MODE);
                Assert.fail('guest must not change a status (BR-09)');
            } catch (Exception e) {
                Assert.isTrue(e instanceof DmlException || e instanceof System.SecurityException, 'blocked: ' + e.getTypeName());
            }
        }
    }

    @IsTest
    static void guestCannotUseCustomerMethods_BR_07() {
        System.runAs(guest()) {
            try {
                RutaCargoController.getMyShipments(null, null);
                Assert.fail('expected exception');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
            try {
                RutaCargoController.quoteShipment('Standard', 1, 100);
                Assert.fail('expected exception');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
            try {
                CustomerService.createShipment('a', 'b', '06000', ShipmentRules.today().addDays(1), 'r', 'a', 'c', '64000', '1', 'r@y.test', 'Standard', 1, 'x', 1, null, null);
                Assert.fail('expected exception');
            } catch (CustomerService.CustomerException e) {
                Assert.isTrue(e.getMessage().contains('log in'));
            }
        }
    }

    @IsTest
    static void guestIsRefusedByTheCarrierEndpoint_BR_04() {
        String number1 = tn();
        System.runAs(guest()) {
            post(number1);
            Assert.areEqual(403, RestContext.response.statusCode);
        }
        Assert.areEqual('In transit', [SELECT Status__c FROM Shipment__c WHERE Name = :number1].Status__c, 'status unchanged');
    }

    // ---- customer ---------------------------------------------------------------------------------

    @IsTest
    static void customerHasNoDirectShipmentAccessAndCannotChangeStatus_BR_07_BR_09() {
        User customer = TestDataFactory.registerCustomer('bound@acme.test');
        Shipment__c own = TestDataFactory.createShipment(customer.Contact.AccountId, 'In transit', 'C-1');
        System.runAs(customer) {
            try {
                Database.query('SELECT Id FROM Shipment__c', AccessLevel.USER_MODE);
                Assert.fail('customer has no object permission on Shipment__c');
            } catch (Exception e) {
                Assert.isTrue(e instanceof System.SecurityException || e instanceof QueryException, 'blocked: ' + e.getTypeName());
            }
            try {
                Database.update(new Shipment__c(Id = own.Id, Status__c = 'Delivered', Price__c = 1), AccessLevel.USER_MODE);
                Assert.fail('customer must not edit status or price');
            } catch (Exception e) {
                Assert.isTrue(e instanceof DmlException || e instanceof System.SecurityException, 'blocked: ' + e.getTypeName());
            }
        }
        Shipment__c after = [SELECT Status__c, Price__c FROM Shipment__c WHERE Id = :own.Id];
        Assert.areEqual('In transit', after.Status__c);
        Assert.areEqual(171, after.Price__c);
    }

    @IsTest
    static void customerCannotRepointTheirContactToAnotherAccount_BR_07() {
        User ana = TestDataFactory.registerCustomer('repoint1@acme.test');
        User marta = TestDataFactory.registerCustomer('repoint2@acme.test');
        System.runAs(ana) {
            try {
                Database.update(new Contact(Id = ana.ContactId, AccountId = marta.Contact.AccountId), AccessLevel.USER_MODE);
                Assert.fail('a customer must not be able to change Contact.AccountId');
            } catch (Exception e) {
                Assert.isTrue(e instanceof DmlException || e instanceof System.SecurityException, 'blocked: ' + e.getTypeName());
            }
        }
        Assert.areEqual(ana.Contact.AccountId, [SELECT AccountId FROM Contact WHERE Id = :ana.ContactId].AccountId);
    }

    @IsTest
    static void customerCannotReadAnotherCustomersShipmentThroughTheController_BR_07() {
        User ana = TestDataFactory.registerCustomer('anab@acme.test');
        User marta = TestDataFactory.registerCustomer('martab@acme.test');
        Shipment__c theirs = TestDataFactory.createShipment(marta.Contact.AccountId, 'In transit', 'M-1');
        String theirNumber = TestDataFactory.trackingOf(theirs.Id);
        System.runAs(ana) {
            Assert.isNull(RutaCargoController.getMyShipment(theirNumber), 'not found for another account');
            Assert.areEqual(0, RutaCargoController.getMyShipments(null, 'M-1').size());
            Assert.areEqual(0, RutaCargoController.getMyShipments(null, theirNumber).size());
        }
    }

    @IsTest
    static void shipmentIsCreatedUnderTheCallerAccountNeverAnotherOne_BR_07() {
        User ana = TestDataFactory.registerCustomer('owna@acme.test');
        User marta = TestDataFactory.registerCustomer('ownb@acme.test');
        RutaCargoDtos.ActionResult created;
        System.runAs(ana) {
            Date pickup = ShipmentRules.today().addDays(1);
            while (!ShipmentRules.isBusinessDay(pickup)) {
                pickup = pickup.addDays(1);
            }
            created = RutaCargoController.requestShipment('a', 'b', '06000', pickup, 'r', 'a', 'c', '64000', '1', 'r@y.test', 'Standard', 1, 'x', 1, null, null);
        }
        Assert.isTrue(created.success);
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment__c WHERE Name = :created.trackingNumber AND Account__c = :ana.Contact.AccountId], 'created under the caller account');
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE Name = :created.trackingNumber AND Account__c = :marta.Contact.AccountId]);
        System.runAs(marta) {
            Assert.areEqual(0, RutaCargoController.getMyShipments(null, null).size());
        }
    }

    @IsTest
    static void customerIsRefusedByTheCarrierEndpoint_BR_04() {
        User customer = TestDataFactory.registerCustomer('rest@acme.test');
        String number1 = tn();
        System.runAs(customer) {
            post(number1);
            Assert.areEqual(403, RestContext.response.statusCode);
        }
        Assert.areEqual('In transit', [SELECT Status__c FROM Shipment__c WHERE Name = :number1].Status__c, 'status unchanged');
    }

    // ---- lock behaviour (BR-02) ---------------------------------------------------------------------

    @IsTest
    static void lockBlocksProofAndRescheduleToo_BR_02() {
        String number1 = tn();
        for (Integer i = 0; i < RecipientService.MAX_FAILURES; i++) {
            RecipientService.getDetails(number1, '9999' + i);
        }
        Assert.areEqual('LOCKED', RecipientService.getProof(number1, TestDataFactory.POSTAL).outcome);
        Assert.areEqual('LOCKED', RecipientService.reschedule(number1, TestDataFactory.POSTAL, ShipmentRules.today().addDays(4), null).outcome);
        Assert.areEqual(0, [SELECT COUNT() FROM Delivery_Change__c]);
    }

    @IsTest
    static void lockExpiresAfterTheWindow_BR_02() {
        String number1 = tn();
        for (Integer i = 0; i < RecipientService.MAX_FAILURES; i++) {
            RecipientService.getDetails(number1, '9999' + i);
        }
        Shipment__c locked = [SELECT Id, Locked_Until__c FROM Shipment__c WHERE Name = :number1];
        Assert.isTrue(locked.Locked_Until__c > Datetime.now(), 'locked into the future');
        locked.Locked_Until__c = Datetime.now().addMinutes(-1);
        update locked;
        Assert.areEqual('OK', RecipientService.getDetails(number1, TestDataFactory.POSTAL).outcome, 'right code works after expiry');
        Assert.areEqual(0, [SELECT Failed_Verifications__c FROM Shipment__c WHERE Name = :number1].Failed_Verifications__c, 'counter reset after success');
    }

    // ---- login / reset (AC-005.5, AC-005.6) -----------------------------------------------------------

    @IsTest
    static void resetAnswersTheSameForRegisteredAndUnknownEmails_AC_005_6() {
        TestDataFactory.registerCustomer('known@acme.test');
        String known = RutaCargoController.forgotPassword('known@acme.test');
        String unknown = RutaCargoController.forgotPassword('unknown@acme.test');
        Assert.areEqual(unknown, known, 'no way to discover which emails have an account');
    }

    @IsTest
    static void loginFailureDoesNotRevealWhetherTheEmailExists_AC_005_5() {
        TestDataFactory.registerCustomer('login@acme.test');
        String knownMessage;
        String unknownMessage;
        try {
            RutaCargoController.login('login@acme.test', 'wrong-password-1', '/');
        } catch (AuraHandledException e) {
            knownMessage = e.getMessage();
        }
        try {
            RutaCargoController.login('nobody@acme.test', 'wrong-password-1', '/');
        } catch (AuraHandledException e) {
            unknownMessage = e.getMessage();
        }
        Assert.isNotNull(knownMessage, 'wrong password is refused');
        Assert.isNotNull(unknownMessage, 'unknown email is refused');
        Assert.areEqual(unknownMessage, knownMessage, 'same error for both');
    }
}
