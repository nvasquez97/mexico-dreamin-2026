/**
 * Tests for PublicTrackingController, run as the real site guest user.
 * Covers AC-001.1 to AC-001.5 and BR-01.
 */
@IsTest
private class PublicTrackingControllerTest {

    @TestSetup
    static void setup() {
        Account acme = TestDataFactory.buildCustomerAccount('Acme Test');
        Database.insert(acme, AccessLevel.SYSTEM_MODE);
        List<Shipment__c> shipments = new List<Shipment__c>();
        Shipment__c inTransit = TestDataFactory.buildShipment(acme.Id, 'In transit');
        inTransit.Customer_Reference__c = 'PO-777';
        inTransit.Estimated_Delivery__c = Date.newInstance(2026, 11, 25);
        shipments.add(inTransit);
        Shipment__c requested = TestDataFactory.buildShipment(acme.Id, 'Requested');
        requested.Customer_Reference__c = 'PO-888';
        requested.Estimated_Delivery__c = Date.newInstance(2026, 11, 20);
        shipments.add(requested);
        Shipment__c delivered = TestDataFactory.buildShipment(acme.Id, 'Delivered');
        delivered.Estimated_Delivery__c = Date.newInstance(2026, 11, 18);
        shipments.add(delivered);
        Database.insert(shipments, AccessLevel.SYSTEM_MODE);
    }

    private static List<Shipment__c> loadShipments() {
        return [SELECT Id, Name, Status__c FROM Shipment__c WITH SYSTEM_MODE ORDER BY Name];
    }

