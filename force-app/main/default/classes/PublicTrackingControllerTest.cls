/**
 * @description Proves PublicTrackingController.search, the guest tracking search
 *              of odd/tasks/req-001-public-tracking.md (S1): AC-001.1 (server:
 *              split values, modes, 10-value cap, 100 raw entries, 520-character
 *              entries, closed mode list, generic errors), AC-001.2 (exactly the BR-01 keys, Mexico
 *              City dates, no private value, no Id), AC-001.3 (server: notFound
 *              in input order, 50-row cap with truncated), AC-001.5 (trim and
 *              case-insensitive de-duplication) and AC-001.6 (the real site guest
 *              user gets the results of shipments it cannot read). Tests that do
 *              not use System.runAs run as the running administrator.
 */
@IsTest
private with sharing class PublicTrackingControllerTest {

    private static final String TRACKING = 'TRACKING_NUMBER';
    private static final String REFERENCE_MODE = 'REFERENCE';
    private static final String COUNT_MESSAGE = 'Enter up to 10 values.';
    private static final String GENERIC_MESSAGE = 'We could not complete the search. Please try again.';
    private static final String REFERENCE = 'PO-7781';
    private static final String SHARED_REFERENCE = 'PO-9902';
    private static final String BULK_REFERENCE = 'PO-BULK-251';
    private static final String BOUNDARY_REFERENCE = 'PO-BOUNDARY-50';
    private static final String NO_MATCH_REFERENCE = 'PO-NO-MATCH';
    private static final String NO_MATCH_TRACKING = 'RC999999999';
    private static final String LONG_VALUE = 'RC' + '1'.repeat(49);
    private static final Integer SETUP_SIZE = 10;
    private static final Integer BULK_SIZE = 251;
    private static final Integer RESULT_CAP = 50;
    private static final Integer MAX_RAW_ENTRIES = 100;
    // 10 values of up to 50 characters, each followed by a comma and a space.
    private static final Integer MAX_ENTRY_LENGTH = 520;
    private static final Integer HUGE_ENTRY_PAIRS = 500000;
    private static final Datetime FIRST_UPDATE = Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0);
    private static final Datetime SECOND_UPDATE = Datetime.newInstanceGmt(2026, 11, 21, 3, 0, 0);
    private static final Date FIRST_ESTIMATE = Date.newInstance(2026, 11, 25);
    private static final Date SECOND_ESTIMATE = Date.newInstance(2026, 11, 21);
    private static final Decimal PRICE = 4321.87;
    private static final Decimal CARRIER_COST = 1234.56;
    private static final String INTERNAL_NOTE = 'Internal note: customer pays late';
    private static final String LAST_LOCATION = 'Queretaro hub';
    private static final Set<String> BR01_KEYS = new Set<String>{
        'trackingNumber', 'status', 'originCity', 'destinationCity', 'lastLocation', 'lastUpdate', 'estimatedDelivery'
    };

    // SECURITY-JUSTIFICATION: test fixture only. At API 67 DML and SOQL default
    // to user mode and the running administrator has no field permissions on the
    // RutaCargo fields, so test-only setup DML and read-back SOQL run in system
    // mode. Scope: this test class. Compensating control: the code under test
    // is called as the real site guest user (System.runAs) in the AC-001.6 tests.
    // (pending owner approval, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    @TestSetup
    static void setup() {
        Account customer = TestDataFactory.newCustomerAccount();
        insertAsSystem(new List<Account>{ customer });
        List<Shipment__c> shipments = TestDataFactory.newShipments(customer.Id, SETUP_SIZE);
        setPrivateAndPublicFields(shipments[0], REFERENCE, FIRST_UPDATE, FIRST_ESTIMATE);
        setPrivateAndPublicFields(shipments[1], null, SECOND_UPDATE, SECOND_ESTIMATE);
        shipments[2].Customer_Reference__c = SHARED_REFERENCE;
        shipments[3].Customer_Reference__c = SHARED_REFERENCE;
        insertAsSystem(shipments);
    }

    private static void setPrivateAndPublicFields(Shipment__c shipment, String reference, Datetime lastUpdate, Date estimate) {
        shipment.Customer_Reference__c = reference;
        shipment.Last_Update__c = lastUpdate;
        shipment.Estimated_Delivery__c = estimate;
        shipment.Last_Location__c = LAST_LOCATION;
        shipment.Price__c = PRICE;
        shipment.Carrier_Cost__c = CARRIER_COST;
        shipment.Internal_Notes__c = INTERNAL_NOTE;
    }

    private static List<Shipment__c> setupShipments() {
        return [
            SELECT Id, Name, Account__c, Customer_Reference__c, Last_Update__c, Delivery_Access_Code_Hash__c,
                Recipient_Name__c, Recipient_Address__c, Recipient_Phone__c, Recipient_Email__c
            FROM Shipment__c WITH SYSTEM_MODE ORDER BY Name
        ];
    }

    private static Shipment__c shipmentUpdatedAt(Datetime lastUpdate) {
        return [SELECT Id, Name FROM Shipment__c WHERE Last_Update__c = :lastUpdate WITH SYSTEM_MODE LIMIT 1];
    }

    private static List<String> namesOf(List<Shipment__c> shipments) {
        List<String> names = new List<String>();
        for (Shipment__c shipment : shipments) {
            names.add(shipment.Name);
        }
        return names;
    }

    private static List<String> trackingNumbersOf(PublicTrackingResult result) {
        List<String> names = new List<String>();
        for (PublicTrackingResult.TrackedShipment shipment : result.results) {
            names.add(shipment.trackingNumber);
        }
        return names;
    }

    private static List<Shipment__c> insertShipmentsWithReference(String reference, Integer count) {
        Id customerId = [SELECT Id FROM Account WITH SYSTEM_MODE LIMIT 1].Id;
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId, count);
        for (Shipment__c shipment : shipments) {
            shipment.Customer_Reference__c = reference;
        }
        insertAsSystem(shipments);
        return [SELECT Name FROM Shipment__c WHERE Customer_Reference__c = :reference WITH SYSTEM_MODE ORDER BY Name];
    }

    // Calls search, expects an AuraHandledException with the given message, and
    // proves that no SOQL query ran.
    private static void assertRejectedWithoutQuery(String mode, List<String> values, String expectedMessage) {
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        try {
            PublicTrackingController.search(mode, values);
            Assert.fail('search must throw an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.areEqual(expectedMessage, e.getMessage(), 'The caller must get only the generic message');
        }
        Assert.areEqual(queriesBefore, Limits.getQueries(), 'A rejected search must not run any query');
        Test.stopTest();
    }

    // ─── AC-001.1 (server) ────────────────────────────────────────────────

    @IsTest
    static void search_trackingValuesSplitOnCommas_returnsThreeResults() {
        List<String> names = namesOf(setupShipments());
        List<String> values = new List<String>{ names[4] + ', ' + names[5], names[6] };
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, values);
        Test.stopTest();
        Assert.areEqual(new List<String>{ names[4], names[5], names[6] }, trackingNumbersOf(result),
            'The three tracking numbers A, B and C must be found, ordered by tracking number');
        Assert.areEqual(0, result.notFound.size(), 'Every value was found');
    }

    @IsTest
    static void search_reference_returnsThatShipment() {
        Shipment__c first = shipmentUpdatedAt(FIRST_UPDATE);
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(REFERENCE_MODE, new List<String>{ REFERENCE });
        Test.stopTest();
        Assert.areEqual(new List<String>{ first.Name }, trackingNumbersOf(result),
            'The shipment with reference PO-7781 must be returned');
    }

    @IsTest
    static void search_sharedReference_returnsEveryShipmentWithIt() {
        List<String> names = namesOf(setupShipments());
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(REFERENCE_MODE, new List<String>{ SHARED_REFERENCE });
        Test.stopTest();
        Assert.areEqual(new List<String>{ names[2], names[3] }, trackingNumbersOf(result),
            'Both shipments with reference PO-9902 must be returned (C2)');
    }

    @IsTest
    static void search_exactlyTenDistinctValues_areAccepted() {
        List<String> names = namesOf(setupShipments());
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, names);
        Test.stopTest();
        Assert.areEqual(names, trackingNumbersOf(result), 'All 10 values must be searched and found');
    }

    @IsTest
    static void search_elevenDistinctValues_isRejectedWithoutQuery() {
        List<String> values = namesOf(setupShipments());
        values.add(NO_MATCH_TRACKING);
        assertRejectedWithoutQuery(TRACKING, values, COUNT_MESSAGE);
    }

    @IsTest
    static void search_moreThanHundredRawEntries_isRejectedWithoutQuery() {
        String name = setupShipments()[0].Name;
        List<String> values = new List<String>();
        for (Integer i = 0; i < 101; i++) {
            values.add(name);
        }
        assertRejectedWithoutQuery(TRACKING, values, COUNT_MESSAGE);
    }

    @IsTest
    static void search_exactlyHundredRawEntries_areAccepted() {
        List<String> names = namesOf(setupShipments());
        List<String> values = new List<String>();
        for (Integer i = 0; i < MAX_RAW_ENTRIES; i++) {
            values.add(names[Math.mod(i, names.size())]);
        }
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, values);
        Test.stopTest();
        Assert.areEqual(names, trackingNumbersOf(result), '100 raw entries holding 10 distinct values must be accepted');
    }

    @IsTest
    static void search_entryAtLengthBound_isAccepted() {
        List<String> names = namesOf(setupShipments());
        String entry = String.join(names, ', ').rightPad(MAX_ENTRY_LENGTH);
        Assert.areEqual(MAX_ENTRY_LENGTH, entry.length(), 'The entry must be exactly at the bound');
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, new List<String>{ entry });
        Test.stopTest();
        Assert.areEqual(names, trackingNumbersOf(result), 'An entry of 520 characters with 10 values must be accepted');
    }

    @IsTest
    static void search_entryLongerThanBound_isRejectedWithoutQuery() {
        String entry = 'a,'.repeat(MAX_ENTRY_LENGTH / 2) + 'a';
        Assert.areEqual(MAX_ENTRY_LENGTH + 1, entry.length(), 'The entry must be one character over the bound');
        assertRejectedWithoutQuery(REFERENCE_MODE, new List<String>{ entry }, GENERIC_MESSAGE);
    }

    @IsTest
    static void search_hugeEntryOfDuplicates_isRejectedWithoutQuery() {
        // One entry that splits into 500,000 copies of the same value: before
        // the bound, split() ran over all of it before any count check.
        String entry = 'a,'.repeat(HUGE_ENTRY_PAIRS);
        assertRejectedWithoutQuery(REFERENCE_MODE, new List<String>{ entry }, GENERIC_MESSAGE);
    }

    @IsTest
    static void search_modeName_isRejectedWithoutQuery() {
        assertRejectedWithoutQuery('Name', new List<String>{ setupShipments()[0].Name }, GENERIC_MESSAGE);
    }

    @IsTest
    static void search_modePriceField_isRejectedWithoutQuery() {
        assertRejectedWithoutQuery('Price__c', new List<String>{ setupShipments()[0].Name }, GENERIC_MESSAGE);
    }

    @IsTest
    static void search_unexpectedException_givesOnlyTheGenericMessage() {
        String name = setupShipments()[0].Name;
        PublicTrackingController.failForTest = true;
        Test.startTest();
        try {
            PublicTrackingController.search(TRACKING, new List<String>{ name });
            Assert.fail('search must throw an AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.areEqual(GENERIC_MESSAGE, e.getMessage(), 'No exception text may reach the caller (X7)');
        }
        Test.stopTest();
    }

    // ─── AC-001.2 (BR-01, BR-03, BR-06) ──────────────────────────────────

    @IsTest
    static void search_eachResult_hasExactlyTheBr01Keys() {
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(REFERENCE_MODE, new List<String>{ REFERENCE });
        Test.stopTest();
        Assert.areEqual(1, result.results.size(), 'PO-7781 must return exactly one result to inspect');
        Map<String, Object> serialized = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(result.results[0]));
        Assert.areEqual(BR01_KEYS, serialized.keySet(), 'A result must have exactly the seven BR-01 keys');
    }

    @IsTest
    static void search_response_hasOnlyResultsNotFoundAndTruncated() {
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(REFERENCE_MODE, new List<String>{ REFERENCE });
        Test.stopTest();
        Map<String, Object> serialized = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(result));
        Assert.areEqual(new Set<String>{ 'results', 'notFound', 'truncated' }, serialized.keySet(),
            'The response must not carry any other key, such as a reason for a miss (P4)');
    }

    @IsTest
    static void search_lastUpdate_isFormattedInMexicoCity() {
        Shipment__c first = shipmentUpdatedAt(FIRST_UPDATE);
        Shipment__c second = shipmentUpdatedAt(SECOND_UPDATE);
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, new List<String>{ first.Name, second.Name });
        Test.stopTest();
        Assert.areEqual(2, result.results.size(), 'Both shipments must be returned before their dates are checked');
        Assert.areEqual('2026-11-20 10:00', result.results[0].lastUpdate, '16:00 UTC is 10:00 in Mexico City');
        Assert.areEqual('2026-11-20 21:00', result.results[1].lastUpdate,
            '03:00 UTC on the 21st is 21:00 on the 20th in Mexico City');
    }

    @IsTest
    static void search_estimatedDelivery_isTheIsoDate() {
        Shipment__c first = shipmentUpdatedAt(FIRST_UPDATE);
        Shipment__c second = shipmentUpdatedAt(SECOND_UPDATE);
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, new List<String>{ first.Name, second.Name });
        Test.stopTest();
        Assert.areEqual(2, result.results.size(), 'Both shipments must be returned before their estimates are checked');
        Assert.areEqual('2026-11-25', result.results[0].estimatedDelivery, 'First shipment estimate as ISO date');
        Assert.areEqual('2026-11-21', result.results[1].estimatedDelivery, 'Second shipment estimate as ISO date');
        Assert.areEqual(LAST_LOCATION, result.results[0].lastLocation, 'The last location is public (BR-01)');
    }

    @IsTest
    static void search_response_containsNoPrivateValueAndNoId() {
        List<Shipment__c> shipments = setupShipments();
        List<String> searched = new List<String>{ shipments[0].Name, shipments[1].Name };
        Test.startTest();
        String serialized = JSON.serialize(PublicTrackingController.search(TRACKING, searched));
        Test.stopTest();
        Assert.isTrue(serialized.contains(searched[0]) && serialized.contains(searched[1]),
            'Both shipments must be in the response, so the checks below are not vacuous');
        Set<String> privateValues = new Set<String>{ String.valueOf(PRICE), String.valueOf(CARRIER_COST), INTERNAL_NOTE };
        for (Shipment__c shipment : new List<Shipment__c>{ shipments[0], shipments[1] }) {
            privateValues.addAll(new List<String>{
                shipment.Recipient_Name__c, shipment.Recipient_Address__c, shipment.Recipient_Phone__c,
                shipment.Recipient_Email__c, shipment.Delivery_Access_Code_Hash__c,
                String.valueOf(shipment.Account__c).left(15), String.valueOf(shipment.Id).left(15)
            });
        }
        for (String privateValue : privateValues) {
            Assert.isFalse(serialized.contains(privateValue), 'The response must not contain ' + privateValue);
        }
    }

    // ─── AC-001.3 (P4, server) ────────────────────────────────────────────

    @IsTest
    static void search_misses_areListedOnceInInputOrder() {
        String found = setupShipments()[4].Name;
        List<String> values = new List<String>{ NO_MATCH_TRACKING, found, 'ABC', 'RC12', LONG_VALUE, 'abc' };
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, values);
        Test.stopTest();
        Assert.areEqual(new List<String>{ found }, trackingNumbersOf(result), 'The found value must be in results');
        Assert.areEqual(new List<String>{ NO_MATCH_TRACKING, 'ABC', 'RC12', LONG_VALUE }, result.notFound,
            'Each miss must appear once, in input order, whatever the reason');
        Assert.isFalse(result.truncated, 'Two rows are not truncated');
    }

    @IsTest
    static void search_onlyInvalidTrackingFormats_runsNoQuery() {
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, new List<String>{ 'ABC', 'RC12' });
        Integer queriesRun = Limits.getQueries() - queriesBefore;
        Test.stopTest();
        Assert.areEqual(0, queriesRun, 'Values not matching ^RC\\d{9}$ must not be queried');
        Assert.areEqual(new List<String>{ 'ABC', 'RC12' }, result.notFound, 'Both values are not found');
    }

    @IsTest
    static void search_referenceLongerThanFifty_runsNoQuery() {
        String longReference = 'PO-' + 'X'.repeat(48);
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        PublicTrackingResult result = PublicTrackingController.search(REFERENCE_MODE, new List<String>{ longReference });
        Integer queriesRun = Limits.getQueries() - queriesBefore;
        Test.stopTest();
        Assert.areEqual(0, queriesRun, 'A value longer than 50 characters must not be queried');
        Assert.areEqual(new List<String>{ longReference }, result.notFound, 'The long value is not found');
    }

    @IsTest
    static void search_moreThanFiftyRows_returnsFiftyTruncatedAndNoMisses() {
        List<String> names = namesOf(insertShipmentsWithReference(BULK_REFERENCE, BULK_SIZE));
        List<String> firstFifty = new List<String>();
        for (Integer i = 0; i < RESULT_CAP; i++) {
            firstFifty.add(names[i]);
        }
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(
            REFERENCE_MODE, new List<String>{ BULK_REFERENCE, NO_MATCH_REFERENCE });
        Test.stopTest();
        Assert.areEqual(firstFifty, trackingNumbersOf(result), 'The first 50 of 251 matches must be returned');
        Assert.isTrue(result.truncated, '251 matches exceed the 50-row cap');
        Assert.areEqual(0, result.notFound.size(), 'A truncated search proves no value missing');
    }

    @IsTest
    static void search_exactlyFiftyRows_isNotTruncated() {
        List<String> names = namesOf(insertShipmentsWithReference(BOUNDARY_REFERENCE, RESULT_CAP));
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(
            REFERENCE_MODE, new List<String>{ BOUNDARY_REFERENCE, NO_MATCH_REFERENCE });
        Test.stopTest();
        Assert.areEqual(names, trackingNumbersOf(result), 'All 50 matches must be returned');
        Assert.isFalse(result.truncated, '50 matches are within the cap');
        Assert.areEqual(new List<String>{ NO_MATCH_REFERENCE }, result.notFound, 'The miss must be listed');
    }

    // ─── AC-001.5 ─────────────────────────────────────────────────────────

    @IsTest
    static void search_trackingSpellings_findTheShipmentOnce() {
        String name = setupShipments()[4].Name;
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(
            TRACKING, new List<String>{ ' ' + name.toLowerCase() + ' ', name });
        Test.stopTest();
        Assert.areEqual(new List<String>{ name }, trackingNumbersOf(result), 'Both spellings find A once');
        Assert.areEqual(0, result.notFound.size(), 'Nothing is missing');
    }

    @IsTest
    static void search_referenceSpellings_findTheShipmentOnce() {
        Shipment__c first = shipmentUpdatedAt(FIRST_UPDATE);
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(
            REFERENCE_MODE, new List<String>{ ' po-7781 ', REFERENCE });
        Test.stopTest();
        Assert.areEqual(new List<String>{ first.Name }, trackingNumbersOf(result), 'PO-7781 is found once');
        Assert.areEqual(0, result.notFound.size(), 'Nothing is missing');
    }

    @IsTest
    static void search_duplicateSpelling_countsOnceTowardTheTen() {
        List<String> values = namesOf(setupShipments());
        List<String> expected = values.clone();
        values.add(' ' + values[0].toLowerCase());
        Test.startTest();
        PublicTrackingResult result = PublicTrackingController.search(TRACKING, values);
        Test.stopTest();
        Assert.areEqual(expected, trackingNumbersOf(result), '11 entries with one duplicate are 10 values');
    }

    @IsTest
    static void search_blankValues_returnEmptyWithoutQuery() {
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        PublicTrackingResult result = PublicTrackingController.search(REFERENCE_MODE, new List<String>{ ' ', '', null });
        Integer queriesRun = Limits.getQueries() - queriesBefore;
        Test.stopTest();
        Assert.areEqual(0, queriesRun, 'Blank values must not be queried');
        Assert.areEqual(0, result.results.size() + result.notFound.size(), 'Blank values are dropped');
    }

    // ─── AC-001.6 (P1, P2, P3, P10, P11) ──────────────────────────────────

    @IsTest
    static void siteGuest_cannotReadShipmentsItself() {
        User guest = TestDataFactory.siteGuestUser();
        Integer visible;
        Boolean accessible;
        Test.startTest();
        System.runAs(guest) {
            visible = [SELECT COUNT() FROM Shipment__c WITH SYSTEM_MODE];
            accessible = Schema.SObjectType.Shipment__c.isAccessible();
        }
        Test.stopTest();
        Assert.areEqual(0, visible, 'No shipment is shared with the guest');
        Assert.isFalse(accessible, 'The guest has no object permission on Shipment__c');
    }

    @IsTest
    static void siteGuest_search_returnsTheBr01Results() {
        User guest = TestDataFactory.siteGuestUser();
        Shipment__c first = shipmentUpdatedAt(FIRST_UPDATE);
        Shipment__c second = shipmentUpdatedAt(SECOND_UPDATE);
        PublicTrackingResult result;
        Test.startTest();
        System.runAs(guest) {
            result = PublicTrackingController.search(TRACKING, new List<String>{ first.Name, second.Name });
        }
        Test.stopTest();
        Assert.areEqual(new List<String>{ first.Name, second.Name }, trackingNumbersOf(result),
            'The guest must get both shipments through the controller');
        Assert.areEqual('Requested', result.results[0].status, 'The guest gets the status');
        Assert.areEqual('2026-11-20 21:00', result.results[1].lastUpdate, 'The guest gets Mexico City dates');
    }
}
