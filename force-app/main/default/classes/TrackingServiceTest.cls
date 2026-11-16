/**
 * Tests for public tracking (REQ-001). Test names state the acceptance criterion covered.
 */
@IsTest
private class TrackingServiceTest {
    @TestSetup
    static void setup() {
        TestDataFactory.grantSupportAccess();
        TestDataFactory.createShipment(null, 'In transit', 'ORD-1');
        TestDataFactory.createShipment(null, 'Delivered', 'ord-2');
    }

    private static List<Shipment__c> all() {
        return [SELECT Name, Customer_Reference__c FROM Shipment__c ORDER BY Name];
    }

    @IsTest
    static void searchByTrackingReturnsPublicFields_AC_001_2() {
        String tn = all()[0].Name;
        Test.startTest();
        RutaCargoDtos.TrackingResponse response = TrackingService.search('trackingNumber', tn, null);
        Test.stopTest();
        Assert.areEqual(1, response.found.size());
        RutaCargoDtos.TrackedShipment item = response.found[0];
        Assert.areEqual(tn, item.trackingNumber);
        Assert.areEqual('In transit', item.status);
        Assert.areEqual('Ciudad de Mexico', item.originCity);
        Assert.areEqual('Monterrey', item.destinationCity);
        Assert.areEqual('Ciudad de Mexico', item.lastLocation);
        Assert.isNotNull(item.lastUpdate);
        Assert.isNotNull(item.estimatedDelivery);
        Assert.areEqual(0, response.notFound.size());
    }

    @IsTest
    static void dtoExposesNoInternalOrPersonalFields_BR_01_BR_03() {
        String json = JSON.serialize(TrackingService.search('trackingNumber', all()[0].Name, null));
        for (String forbidden : new List<String>{ 'price', 'carrierCost', 'margin', 'internalNotes', 'recipientName', 'recipientAddress', 'recipientPhone', 'postalCode', 'proofId' }) {
            Assert.isFalse(json.toLowerCase().contains(forbidden.toLowerCase()), 'public DTO must not contain ' + forbidden);
        }
    }

    @IsTest
    static void unmatchedValuesListedAsNotFound_AC_001_3() {
        String tn = all()[0].Name;
        RutaCargoDtos.TrackingResponse response = TrackingService.search('trackingNumber', tn + ',RC999999999', null);
        Assert.areEqual(1, response.found.size());
        Assert.areEqual(new List<String>{ 'RC999999999' }, response.notFound);
    }

    @IsTest
    static void caseAndSpacesIgnored_AC_001_5() {
        String tn = all()[0].Name.toLowerCase();
        RutaCargoDtos.TrackingResponse response = TrackingService.search('trackingNumber', '   ' + tn + '   ', null);
        Assert.areEqual(1, response.found.size());
        RutaCargoDtos.TrackingResponse byRef = TrackingService.search('reference', ' ORD-2 ', null);
        Assert.areEqual(1, byRef.found.size(), 'reference match ignores case');
    }

    @IsTest
    static void commasAndLineBreaksSeparateValues_AC_001_1() {
        List<Shipment__c> rows = all();
        RutaCargoDtos.TrackingResponse response = TrackingService.search('trackingNumber', rows[0].Name + '\n' + rows[1].Name + ',', null);
        Assert.areEqual(2, response.found.size());
    }

    @IsTest
    static void moreThanTenValuesRejected_AC_001_1() {
        List<String> values = new List<String>();
        for (Integer i = 0; i < 11; i++) {
            values.add('RC00000000' + i);
        }
        try {
            TrackingService.search('trackingNumber', String.join(values, ','), null);
            Assert.fail('expected exception');
        } catch (TrackingService.TrackingException e) {
            Assert.isTrue(e.getMessage().contains('up to 10'));
        }
    }

    @IsTest
    static void tenValuesAccepted_AC_001_1() {
        List<String> values = new List<String>();
        for (Integer i = 0; i < 10; i++) {
            values.add('RC00000000' + i);
        }
        Assert.areEqual(10, TrackingService.search('trackingNumber', String.join(values, ','), null).notFound.size());
    }

    @IsTest
    static void invalidSearchByRejected_AC_001_1() {
        try {
            TrackingService.search('name; DROP', 'x', null);
            Assert.fail('expected exception');
        } catch (TrackingService.TrackingException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void sortByStatusAndEstimatedDelivery_AC_001_4() {
        List<Shipment__c> rows = all();
        Shipment__c later = [SELECT Id FROM Shipment__c WHERE Name = :rows[0].Name];
        later.Estimated_Delivery__c = ShipmentRules.today().addDays(9);
        update later;
        String values = rows[0].Name + ',' + rows[1].Name;
        RutaCargoDtos.TrackingResponse byDate = TrackingService.search('trackingNumber', values, 'estimatedDelivery');
        Assert.areEqual(rows[1].Name, byDate.found[0].trackingNumber, 'earliest estimate first');
        RutaCargoDtos.TrackingResponse byStatus = TrackingService.search('trackingNumber', values, 'status');
        Assert.areEqual('In transit', byStatus.found[0].status, 'picklist order: In transit before Delivered');
        Assert.areEqual('Delivered', byStatus.found[1].status);
    }

    @IsTest
    static void controllerWrapsErrors_AC_001_1() {
        try {
            RutaCargoController.trackShipments('trackingNumber', '', null);
            Assert.fail('expected exception');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }
}