    private static PublicTrackingController.TrackingResult trackAsGuest(String searchBy, String raw, String sortBy) {
        PublicTrackingController.TrackingResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            Test.startTest();
            result = PublicTrackingController.track(searchBy, raw, sortBy);
            Test.stopTest();
        }
        return result;
    }

    // Covers AC-001.1, AC-001.2: guest searches by tracking number and sees the public fields.
    @IsTest
    static void shouldReturnPublicFields_WhenGuestSearchesByTrackingNumber() {
        Shipment__c first = loadShipments()[0];
        PublicTrackingController.TrackingResult result = trackAsGuest('trackingNumber', first.Name, 'status');
        Assert.areEqual(1, result.shipments.size(), 'One shipment found');
        PublicTrackingController.ShipmentStatus found = result.shipments[0];
        Assert.areEqual(first.Name, found.trackingNumber, 'Tracking number');
        Assert.areEqual(first.Status__c, found.status, 'Status');
        Assert.areEqual('Ciudad de Mexico', found.originCity, 'Origin city');
        Assert.areEqual('Monterrey', found.destinationCity, 'Destination city');
        Assert.areEqual('Ciudad de Mexico, CDMX', found.lastLocation, 'Last location');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 11, 16, 18, 0, 0), found.lastUpdate, 'Last update');
        Assert.isNotNull(found.estimatedDelivery, 'Estimated delivery');
        Assert.areEqual(0, result.notFound.size(), 'Nothing missing');
    }

    // Covers BR-01: nothing beyond the public fields is serialized to the visitor.
    @IsTest
    static void shouldNotExposeRecipientPriceOrInternalData_WhenGuestTracks() {
        Shipment__c first = loadShipments()[0];
        String json = JSON.serialize(trackAsGuest('trackingNumber', first.Name, 'status'));
        Map<String, Object> result = (Map<String, Object>) System.JSON.deserializeUntyped(json);
        Map<String, Object> shipment = (Map<String, Object>) ((List<Object>) result.get('shipments'))[0];
        Assert.areEqual(
            new Set<String>{ 'trackingNumber', 'status', 'originCity', 'destinationCity', 'lastLocation', 'lastUpdate', 'estimatedDelivery' },
            shipment.keySet(), 'Exactly the AC-001.2 fields');
        for (String secret : new List<String>{ 'Laura', 'Hidalgo', 'laura.garza', 'Ring twice', 'VIP', 'Acme', 'Books' }) {
            Assert.isFalse(json.contains(secret), 'Response must not contain ' + secret + ': ' + json);
        }
    }

    // Covers AC-001.1: up to 10 values separated by commas or line breaks.
    @IsTest
    static void shouldAcceptCommasAndLineBreaks_WhenSeveralValues() {
        List<Shipment__c> all = loadShipments();
        String raw = all[0].Name + ',' + all[1].Name + '\n' + all[2].Name + '\r\n';
        PublicTrackingController.TrackingResult result = trackAsGuest('trackingNumber', raw, 'status');
        Assert.areEqual(3, result.shipments.size(), 'All three found');
    }

    // Covers AC-001.1: more than 10 values is rejected.
    @IsTest
    static void shouldReject_WhenMoreThanTenValues() {
        List<String> values = new List<String>();
        for (Integer i = 1; i <= 11; i++) {
            values.add('RC00000' + (9000 + i));
        }
        try {
            trackAsGuest('trackingNumber', String.join(values, ','), 'status');
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('up to 10'), 'Message: ' + e.getMessage());
        }
    }

    // Covers AC-001.1: search by order reference.
    @IsTest
    static void shouldFindShipment_WhenSearchingByReference() {
        PublicTrackingController.TrackingResult result = trackAsGuest('reference', 'PO-777', 'status');
        Assert.areEqual(1, result.shipments.size(), 'Found by reference');
        Assert.areEqual('In transit', result.shipments[0].status, 'The PO-777 shipment');
    }

    // Covers AC-001.1: a tracking number is not matched when searching by reference.
    @IsTest
    static void shouldNotMatchTrackingNumber_WhenSearchingByReference() {
        Shipment__c first = loadShipments()[0];
        PublicTrackingController.TrackingResult result = trackAsGuest('reference', first.Name, 'status');
        Assert.areEqual(0, result.shipments.size(), 'Tracking numbers are not references');
        Assert.areEqual(new List<String>{ first.Name }, result.notFound, 'Listed as not found');
    }

    // Covers AC-001.3: unmatched values are listed as not found, matched ones are returned.
    @IsTest
    static void shouldListNotFound_WhenValueDoesNotMatch() {
        Shipment__c first = loadShipments()[0];
        PublicTrackingController.TrackingResult result = trackAsGuest('trackingNumber', first.Name + ',RC999999999', 'status');
        Assert.areEqual(1, result.shipments.size(), 'Matched one');
        Assert.areEqual(new List<String>{ 'RC999999999' }, result.notFound, 'Unmatched listed');
    }

    // Covers AC-001.4: sort by status follows the shipment lifecycle order.
    @IsTest
    static void shouldSortByStatusLifecycle_WhenSortByStatus() {
        List<Shipment__c> all = loadShipments();
        String raw = all[2].Name + ',' + all[0].Name + ',' + all[1].Name;
        PublicTrackingController.TrackingResult result = trackAsGuest('trackingNumber', raw, 'status');
        Assert.areEqual('Requested', result.shipments[0].status, 'First');
        Assert.areEqual('In transit', result.shipments[1].status, 'Second');
        Assert.areEqual('Delivered', result.shipments[2].status, 'Third');
    }

    // Covers AC-001.4: sort by estimated delivery date ascending.
    @IsTest
    static void shouldSortByEstimatedDelivery_WhenSortByEstimatedDelivery() {
        List<Shipment__c> all = loadShipments();
        String raw = all[0].Name + ',' + all[1].Name + ',' + all[2].Name;
        PublicTrackingController.TrackingResult result = trackAsGuest('trackingNumber', raw, 'estimatedDelivery');
        Assert.areEqual(Date.newInstance(2026, 11, 18), result.shipments[0].estimatedDelivery, 'Earliest first');
        Assert.areEqual(Date.newInstance(2026, 11, 20), result.shipments[1].estimatedDelivery, 'Then');
        Assert.areEqual(Date.newInstance(2026, 11, 25), result.shipments[2].estimatedDelivery, 'Latest last');
    }

    // Covers AC-001.4: a sort field outside the closed list is rejected.
    @IsTest
    static void shouldReject_WhenSortFieldNotAllowed() {
        try {
            trackAsGuest('trackingNumber', 'RC000000001', 'Price__c');
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('sort'), 'Message: ' + e.getMessage());
        }
    }

    // Covers AC-001.1: a search mode outside the closed list is rejected.
    @IsTest
    static void shouldReject_WhenSearchModeNotAllowed() {
        try {
            trackAsGuest('Recipient_Name__c', 'Laura', 'status');
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('search'), 'Message: ' + e.getMessage());
        }
    }

    // Covers AC-001.5: case and surrounding spaces are ignored.
    @IsTest
    static void shouldIgnoreCaseAndSpaces_WhenSearching() {
        Shipment__c first = loadShipments()[0];
        PublicTrackingController.TrackingResult byTracking = trackAsGuest('trackingNumber', '  ' + first.Name.toLowerCase() + '  ', 'status');
        Assert.areEqual(1, byTracking.shipments.size(), 'Tracking number found ignoring case and spaces');
        Assert.areEqual(0, byTracking.notFound.size(), 'Nothing missing');
    }

    // Covers AC-001.5 (reference): lower case reference with spaces still matches.
    @IsTest
    static void shouldIgnoreCaseAndSpaces_WhenSearchingByReference() {
        PublicTrackingController.TrackingResult result = trackAsGuest('reference', '   po-888 ', 'status');
        Assert.areEqual(1, result.shipments.size(), 'Reference found ignoring case and spaces');
    }

    // Covers BR-01 (malicious input): SOQL-like text matches nothing and returns no data.
    @IsTest
    static void shouldReturnNothing_WhenInputLooksLikeInjection() {
        PublicTrackingController.TrackingResult result = trackAsGuest('reference', '\' OR Name != \'', 'status');
        Assert.areEqual(0, result.shipments.size(), 'No shipments for malicious input');
        Assert.areEqual(1, result.notFound.size(), 'Reported as not found');
    }

    // Covers AC-001.1: empty input is rejected with a message.
    @IsTest
    static void shouldReject_WhenNoValues() {
        try {
            trackAsGuest('trackingNumber', ' , \n ', 'status');
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('at least one'), 'Message: ' + e.getMessage());
        }
    }
}
