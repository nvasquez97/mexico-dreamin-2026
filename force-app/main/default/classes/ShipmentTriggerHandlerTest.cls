/**
 * @description Proves the Shipment__c trigger and ShipmentTriggerHandler: the
 *              delivery access code issued on insert (stored only as an iterated
 *              salted hash, the clear code returned by Id only to
 *              DeliveryAccessCode.insertWithCodes), the Requested status on
 *              insert, the protection of the hash and of the original estimated
 *              delivery on update, and the capture of the original estimated
 *              delivery, and the hash replaced on update only for the Ids
 *              registered by DeliveryAccessCode.reissueCodes.
 *              Covers AC-F.4, AC-F.15, AC-F.13, AC-F.16 and AC-F.5 of
 *              odd/tasks/foundation.md, and AC-004.9 of
 *              odd/tasks/req-004-carrier-status.md: a direct update by a holder of
 *              RutaCargo_EntregaYa_Sender is refused on every row, a support
 *              agent's is applied (251 records each).
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
    private static final String DIRECT_SENDER_UPDATE_MESSAGE =
        'Status updates from EntregaYa must use the status service.';

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
    static void accessCodeHash_isReplacedOnlyForTheIdsOfAnActiveReissue() {
        // AC-F.16 / AC-F.13: in one 251-record update that sets a caller hash on
        // every row, only the Ids registered by an active reissue get a new salted
        // hash matching their new code; every other shipment keeps its hash
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), BULK_SIZE);
        insertAsSystem(shipments);
        Map<Id, Shipment__c> before = readBack(shipments);
        List<Shipment__c> changes = new List<Shipment__c>();
        Set<Id> registered = new Set<Id>();
        for (Integer i = 0; i < shipments.size(); i++) {
            changes.add(new Shipment__c(Id = shipments[i].Id, Delivery_Access_Code_Hash__c = CALLER_HASH));
            if (Math.mod(i, 2) == 0) {
                registered.add(shipments[i].Id);
            }
        }
        DeliveryAccessCode.reissuingIds.addAll(registered);

        Test.startTest();
        updateAsSystem(changes);
        Test.stopTest();

        Map<Id, Shipment__c> saved = readBack(shipments);
        Assert.areEqual(registered, DeliveryAccessCode.reissuedCodesById.keySet(), 'Only registered Ids get a new code');
        for (Shipment__c shipment : shipments) {
            Shipment__c row = saved.get(shipment.Id);
            if (registered.contains(shipment.Id)) {
                Assert.isTrue(STORED_HASH_FORMAT.matcher(row.Delivery_Access_Code_Hash__c).matches(),
                    'A registered shipment must store a v1$100$salt$hash value');
                Assert.areNotEqual(before.get(shipment.Id).Delivery_Access_Code_Hash__c, row.Delivery_Access_Code_Hash__c,
                    'A registered shipment must store a new hash, not its previous one');
                Assert.isTrue(DeliveryAccessCode.matches(row, DeliveryAccessCode.reissuedCodesById.get(shipment.Id)),
                    'The new hash of a registered shipment must match its new code');
            } else {
                Assert.areEqual(before.get(shipment.Id).Delivery_Access_Code_Hash__c, row.Delivery_Access_Code_Hash__c,
                    'A shipment not registered for reissue must keep its hash');
            }
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

    // ─── AC-004.9 (P4, BR-04, BR-09): direct updates by EntregaYa senders ─

    // 251 shipments shared Read/Write with the EntregaYa integration group and the
    // support agents group: manual shares mirror the two deployed rules (A10).
    private static List<Shipment__c> insertBulkSharedShipments() {
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), BULK_SIZE);
        insertAsSystem(shipments);
        TestDataFactory.insertShipmentGroupShares(shipments, TestDataFactory.ENTREGAYA_GROUP);
        TestDataFactory.insertShipmentGroupShares(shipments, TestDataFactory.AGENT_GROUP);
        return shipments;
    }

    // Even rows: In transit at Leon; odd rows: Out for delivery at Celaya.
    private static List<Shipment__c> statusChanges(List<Shipment__c> shipments) {
        List<Shipment__c> changes = new List<Shipment__c>();
        for (Integer i = 0; i < shipments.size(); i++) {
            Boolean even = Math.mod(i, 2) == 0;
            changes.add(new Shipment__c(Id = shipments[i].Id,
                Status__c = even ? 'In transit' : 'Out for delivery',
                Last_Location__c = even ? 'Leon, GTO' : 'Celaya, GTO'));
        }
        return changes;
    }

    private static List<Database.SaveResult> updateAs(User actor, List<Shipment__c> changes) {
        List<Database.SaveResult> results;
        System.runAs(actor) {
            results = Database.update(changes, false, AccessLevel.USER_MODE);
        }
        return results;
    }

    private static Map<Id, Shipment__c> readStatuses(List<Shipment__c> shipments) {
        return new Map<Id, Shipment__c>([
            SELECT Id, Status__c, Last_Location__c FROM Shipment__c WHERE Id IN :shipments WITH SYSTEM_MODE
        ]);
    }

    @IsTest
    static void directUpdate_isRefusedOnEveryRow_whenTheUserHoldsTheSenderPermission() {
        // AC-004.9: a 251-record direct update by the integration user (RutaCargo_EntregaYa_Sender)
        // is refused on every row with the generic message, and nothing changes
        User integration = TestDataFactory.insertEntregaYaIntegrationUser('rcthint');
        List<Shipment__c> shipments = insertBulkSharedShipments();
        List<Shipment__c> changes = statusChanges(shipments);

        Test.startTest();
        List<Database.SaveResult> results = updateAs(integration, changes);
        Test.stopTest();

        Integer refused = 0;
        for (Database.SaveResult result : results) {
            if (!result.isSuccess() && result.getErrors()[0].getMessage() == DIRECT_SENDER_UPDATE_MESSAGE) {
                refused++;
            }
        }
        Assert.areEqual(BULK_SIZE, refused, 'Every row must be refused with the generic message');
        for (Shipment__c saved : readStatuses(shipments).values()) {
            Assert.areEqual('Requested|null', saved.Status__c + '|' + saved.Last_Location__c,
                'A refused update must change nothing');
        }
    }

    @IsTest
    static void directUpdate_isApplied_whenASupportAgentEditsStatusesByHand() {
        // AC-004.9, BR-09: a 251-record status update by a support agent (no custom permission) is applied
        User agent = TestDataFactory.insertSupportAgent('rcthagt');
        List<Shipment__c> shipments = insertBulkSharedShipments();
        List<Shipment__c> changes = statusChanges(shipments);

        Test.startTest();
        List<Database.SaveResult> results = updateAs(agent, changes);
        Test.stopTest();

        Integer applied = 0;
        for (Database.SaveResult result : results) {
            applied += result.isSuccess() ? 1 : 0;
        }
        Assert.areEqual(BULK_SIZE, applied, 'Every row of the agent must be saved');
        Map<Id, Shipment__c> saved = readStatuses(shipments);
        for (Shipment__c change : changes) {
            Shipment__c row = saved.get(change.Id);
            Assert.areEqual(change.Status__c + '|' + change.Last_Location__c, row.Status__c + '|' + row.Last_Location__c,
                'The agent change must be saved');
        }
    }

    // ─── Customer inserts (req-006-007 S1, AC-006.5, AC-006.6) ────────────
    // A customer user (UserType not Standard) inserting a shipment directly (UI
    // API or DML) gets the same result as the request controller: the shipment
    // belongs to the user's own account, has the BR-08 price, the BR-06
    // estimate, Status Requested and no internal field; an invalid weight or
    // pickup date is a field error. "Today" is fixed by the rules' test seam.

    private static Id accountOf(String email) {
        return TestDataFactory.seededCustomerAccountId(email);
    }

    private static List<Shipment__c> newAttackShipments(Integer count, Id otherAccountId) {
        List<Shipment__c> shipments = TestDataFactory.newCustomerShipments(count);
        for (Shipment__c shipment : shipments) {
            shipment.Account__c = otherAccountId;
            shipment.Price__c = 1.00;
            shipment.Status__c = 'Delivered';
            shipment.Carrier_Cost__c = 90.00;
            shipment.Internal_Notes__c = 'customer-written note';
            shipment.Proof_Id__c = 'PROOF-1';
            shipment.Delivered_At__c = Datetime.newInstanceGmt(2026, 11, 20, 12, 0, 0);
            shipment.Last_Location__c = 'Nowhere';
            shipment.Last_Update__c = Datetime.newInstanceGmt(2026, 11, 20, 12, 0, 0);
            shipment.Reschedule_Count__c = 9;
            shipment.Estimated_Delivery__c = Date.newInstance(2026, 11, 21);
            shipment.Original_Estimated_Delivery__c = Date.newInstance(2026, 11, 21);
        }
        return shipments;
    }

    // The worst case of a direct create: every field written (system-mode DML
    // run as the customer, as if FLS allowed them all).
    private static void insertAsUserIgnoringFls(User actor, List<Shipment__c> shipments) {
        System.runAs(actor) {
            Database.insert(shipments, AccessLevel.SYSTEM_MODE);
        }
    }

    private static List<Shipment__c> readCustomerFields(List<Shipment__c> shipments) {
        return [
            SELECT Id, Account__c, Price__c, Status__c, Carrier_Cost__c, Internal_Notes__c, Proof_Id__c, Delivered_At__c,
                Last_Location__c, Last_Update__c, Reschedule_Count__c, Estimated_Delivery__c, Original_Estimated_Delivery__c
            FROM Shipment__c WHERE Id IN :shipments WITH SYSTEM_MODE
        ];
    }

    private static String guardedValues(Shipment__c row) {
        return row.Account__c + '|' + row.Price__c + '|' + row.Status__c + '|' + row.Carrier_Cost__c + '|'
            + row.Internal_Notes__c + '|' + row.Proof_Id__c + '|' + row.Delivered_At__c + '|' + row.Last_Location__c + '|'
            + row.Last_Update__c + '|' + row.Reschedule_Count__c + '|' + String.valueOf(row.Estimated_Delivery__c) + '|'
            + String.valueOf(row.Original_Estimated_Delivery__c);
    }

    private static DmlException insertFailureAs(User actor, List<Shipment__c> shipments) {
        DmlException failure;
        System.runAs(actor) {
            try {
                Database.insert(shipments, AccessLevel.SYSTEM_MODE);
                Assert.fail('The insert must be refused');
            } catch (DmlException e) {
                failure = e;
            }
        }
        return failure;
    }

    @IsTest
    static void customerInsert_isForcedToTheOwnAccountPriceStatusAndNoInternalField() {
        // AC-006.5 (BR-07, BR-08, BR-09, X6): 251 direct creates by Ana with Marta's
        // account, price 1, Delivered, cost, notes and proof set → each stored with
        // Ana's account, 180.00, Requested, estimate 2026-11-27 and no internal field
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> shipments = newAttackShipments(BULK_SIZE, accountOf(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL));

        Test.startTest();
        insertAsUserIgnoringFls(ana, shipments);
        Test.stopTest();

        String expected = accountOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL)
            + '|180.00|Requested|null|null|null|null|null|null|0|2026-11-27|2026-11-27';
        List<Shipment__c> saved = readCustomerFields(shipments);
        Assert.areEqual(BULK_SIZE, saved.size(), 'All 251 shipments must be saved');
        for (Shipment__c row : saved) {
            Assert.areEqual(expected, guardedValues(row), 'A customer insert must be forced to the guarded values');
        }
    }

    @IsTest
    static void customerInsert_inUserMode_isForcedToTheOwnAccountAndPrice() {
        // AC-006.5 (BR-07): Marta creates a shipment in user mode (her own grants)
        // naming Ana's account → stored under Marta's account with the Express price
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        User marta = TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> shipments = TestDataFactory.newCustomerShipments(1);
        shipments[0].Account__c = accountOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        shipments[0].Service_Type__c = 'Express';

        Test.startTest();
        System.runAs(marta) {
            Database.insert(shipments, AccessLevel.USER_MODE);
        }
        Test.stopTest();

        Shipment__c saved = readCustomerFields(shipments)[0];
        Assert.areEqual(accountOf(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL) + '|310.00|2026-11-24',
            saved.Account__c + '|' + saved.Price__c + '|' + String.valueOf(saved.Estimated_Delivery__c),
            'Marta\'s direct create must be under her account at 310.00, estimate Tuesday 2026-11-24');
    }

    @IsTest
    static void customerInsert_isRefusedWithAFieldError_whenTheWeightIsInvalid() {
        // AC-006.5 / AC-006.4: a direct create with 31 kg is refused on Weight_Kg__c
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> shipments = TestDataFactory.newCustomerShipments(1);
        shipments[0].Weight_Kg__c = 31;

        Test.startTest();
        DmlException failure = insertFailureAs(ana, shipments);
        Test.stopTest();

        Assert.areEqual('Weight_Kg__c|' + ShipmentTriggerHandler.INVALID_FIELD_MESSAGE,
            failure.getDmlFieldNames(0)[0] + '|' + failure.getDmlMessage(0), 'The weight must carry the generic field error');
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE Weight_Kg__c = 31 WITH SYSTEM_MODE], 'Nothing must be created');
    }

    @IsTest
    static void customerInsert_isRefusedWithAFieldError_whenThePickupDateIsInvalid() {
        // AC-006.5 / AC-006.3: a direct create with a Saturday pickup is refused on Pickup_Date__c
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> shipments = TestDataFactory.newCustomerShipments(1);
        shipments[0].Pickup_Date__c = Date.newInstance(2026, 11, 21);

        Test.startTest();
        DmlException failure = insertFailureAs(ana, shipments);
        Test.stopTest();

        Assert.areEqual('Pickup_Date__c|' + ShipmentTriggerHandler.INVALID_FIELD_MESSAGE,
            failure.getDmlFieldNames(0)[0] + '|' + failure.getDmlMessage(0), 'The pickup date must carry the generic field error');
    }

    @IsTest
    static void customerInsert_keepsAWorkingAccessCode() {
        // AC-006.5 (A1): clearing a customer's internal fields happens before the
        // code is issued: the code returned by insertWithCodes opens the shipment
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> shipments = TestDataFactory.newCustomerShipments(2);
        Map<Id, String> codes;

        Test.startTest();
        System.runAs(ana) {
            codes = DeliveryAccessCode.insertWithCodes(shipments);
        }
        Test.stopTest();

        Assert.areEqual(2, codes.size(), 'Each customer shipment must get a clear code');
        for (Shipment__c shipment : shipments) {
            Assert.isTrue(DeliveryAccessCode.verify(shipment.Id, codes.get(shipment.Id)),
                'The clear code of a customer insert must match its stored hash');
        }
    }

    @IsTest
    static void externalUserTypeWithAnotherProfile_isGuarded() {
        // AC-006.5: the guard keys on UserType, not on the profile: an
        // administrator seen as an external user type (seam) is guarded, and
        // without a customer account the insert is refused
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        List<Shipment__c> shipments = newAttackShipments(1, customerId());
        ShipmentTriggerHandler.runningUserTypeOverride = 'PowerCustomerSuccess';

        Test.startTest();
        DmlException failure = insertFailureAs(new User(Id = UserInfo.getUserId()), shipments);
        Test.stopTest();

        Assert.areEqual(ShipmentTriggerHandler.NOT_A_CUSTOMER_MESSAGE, failure.getDmlMessage(0),
            'An external user type with another profile and no account must be refused');
    }

    @IsTest
    static void customerProfileSeenAsStandardUserType_isNotGuarded() {
        // AC-006.5: the guard keys on UserType: Ana seen as a Standard (internal)
        // user type (seam) keeps the price 1.00 and the cost she wrote (her own
        // account: the platform refuses a lookup to an account she cannot read)
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        List<Shipment__c> shipments = newAttackShipments(1, accountOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL));
        ShipmentTriggerHandler.runningUserTypeOverride = 'Standard';

        Test.startTest();
        insertAsUserIgnoringFls(ana, shipments);
        Test.stopTest();

        Shipment__c saved = readCustomerFields(shipments)[0];
        Assert.areEqual('1.00|90.00|customer-written note',
            saved.Price__c + '|' + saved.Carrier_Cost__c + '|' + saved.Internal_Notes__c,
            'A Standard user type must not be guarded');
    }

    @IsTest
    static void internalUserInsert_keepsTheValuesItWrites() {
        // AC-006.5: an internal (Standard) user, here the administrator, is not guarded
        ShipmentRequestRules.todayOverride = TestDataFactory.REQUEST_TODAY;
        List<Shipment__c> shipments = newAttackShipments(1, customerId());

        Test.startTest();
        insertAsSystem(shipments);
        Test.stopTest();

        Shipment__c saved = readCustomerFields(shipments)[0];
        Assert.areEqual(customerId() + '|1.00|90.00|customer-written note',
            saved.Account__c + '|' + saved.Price__c + '|' + saved.Carrier_Cost__c + '|' + saved.Internal_Notes__c,
            'An internal user must keep the values it writes');
    }
}
