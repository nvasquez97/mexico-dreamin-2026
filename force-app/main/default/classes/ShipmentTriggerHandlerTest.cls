/**
 * @description Proves the Shipment__c trigger and ShipmentTriggerHandler: the
 *              delivery access code issued on insert (stored only as a salted
 *              hash), the Requested status on insert, the protection of the hash
 *              and of the original estimated delivery on update, and the capture
 *              of the original estimated delivery.
 *              Covers AC-F.4, AC-F.15, AC-F.13 and AC-F.5 of odd/tasks/foundation.md.
 */
@IsTest
private with sharing class ShipmentTriggerHandlerTest {

    private static final Integer BULK_SIZE = 251;
    private static final Integer CALLER_HASH_INDEX = 250;
    private static final String CALLER_HASH = 'caller-chosen-hash-value';
    private static final Pattern CODE_FORMAT = Pattern.compile('^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{10}$');
    private static final Pattern STORED_HASH_FORMAT = Pattern.compile('^[A-Za-z0-9+/]{22}==\\$[A-Za-z0-9+/]{43}=$');
    private static final Date FIRST_ESTIMATE = Date.newInstance(2026, 12, 1);
    private static final Date SECOND_ESTIMATE = Date.newInstance(2026, 12, 9);
    private static final Date LATER_ESTIMATE = Date.newInstance(2026, 12, 20);
    private static final Date OTHER_LATER_ESTIMATE = Date.newInstance(2026, 12, 27);

    // SECURITY-JUSTIFICATION: this class proves trigger behavior, not access. At
    // API 67 DML and SOQL default to user mode and the field permissions arrive
    // with the permission sets of task T3, so test-only DML and SOQL here run in
    // system mode. Scope: this test class only. Compensating control: access is
    // proven with System.runAs in the T3 access tests. (pending owner approval, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    private static void updateAsSystem(List<SObject> records) {
        Database.update(records, AccessLevel.SYSTEM_MODE);
    }

    private static Map<Id, Shipment__c> readBack(List<Shipment__c> shipments) {
        return new Map<Id, Shipment__c>([
            SELECT Id, Status__c, Delivery_Access_Code_Hash__c, Estimated_Delivery__c, Original_Estimated_Delivery__c
            FROM Shipment__c
            WHERE Id IN :shipments
            WITH SYSTEM_MODE
        ]);
    }

    @TestSetup
    static void setup() {
        insertAsSystem(new List<Account>{ TestDataFactory.newCustomerAccount() });
    }

    private static Id customerId() {
        return [SELECT Id FROM Account WHERE Name = :TestDataFactory.DEFAULT_ACCOUNT_NAME WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static List<Shipment__c> newShipmentsWithEstimates(List<Date> estimates) {
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), estimates.size());
        for (Integer i = 0; i < estimates.size(); i++) {
            shipments[i].Estimated_Delivery__c = estimates[i];
        }
        return shipments;
    }

    // ─── AC-F.4 (D1, X8, X16) ─────────────────────────────────────────────

    private static List<Shipment__c> newBulkShipmentsWithOneCallerHash() {
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), BULK_SIZE);
        shipments[CALLER_HASH_INDEX].Delivery_Access_Code_Hash__c = CALLER_HASH;
        return shipments;
    }

    @IsTest
    static void issuedCodes_are251DistinctCodesFromTheAlphabet_whenInsertedInOneDml() {
        // AC-F.4: the 251 clear codes returned to the inserting transaction are
        // 10 characters from ABCDEFGHJKMNPQRSTUVWXYZ23456789 and all distinct
        List<Shipment__c> shipments = newBulkShipmentsWithOneCallerHash();

        Test.startTest();
        insertAsSystem(shipments);
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();
        Test.stopTest();

        Assert.areEqual(BULK_SIZE, codes.size(), 'One clear code must be returned per inserted shipment');
        for (Integer i = 0; i < codes.size(); i++) {
            Assert.isTrue(codes[i] != null && CODE_FORMAT.matcher(codes[i]).matches(),
                'Code at position ' + i + ' must be 10 characters from the alphabet');
        }
        Assert.areEqual(BULK_SIZE, new Set<String>(codes).size(), 'All 251 codes must be distinct');
    }

    @IsTest
    static void everyShipment_storesASaltedHashAndReplacesTheCallerValue_whenInsertedInOneDml() {
        // AC-F.4: every shipment has a salted hash and the caller's value was replaced
        List<Shipment__c> shipments = newBulkShipmentsWithOneCallerHash();

        Test.startTest();
        insertAsSystem(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Set<String> hashes = new Set<String>();
        for (Integer i = 0; i < shipments.size(); i++) {
            String hash = saved.get(shipments[i].Id).Delivery_Access_Code_Hash__c;
            Assert.isTrue(hash != null && STORED_HASH_FORMAT.matcher(hash).matches(),
                'Shipment at position ' + i + ' must store <base64 salt>$<base64 SHA-256>, got: ' + hash);
            hashes.add(hash);
        }
        Assert.areNotEqual(CALLER_HASH, saved.get(shipments[CALLER_HASH_INDEX].Id).Delivery_Access_Code_Hash__c,
            'The hash value sent by the caller must be replaced');
        Assert.areEqual(BULK_SIZE, hashes.size(), 'Every shipment must have its own salted hash');
    }

    @IsTest
    static void noShipment_storesItsClearCode_whenInsertedInOneDml() {
        // AC-F.4: no record stores a clear code (every text field of every record is checked)
        List<Shipment__c> shipments = newBulkShipmentsWithOneCallerHash();

        Test.startTest();
        insertAsSystem(shipments);
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();
        Test.stopTest();

        Assert.areEqual(BULK_SIZE, codes.size(), 'One clear code must be returned per inserted shipment');
        Map<Id, SObject> saved = new Map<Id, SObject>(readAllTextFields(shipments));
        for (Integer i = 0; i < shipments.size(); i++) {
            Map<String, Object> values = saved.get(shipments[i].Id).getPopulatedFieldsAsMap();
            for (String fieldName : values.keySet()) {
                Object value = values.get(fieldName);
                Assert.isFalse(value instanceof String && ((String) value).toUpperCase().contains(codes[i]),
                    'Shipment at position ' + i + ' stores its clear code in ' + fieldName);
            }
        }
    }

    private static List<SObject> readAllTextFields(List<Shipment__c> shipments) {
        List<String> fieldNames = new List<String>();
        for (Schema.SObjectField field : Schema.SObjectType.Shipment__c.fields.getMap().values()) {
            if (field.getDescribe().getSoapType() == Schema.SoapType.STRING) {
                fieldNames.add(field.getDescribe().getName());
            }
        }
        String query = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM Shipment__c WHERE Id IN :shipments';
        return Database.queryWithBinds(query, new Map<String, Object>{ 'shipments' => shipments }, AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void matches_acceptsOwnCodeAndRejectsAnotherShipmentsCode_whenInsertedInOneDml() {
        // AC-F.4: DeliveryAccessCode.matches accepts each shipment's own code and
        // rejects another shipment's code
        List<Shipment__c> shipments = newBulkShipmentsWithOneCallerHash();

        Test.startTest();
        insertAsSystem(shipments);
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();
        Test.stopTest();

        Assert.areEqual(BULK_SIZE, codes.size(), 'One clear code must be returned per inserted shipment');
        Map<Id, Shipment__c> saved = readBack(shipments);
        for (Integer i = 0; i < shipments.size(); i++) {
            Shipment__c shipment = saved.get(shipments[i].Id);
            String otherCode = codes[Math.mod(i + 1, BULK_SIZE)];
            Assert.isTrue(DeliveryAccessCode.matches(shipment, codes[i]),
                'Shipment at position ' + i + ' must accept its own code');
            Assert.isFalse(DeliveryAccessCode.matches(shipment, otherCode),
                'Shipment at position ' + i + ' must reject the code of another shipment');
        }
    }

    @IsTest
    static void issuedCodes_holdOnlyTheLastInsert_whenASecondInsertFollowsAFullChunk() {
        // AC-F.4 (decided contract): the codes are aligned with the last insert
        // call; a new insert after a full 200-record chunk starts a new list
        List<Shipment__c> firstInsert = TestDataFactory.newShipments(customerId(), 200);
        List<Shipment__c> secondInsert = TestDataFactory.newShipments(customerId(), 3);

        Test.startTest();
        insertAsSystem(firstInsert);
        Integer firstCount = DeliveryAccessCode.lastIssuedCodes().size();
        insertAsSystem(secondInsert);
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();
        Test.stopTest();

        Assert.areEqual(200, firstCount, 'The first insert must return its 200 codes');
        Assert.areEqual(3, codes.size(), 'The second insert must return only its own 3 codes');
        Map<Id, Shipment__c> saved = readBack(secondInsert);
        for (Integer i = 0; i < secondInsert.size(); i++) {
            Assert.isTrue(DeliveryAccessCode.matches(saved.get(secondInsert[i].Id), codes[i]),
                'Code at position ' + i + ' must belong to the shipment at the same position of the second insert');
        }
    }

    // ─── AC-F.15 (BR-09) ──────────────────────────────────────────────────

    @IsTest
    static void status_isRequested_whenInsertedAsDeliveredOrInTransit() {
        // AC-F.15: shipments inserted with Status__c Delivered and In transit are
        // read back as Requested (251 records, across the 200-record batch boundary)
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), BULK_SIZE);
        for (Integer i = 0; i < shipments.size(); i++) {
            shipments[i].Status__c = Math.mod(i, 2) == 0 ? 'Delivered' : 'In transit';
        }

        Test.startTest();
        insertAsSystem(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Assert.areEqual(BULK_SIZE, saved.size(), 'All 251 shipments must be saved');
        for (Integer i = 0; i < shipments.size(); i++) {
            Assert.areEqual('Requested', saved.get(shipments[i].Id).Status__c,
                'A shipment inserted as ' + shipments[i].Status__c + ' must start as Requested');
        }
    }

    // ─── AC-F.13 (D1, D4) ─────────────────────────────────────────────────

    @IsTest
    static void accessCodeHash_keepsItsValue_whenAnUpdateSetsANewOne() {
        // AC-F.13: an update that sets a new Delivery_Access_Code_Hash__c keeps the previous value
        List<Shipment__c> shipments = newShipmentsWithEstimates(new List<Date>{ FIRST_ESTIMATE, SECOND_ESTIMATE });
        insertAsSystem(shipments);
        Map<Id, Shipment__c> before = readBack(shipments);
        List<Shipment__c> changes = new List<Shipment__c>{
            new Shipment__c(Id = shipments[0].Id, Delivery_Access_Code_Hash__c = 'new-hash-from-caller-a'),
            new Shipment__c(Id = shipments[1].Id, Delivery_Access_Code_Hash__c = 'new-hash-from-caller-b')
        };

        Test.startTest();
        updateAsSystem(changes);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        for (Shipment__c shipment : shipments) {
            Assert.areEqual(before.get(shipment.Id).Delivery_Access_Code_Hash__c,
                saved.get(shipment.Id).Delivery_Access_Code_Hash__c,
                'An update must not change the stored access code hash');
        }
    }

    @IsTest
    static void originalEstimate_keepsItsValue_whenAnUpdateSetsANewOne() {
        // AC-F.13: an update that sets a new Original_Estimated_Delivery__c keeps the previous value
        List<Shipment__c> shipments = newShipmentsWithEstimates(new List<Date>{ FIRST_ESTIMATE, SECOND_ESTIMATE });
        insertAsSystem(shipments);
        List<Shipment__c> changes = new List<Shipment__c>{
            new Shipment__c(Id = shipments[0].Id, Original_Estimated_Delivery__c = LATER_ESTIMATE),
            new Shipment__c(Id = shipments[1].Id, Original_Estimated_Delivery__c = OTHER_LATER_ESTIMATE)
        };

        Test.startTest();
        updateAsSystem(changes);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Assert.areEqual(FIRST_ESTIMATE, saved.get(shipments[0].Id).Original_Estimated_Delivery__c,
            'An update must not change an original estimated delivery of 2026-12-01');
        Assert.areEqual(SECOND_ESTIMATE, saved.get(shipments[1].Id).Original_Estimated_Delivery__c,
            'An update must not change an original estimated delivery of 2026-12-09');
    }

    // ─── AC-F.5 (D4, AC-003.2) ────────────────────────────────────────────

    @IsTest
    static void originalEstimate_equalsTheEstimate_whenInserted() {
        // AC-F.5: shipments inserted with Estimated_Delivery__c 2026-12-01 and
        // 2026-12-09 get Original_Estimated_Delivery__c equal to each date
        List<Shipment__c> shipments = newShipmentsWithEstimates(new List<Date>{ FIRST_ESTIMATE, SECOND_ESTIMATE });

        Test.startTest();
        insertAsSystem(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Assert.areEqual(FIRST_ESTIMATE, saved.get(shipments[0].Id).Original_Estimated_Delivery__c,
            'Original estimate must be 2026-12-01');
        Assert.areEqual(SECOND_ESTIMATE, saved.get(shipments[1].Id).Original_Estimated_Delivery__c,
            'Original estimate must be 2026-12-09');
    }

    @IsTest
    static void originalEstimate_keepsTheFirstDate_whenTheEstimateIsUpdated() {
        // AC-F.5: when Estimated_Delivery__c is later updated, the original keeps
        // the first date (251 records, across the 200-record batch boundary)
        List<Date> estimates = new List<Date>();
        for (Integer i = 0; i < BULK_SIZE; i++) {
            estimates.add(Math.mod(i, 2) == 0 ? FIRST_ESTIMATE : SECOND_ESTIMATE);
        }
        List<Shipment__c> shipments = newShipmentsWithEstimates(estimates);
        insertAsSystem(shipments);
        for (Shipment__c shipment : shipments) {
            shipment.Estimated_Delivery__c = LATER_ESTIMATE;
        }

        Test.startTest();
        updateAsSystem(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        for (Integer i = 0; i < shipments.size(); i++) {
            Shipment__c shipment = saved.get(shipments[i].Id);
            Assert.areEqual(LATER_ESTIMATE, shipment.Estimated_Delivery__c, 'The estimate update must be saved');
            Assert.areEqual(estimates[i], shipment.Original_Estimated_Delivery__c,
                'Original estimate at position ' + i + ' must keep the first date');
        }
    }

    @IsTest
    static void originalEstimate_takesTheFirstEstimate_whenInsertedWithoutOne() {
        // AC-F.5: a shipment inserted without an estimate takes the estimate first
        // set by an update as its original estimate
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), 2);
        insertAsSystem(shipments);
        Map<Id, Shipment__c> inserted = readBack(shipments);
        Assert.isNull(inserted.get(shipments[0].Id).Original_Estimated_Delivery__c,
            'A shipment without an estimate must have no original estimate');
        shipments[0].Estimated_Delivery__c = FIRST_ESTIMATE;
        shipments[1].Estimated_Delivery__c = SECOND_ESTIMATE;

        Test.startTest();
        updateAsSystem(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Assert.areEqual(FIRST_ESTIMATE, saved.get(shipments[0].Id).Original_Estimated_Delivery__c,
            'Original estimate must take the first estimate 2026-12-01');
        Assert.areEqual(SECOND_ESTIMATE, saved.get(shipments[1].Id).Original_Estimated_Delivery__c,
            'Original estimate must take the first estimate 2026-12-09');
    }

    @IsTest
    static void originalEstimate_staysBlank_whenAnUpdateSetsItWithoutAnEstimate() {
        // AC-F.5 / AC-F.13 (assumption): while there is no estimate, the original
        // estimate is derived only from Estimated_Delivery__c, never set by the caller
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), 2);
        insertAsSystem(shipments);
        shipments[0].Original_Estimated_Delivery__c = LATER_ESTIMATE;
        shipments[1].Original_Estimated_Delivery__c = OTHER_LATER_ESTIMATE;

        Test.startTest();
        updateAsSystem(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Assert.isNull(saved.get(shipments[0].Id).Original_Estimated_Delivery__c,
            'A caller must not set the original estimate of a shipment without an estimate (2026-12-20)');
        Assert.isNull(saved.get(shipments[1].Id).Original_Estimated_Delivery__c,
            'A caller must not set the original estimate of a shipment without an estimate (2026-12-27)');
    }
}
