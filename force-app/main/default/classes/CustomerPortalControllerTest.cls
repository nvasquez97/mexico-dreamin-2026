@IsTest
private class CustomerPortalControllerTest {
    private static Map<String, Object> validForm() {
        return new Map<String, Object>{
            'pickupAddress' => 'Calle Prueba 1', 'pickupCity' => 'Puebla', 'pickupPostalCode' => '72000',
            'pickupDate' => String.valueOf(TestDataFactory.nextBusinessDay(2)), 'recipientName' => 'Rita Recipient',
            'recipientAddress' => 'Av Test 2', 'destinationCity' => 'Mérida', 'destinationPostalCode' => '97000',
            'recipientPhone' => '9995551234', 'recipientEmail' => 'rita@example.com', 'serviceType' => 'Express',
            'weightKg' => '2', 'declaredValue' => '1000', 'packageDescription' => 'Books', 'customerReference' => 'PO-7',
            'deliveryInstructions' => ''
        };
    }

    private static void expectError(Map<String, Object> form, String fragment) {
        try {
            CustomerPortalController.createShipment(form);
            System.assert(false, 'expected an error containing: ' + fragment);
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains(fragment), e.getMessage());
        }
    }

    // AC-006.1 .. AC-006.6, BR-05, BR-08, BR-09
    @IsTest
    static void requestShipment() {
        Account mine = TestDataFactory.account('Mine');
        User u = TestDataFactory.customerUser(mine, 'mine@example.com');
        Map<String, Object> form = validForm();
        CustomerPortalController.CreatedShipment c;
        System.runAs(u) {
            System.assertEquals(295, CustomerPortalController.quote('Express', 2, 1000)); // AC-006.2
            form.put('status', 'Delivered'); // ignored: BR-09
            form.put('price', '1');          // ignored: BR-08
            c = CustomerPortalController.createShipment(form);
        }
        {
            System.assert(Pattern.matches('RC\\d{9}', c.trackingNumber), c.trackingNumber); // BR-05
            System.assertEquals(295, c.price);
            Date pickup = Date.valueOf((String) form.get('pickupDate'));
            System.assertEquals(ShipmentRules.estimatedDelivery(pickup, 'Express'), c.estimatedDelivery); // AC-006.6

            Shipment__c s = [SELECT Account__c, Status__c, Original_Estimated_Delivery__c, Estimated_Delivery__c FROM Shipment__c WHERE Name = :c.trackingNumber];
            System.assertEquals(mine.Id, s.Account__c);
            System.assertEquals('Requested', s.Status__c); // AC-006.5
            System.assertEquals(s.Estimated_Delivery__c, s.Original_Estimated_Delivery__c);
        }
    }

    // AC-006.3, AC-006.4 and required data
    @IsTest
    static void requestValidation() {
        Account mine = TestDataFactory.account('Mine');
        User u = TestDataFactory.customerUser(mine, 'mine2@example.com');
        System.runAs(u) {
            Date today = ShipmentRules.today();
            Date saturday = today.addDays(1);
            while (Math.mod(Date.newInstance(1900, 1, 7).daysBetween(saturday), 7) != 6) {
                saturday = saturday.addDays(1);
            }
            Map<String, Object> f = validForm(); f.put('pickupDate', String.valueOf(today)); expectError(f, 'pickup date');
            f = validForm(); f.put('pickupDate', String.valueOf(TestDataFactory.nextBusinessDay(16))); expectError(f, 'pickup date');
            f = validForm(); f.put('pickupDate', String.valueOf(saturday)); expectError(f, 'pickup date');
            f = validForm(); f.put('weightKg', '30.01'); expectError(f, 'weight');
            f = validForm(); f.put('weightKg', '0'); expectError(f, 'weight');
            f = validForm(); f.put('declaredValue', '50000.01'); expectError(f, 'declared value');
            f = validForm(); f.put('destinationPostalCode', '9700'); expectError(f, 'Postal codes');
            f = validForm(); f.put('recipientEmail', 'nope'); expectError(f, 'email');
            f = validForm(); f.put('recipientName', ''); expectError(f, 'required');
            f = validForm(); f.put('serviceType', 'Teleport'); expectError(f, 'service');
            f = validForm(); f.put('weightKg', 'abc'); expectError(f, 'weight');
            // maximums are allowed
            f = validForm(); f.put('weightKg', '30'); f.put('declaredValue', '50000');
            System.assertNotEquals(null, CustomerPortalController.createShipment(f).trackingNumber);
        }
        System.assertEquals(1, [SELECT COUNT() FROM Shipment__c], 'invalid requests created nothing; only the max-values one did');
    }

    // AC-007.1 .. AC-007.3, BR-03, BR-07
    @IsTest
    static void myShipmentsAreIsolated() {
        Account mine = TestDataFactory.account('Mine');
        Account other = TestDataFactory.account('Other');
        Shipment__c a = TestDataFactory.shipment(mine.Id, 'In transit', '64000');
        Shipment__c b = TestDataFactory.shipment(mine.Id, 'Delivered', '64000');
        Shipment__c theirs = TestDataFactory.shipment(other.Id, 'In transit', '64000');
        User u = TestDataFactory.customerUser(mine, 'mine3@example.com');
        System.runAs(u) {
            CustomerPortalController.MyShipmentsPage all = CustomerPortalController.listShipments(null, null, 0);
            System.assertEquals(2, all.shipments.size());
            for (CustomerPortalController.MyShipment m : all.shipments) {
                System.assertNotEquals(theirs.Name, m.trackingNumber, 'BR-07');
                System.assertEquals(200, m.price); // own price visible (BR-03)
            }
            System.assertEquals(1, CustomerPortalController.listShipments('Delivered', null, 0).shipments.size());
            System.assertEquals(1, CustomerPortalController.listShipments(null, a.Name, 0).shipments.size());
            System.assertEquals(2, CustomerPortalController.listShipments(null, 'rita', 0).shipments.size());
            System.assertEquals(2, CustomerPortalController.listShipments(null, 'ref-1', 0).shipments.size());
            System.assertEquals(0, CustomerPortalController.listShipments(null, '%', 0).shipments.size(), 'wildcards are escaped');

            CustomerPortalController.ShipmentDetail d = CustomerPortalController.getShipment(b.Name);
            System.assertEquals('Delivered', d.summary.status);
            System.assertEquals('Rita Recipient', d.input.recipientName);
            String json = JSON.serialize(d);
            System.assert(!json.contains('SECRET') && !json.contains('Carrier') && !json.contains('arrier'), 'BR-03');
            try {
                CustomerPortalController.getShipment(theirs.Name);
                System.assert(false, 'someone else\'s shipment');
            } catch (AuraHandledException e) {
                System.assertEquals('Shipment not found.', e.getMessage());
            }
        }
    }

    @IsTest
    static void guestsAndInternalUsersAreRejected() {
        try {
            CustomerPortalController.listShipments(null, null, 0); // running user has no contact
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('customer account'));
        }
        System.assertNotEquals(null, CustomerPortalController.pickupWindow().get('min'));
    }
}
