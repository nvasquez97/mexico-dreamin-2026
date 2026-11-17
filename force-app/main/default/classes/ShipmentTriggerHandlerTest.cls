/**
 * @description Proves the Shipment__c trigger and ShipmentTriggerHandler: the
 *              delivery access code issued on insert (stored only as an iterated
 *              salted hash, the clear code returned by Id only to
 *              DeliveryAccessCode.insertWithCodes), the Requested status on
 *              insert, the protection of the hash and of the original estimated
 *              delivery on update, and the capture of the original estimated
 *              delivery.
 *              Covers AC-F.4, AC-F.15, AC-F.13 and AC-F.5 of odd/tasks/foundation.md.
 */
@IsTest
private with sharing class ShipmentTriggerHandlerTest {

    private static final Integer BULK_SIZE = 251;
    private static final Integer CALLER_HASH_INDEX = 250;
    private static final String CALLER_HASH = 'caller-chosen-hash-value';
    private static final Integer INVALID_INDEX = 10;
    private static final Pattern CODE_FORMAT = Pattern.compile('^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$');
    private static final Pattern STORED_HASH_FORMAT =
        Pattern.compile('^v1\\$100\\$[A-Za-z0-9+/]{22}==\\$[A-Za-z0-9+/]{43}=$');
    private static final Date FIRST_ESTIMATE = Date.newInstance(2026, 12, 1);
    private static final Date SECOND_ESTIMATE = Date.newInstance(2026, 12, 9);
    private static final Date LATER_ESTIMATE = Date.newInstance(2026, 12, 20);
    private static final Date OTHER_LATER_ESTIMATE = Date.newInstance(2026, 12, 27);

    // The user that inserts through insertWithCodes (user mode): Minimum Access
    // plus a test-only permission set with Account read, Shipment__c read and
    // create, and read and edit on the optional Shipment__c fields. It owns its
    // own customer account.
    private static User creator;
    private static Id creatorCustomerId;

    // SECURITY-JUSTIFICATION: this class proves trigger behavior, not access. At
    // API 67 DML and SOQL default to user mode and the field permissions arrive
    // with the permission sets of task T3, so test-only DML and SOQL here run in
    // system mode. DeliveryAccessCode.insertWithCodes itself always runs in user
    // mode, as the test user of createShipmentCreator. Scope: this test class only. Compensating control: access is
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

    // ─── AC-F.4 (D1, X8, X16; CODE-001, CODE-002) ─────────────────────────

    private static List<Shipment__c> newBulkShipmentsWithOneCallerHash() {
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), BULK_SIZE);
        shipments[CALLER_HASH_INDEX].Delivery_Access_Code_Hash__c = CALLER_HASH;
        return shipments;
    }

    // The user that inserts through insertWithCodes (user mode): see createShipmentCreator.
    private static void createShipmentCreator() {
        creator = TestDataFactory.newUser(minimumAccessProfileId(), 'shipcrtr');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertAsSystem(new List<User>{ creator });
            PermissionSet permissionSet = new PermissionSet(Name = 'T2_Test_Shipment_Creator', Label = 'T2 Test Shipment Creator');
            insertAsSystem(new List<PermissionSet>{ permissionSet });
            insertAsSystem(new List<ObjectPermissions>{
                new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Account', PermissionsRead = true),
                new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'Shipment__c',
                    PermissionsRead = true, PermissionsCreate = true)
            });
            insertAsSystem(optionalShipmentFieldGrants(permissionSet.Id));
            insertAsSystem(new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = creator.Id, PermissionSetId = permissionSet.Id)
            });
        }
        Account customer = TestDataFactory.newCustomerAccount('Creator Customer');
        customer.OwnerId = creator.Id;
        insertAsSystem(new List<Account>{ customer });
        creatorCustomerId = customer.Id;
    }

    private static List<FieldPermissions> optionalShipmentFieldGrants(Id permissionSetId) {
        List<FieldPermissions> grants = new List<FieldPermissions>();
        for (Schema.SObjectField field : Schema.SObjectType.Shipment__c.fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.isCustom() && describe.isNillable() && !describe.isCalculated()) {
                grants.add(new FieldPermissions(ParentId = permissionSetId, SobjectType = 'Shipment__c',
                    Field = 'Shipment__c.' + describe.getName(), PermissionsRead = true, PermissionsEdit = true));
            }
        }
        return grants;
    }

    private static List<Shipment__c> newCreatorShipments(Integer count) {
        if (creator == null) {
            createShipmentCreator();
        }
        return TestDataFactory.newShipments(creatorCustomerId, count);
    }

    private static List<Shipment__c> newCreatorShipmentsWithOneCallerHash() {
        List<Shipment__c> shipments = newCreatorShipments(BULK_SIZE);
        shipments[CALLER_HASH_INDEX].Delivery_Access_Code_Hash__c = CALLER_HASH;
        return shipments;
    }

    private static Map<Id, String> insertWithCodesAsCreator(List<Shipment__c> shipments) {
        Map<Id, String> codes;
        System.runAs(creator) {
            codes = DeliveryAccessCode.insertWithCodes(shipments);
        }
        return codes;
    }

    @IsTest
    static void insertWithCodes_returnsOneDistinctAlphabetCodePerInsertedId() {
        // AC-F.4: the returned Map<Id,String> holds, for each of the 251 inserted Ids,
        // a 12-character code from ABCDEFGHJKMNPQRSTUVWXYZ23456789, all distinct
        List<Shipment__c> shipments = newCreatorShipmentsWithOneCallerHash();

        Test.startTest();
        Map<Id, String> codes = insertWithCodesAsCreator(shipments);
        Test.stopTest();

        Assert.areEqual(new Map<Id, Shipment__c>(shipments).keySet(), codes.keySet(),
            'The map must hold exactly the 251 inserted Ids');
        for (Integer i = 0; i < shipments.size(); i++) {
            String code = codes.get(shipments[i].Id);
            Assert.isTrue(code != null && CODE_FORMAT.matcher(code).matches(),
                'The code of the shipment at position ' + i + ' must be 12 characters from the alphabet');
        }
        Assert.areEqual(BULK_SIZE, new Set<String>(codes.values()).size(), 'All 251 codes must be distinct');
    }

    @IsTest
    static void insertWithCodes_storesAnIteratedSaltedHashAndReplacesTheCallerValue() {
        // AC-F.4: every shipment has a salted, iterated hash (v1$100$salt$hash) and
        // the caller's value was replaced
        List<Shipment__c> shipments = newCreatorShipmentsWithOneCallerHash();

        Test.startTest();
        insertWithCodesAsCreator(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Set<String> hashes = new Set<String>();
        for (Integer i = 0; i < shipments.size(); i++) {
            String hash = saved.get(shipments[i].Id).Delivery_Access_Code_Hash__c;
            Assert.isTrue(hash != null && STORED_HASH_FORMAT.matcher(hash).matches(),
                'Shipment at position ' + i + ' must store v1$100$<base64 salt>$<base64 hash>, got: ' + hash);
            hashes.add(hash);
        }
        Assert.areNotEqual(CALLER_HASH, saved.get(shipments[CALLER_HASH_INDEX].Id).Delivery_Access_Code_Hash__c,
            'The hash value sent by the caller must be replaced');
        Assert.areEqual(BULK_SIZE, hashes.size(), 'Every shipment must have its own salted hash');
    }

    @IsTest
    static void insertWithCodes_noRecordStoresItsClearCode() {
        // AC-F.4: no record stores a clear code (every text field of every record is checked)
        List<Shipment__c> shipments = newCreatorShipmentsWithOneCallerHash();

        Test.startTest();
        Map<Id, String> codes = insertWithCodesAsCreator(shipments);
        Test.stopTest();

        Assert.areEqual(BULK_SIZE, codes.size(), 'One clear code must be returned per inserted shipment');
        Map<Id, SObject> saved = new Map<Id, SObject>(readAllTextFields(shipments));
        for (Integer i = 0; i < shipments.size(); i++) {
            String code = codes.get(shipments[i].Id);
            Map<String, Object> values = saved.get(shipments[i].Id).getPopulatedFieldsAsMap();
            for (String fieldName : values.keySet()) {
                Object value = values.get(fieldName);
                Assert.isFalse(value instanceof String && ((String) value).toUpperCase().contains(code),
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
    static void matches_acceptsEachShipmentsOwnCodeAsTyped_whenInsertedWithCodes() {
        // AC-F.4: matches accepts each shipment's own code as returned, in lower
        // case and as XXXX-XXXX-XXXX (the three forms rotate over the 251 records)
        List<Shipment__c> shipments = newCreatorShipmentsWithOneCallerHash();

        Test.startTest();
        Map<Id, String> codes = insertWithCodesAsCreator(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        for (Integer i = 0; i < shipments.size(); i++) {
            String code = codes.get(shipments[i].Id);
            Assert.isTrue(DeliveryAccessCode.matches(saved.get(shipments[i].Id), typedForm(code, i)),
                'Shipment at position ' + i + ' must accept its own code typed in form ' + Math.mod(i, 3));
        }
    }

    // Form 0: as returned; form 1: lower case; form 2: grouped as xxxx-xxxx-xxxx in lower case.
    private static String typedForm(String code, Integer position) {
        Integer form = Math.mod(position, 3);
        if (form == 1) {
            return code.toLowerCase();
        }
        if (form == 2) {
            return (code.left(4) + '-' + code.mid(4, 4) + '-' + code.right(4)).toLowerCase();
        }
        return code;
    }

    @IsTest
    static void matches_rejectsAnotherShipmentsCode_whenInsertedWithCodes() {
        // AC-F.4: matches rejects another shipment's code
        List<Shipment__c> shipments = newCreatorShipmentsWithOneCallerHash();

        Test.startTest();
        Map<Id, String> codes = insertWithCodesAsCreator(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        for (Integer i = 0; i < shipments.size(); i++) {
            String otherCode = codes.get(shipments[Math.mod(i + 1, BULK_SIZE)].Id);
            Assert.isFalse(DeliveryAccessCode.matches(saved.get(shipments[i].Id), otherCode),
                'Shipment at position ' + i + ' must reject the code of another shipment');
        }
    }

    @IsTest
    static void insertWithCodes_returnsOnlyItsOwnRows_whenCalledTwice() {
        // AC-F.4 (CODE-002): each call returns the codes of its own rows, bound by Id
        List<Shipment__c> firstInsert = newCreatorShipments(200);
        List<Shipment__c> secondInsert = newCreatorShipments(3);

        Test.startTest();
        Map<Id, String> firstCodes = insertWithCodesAsCreator(firstInsert);
        Map<Id, String> secondCodes = insertWithCodesAsCreator(secondInsert);
        Test.stopTest();

        Assert.areEqual(new Map<Id, Shipment__c>(firstInsert).keySet(), firstCodes.keySet(),
            'The first call must return the codes of its 200 rows only');
        Assert.areEqual(new Map<Id, Shipment__c>(secondInsert).keySet(), secondCodes.keySet(),
            'The second call must return the codes of its 3 rows only');
        Map<Id, Shipment__c> saved = readBack(secondInsert);
        for (Integer i = 0; i < secondInsert.size(); i++) {
            Assert.isTrue(DeliveryAccessCode.matches(saved.get(secondInsert[i].Id), secondCodes.get(secondInsert[i].Id)),
                'The code returned for the shipment at position ' + i + ' must be its own');
        }
    }

    @IsTest
    static void insertWithCodes_keepsNoClearCodeInMemory_afterReturning() {
        // AC-F.4 (CODE-002): the codes are removed from memory once returned
        List<Shipment__c> shipments = newCreatorShipmentsWithOneCallerHash();

        Test.startTest();
        Map<Id, String> codes = insertWithCodesAsCreator(shipments);
        Test.stopTest();

        Assert.areEqual(BULK_SIZE, codes.size(), 'One clear code must be returned per inserted shipment');
        Assert.isTrue(DeliveryAccessCode.issuedCodesById.isEmpty(), 'No clear code may stay in memory by Id');
        Assert.isTrue(DeliveryAccessCode.pendingCodesByHash.isEmpty(), 'No clear code may stay pending');
    }

    @IsTest
    static void plainInsert_keepsNoClearCodeInMemory() {
        // AC-F.4 (CODE-002): rows inserted without insertWithCodes get a hash, and
        // their clear codes are discarded
        List<Shipment__c> shipments = newBulkShipmentsWithOneCallerHash();

        Test.startTest();
        insertAsSystem(shipments);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Assert.isTrue(STORED_HASH_FORMAT.matcher(saved.get(shipments[0].Id).Delivery_Access_Code_Hash__c).matches(),
            'A plainly inserted shipment must still get an iterated salted hash');
        Assert.isTrue(DeliveryAccessCode.issuedCodesById.isEmpty(), 'No clear code may be kept by Id');
        Assert.isTrue(DeliveryAccessCode.pendingCodesByHash.isEmpty(), 'No clear code may be kept pending');
    }

    @IsTest
    static void insertWithCodes_throwsAndKeepsNoClearCode_whenARowIsInvalid() {
        // AC-F.4 (CODE-002): insertWithCodes is all-or-none; a failure leaves no code in memory
        List<Shipment__c> shipments = newCreatorShipmentsWithOneCallerHash();
        shipments[INVALID_INDEX].Account__c = null;

        Test.startTest();
        try {
            insertWithCodesAsCreator(shipments);
            Assert.fail('An insert with a row without Account__c must throw');
        } catch (DmlException e) {
            Assert.areEqual(StatusCode.REQUIRED_FIELD_MISSING, e.getDmlType(0), 'The missing Account__c must fail the insert');
        }
        Test.stopTest();

        Assert.isTrue(DeliveryAccessCode.issuedCodesById.isEmpty(), 'No clear code may stay in memory by Id');
        Assert.isTrue(DeliveryAccessCode.pendingCodesByHash.isEmpty(), 'No clear code may stay pending');
    }

    @IsTest
    static void partialInsert_everySuccessfulRowsCodeMatchesItsRecord() {
        // AC-F.4 (CODE-002): Database.insert(rows, false) with one invalid row in the
        // first 200-record chunk: every successful row's code still matches its record
        List<Shipment__c> shipments = newBulkShipmentsWithOneCallerHash();
        shipments[INVALID_INDEX].Account__c = null;
        DeliveryAccessCode.captureForTest = true;

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(shipments, false, AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Assert.isFalse(results[INVALID_INDEX].isSuccess(), 'The row without Account__c must fail');
        List<Shipment__c> succeeded = new List<Shipment__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                succeeded.add(new Shipment__c(Id = results[i].getId()));
            }
        }
        Assert.areEqual(BULK_SIZE - 1, succeeded.size(), 'Every other row must be inserted');
        Map<Id, Shipment__c> saved = readBack(succeeded);
        for (Shipment__c shipment : succeeded) {
            String code = DeliveryAccessCode.issuedCodesById.get(shipment.Id);
            Assert.isTrue(code != null && DeliveryAccessCode.matches(saved.get(shipment.Id), code),
                'The code bound to a successful row must match that row');
        }
    }

    @IsTest
    static void insertWithCodes_throwsSecurityException_whenTheUserCannotCreateShipments() {
        // AC-F.4 (P10, no escalation): insertWithCodes runs in user mode, so a user
        // without access to Shipment__c cannot insert through it
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), 2);
        User noAccess = TestDataFactory.newUser(minimumAccessProfileId(), 'noaccess');
        insertAsSystem(new List<User>{ noAccess });

        Test.startTest();
        Boolean inserted = true;
        System.runAs(noAccess) {
            try {
                DeliveryAccessCode.insertWithCodes(shipments);
            } catch (System.SecurityException e) {
                inserted = false;
            }
        }
        Test.stopTest();

        Assert.isFalse(inserted, 'A user without Shipment__c access must not insert through insertWithCodes');
        Assert.isTrue(DeliveryAccessCode.issuedCodesById.isEmpty(), 'No clear code may stay in memory by Id');
    }

    private static Id minimumAccessProfileId() {
        return [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' WITH SYSTEM_MODE LIMIT 1].Id;
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
