/**
 * @description Unit tests of DeliveryAccessCode: the generator (12 characters,
 *              uniform coverage of the alphabet), the stored value
 *              `v1$<rounds>$<base64 salt>$<base64 hash>` (100 salted SHA-256
 *              rounds, recomputed here independently) and the matching rules
 *              (normalization of lower case, spaces and hyphens, blank input,
 *              blank, malformed or unknown stored values, rounds read from the
 *              stored value): no DML, shipments in memory. Then the sanctioned
 *              reissue (reissueCodes, run as a support agent in user mode) and
 *              verify (one shipment's hash, by Id) on saved shipments.
 *              Covers AC-F.4, AC-F.16 and AC-F.17 of odd/tasks/foundation.md
 *              (D1, X8, X16).
 *              The support agent is a Standard Platform User with the
 *              RutaCargo_Support_Agent permission set. Criteria-based sharing
 *              rules are not evaluated in Apex tests (A10), so setup mirrors the
 *              rule access with manual Edit shares to the agent itself, not to the
 *              RutaCargo_Support_Agents group: adding a group member here locks
 *              the group row against SupportAgentAccessTest when the classes run
 *              in parallel (UNABLE_TO_LOCK_ROW).
 */
@IsTest
private with sharing class DeliveryAccessCodeTest {

    private static final String ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    private static final Pattern CODE_FORMAT = Pattern.compile('^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$');
    private static final Pattern STORED_HASH_FORMAT =
        Pattern.compile('^v1\\$100\\$[A-Za-z0-9+/]{22}==\\$[A-Za-z0-9+/]{43}=$');
    private static final Integer SAMPLE_SIZE = 500;
    private static final Integer EXPECTED_ROUNDS = 100;
    private static final Integer HASH_FIELD_LENGTH = 100;
    private static final String FIRST_CODE = 'ABCDEFGHJKMN';
    private static final String SECOND_CODE = '23456789PQRS';

    private static final String PERMISSION_SET_NAME = 'RutaCargo_Support_Agent';
    private static final String AGENT_KEY = 'rcreissue';
    private static final String SHARED_ACCOUNT = 'Reissue Test Customer';
    private static final String UNSHARED_ACCOUNT = 'Reissue Unshared Customer';
    private static final Integer BULK_SIZE = 251;
    private static final Integer UNSHARED_SIZE = 2;
    private static final String READER_KEY = 'rcreader';
    private static final String READ_ONLY_PERMISSION_SET_NAME = 'RC_Shipment_Read_Only_Test';

    // Independent recomputation of the stored value: round 1 hashes salt + code,
    // each next round hashes salt + the previous digest.
    private static String recompute(String code, Blob salt, Integer rounds) {
        String saltHex = EncodingUtil.convertToHex(salt);
        Blob digest = Crypto.generateDigest('SHA-256',
            EncodingUtil.convertFromHex(saltHex + EncodingUtil.convertToHex(Blob.valueOf(code))));
        for (Integer round = 2; round <= rounds; round++) {
            digest = Crypto.generateDigest('SHA-256',
                EncodingUtil.convertFromHex(saltHex + EncodingUtil.convertToHex(digest)));
        }
        return 'v1$' + rounds + '$' + EncodingUtil.base64Encode(salt) + '$' + EncodingUtil.base64Encode(digest);
    }

    private static Blob saltOf(String stored) {
        return EncodingUtil.base64Decode(stored.split('\\$')[2]);
    }

    private static Shipment__c shipmentWithHash(String stored) {
        return new Shipment__c(Delivery_Access_Code_Hash__c = stored);
    }

    // ─── Saved shipments for reissueCodes and verify (AC-F.16, AC-F.17) ──

    // SECURITY-JUSTIFICATION: the running test admin has no field permissions on
    // the RutaCargo custom fields and nobody can read Delivery_Access_Code_Hash__c
    // (at API 67 DML and SOQL default to user mode), so the test fixture is
    // written and the stored hashes are read back in system mode. Scope: setup DML
    // and verification reads of this test class only. Compensating control: the
    // code under test (reissueCodes, insertWithCodes) runs as the support agent
    // inside System.runAs in user mode. (pending owner approval, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    private static Map<Id, Shipment__c> readHashes(Set<Id> shipmentIds) {
        return new Map<Id, Shipment__c>([
            SELECT Id, Delivery_Access_Code_Hash__c FROM Shipment__c WHERE Id IN :shipmentIds WITH SYSTEM_MODE
        ]);
    }

    @TestSetup
    static void setup() {
        List<User> users = TestDataFactory.newPlatformUsers(new List<String>{ AGENT_KEY, READER_KEY });
        User agent = users[0];
        User reader = users[1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertAsSystem(users);
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_NAME WITH SYSTEM_MODE].Id;
            insertAsSystem(TestDataFactory.newPermissionSetAssignments(permissionSetId, new List<User>{ agent }));
            // The reader: Read on Shipment__c and no Edit, from a permission set of this test only.
            PermissionSet readOnly = TestDataFactory.newTestPermissionSet(READ_ONLY_PERMISSION_SET_NAME);
            insertAsSystem(new List<PermissionSet>{ readOnly });
            insertAsSystem(new List<ObjectPermissions>{
                TestDataFactory.newReadOnlyObjectPermission(readOnly.Id, 'Shipment__c')
            });
            insertAsSystem(TestDataFactory.newPermissionSetAssignments(readOnly.Id, new List<User>{ reader }));
        }
        Account shared = TestDataFactory.newCustomerAccount(SHARED_ACCOUNT);
        Account unshared = TestDataFactory.newCustomerAccount(UNSHARED_ACCOUNT);
        insertAsSystem(new List<Account>{ shared, unshared });
        List<Shipment__c> sharedShipments = TestDataFactory.newShipments(shared.Id, BULK_SIZE);
        insertAsSystem(sharedShipments);
        List<Shipment__c> unsharedShipments = TestDataFactory.newShipments(unshared.Id, UNSHARED_SIZE);
        insertAsSystem(unsharedShipments);
        // Manual shares to the agent user (the share builders accept any user or group Id).
        insertAsSystem(TestDataFactory.newShipmentGroupShares(sharedShipments, agent.Id, 'Edit'));
        insertAsSystem(TestDataFactory.newAccountGroupShares(new List<Account>{ shared }, agent.Id, 'Edit'));
        // The reader may edit the records of the second customer (sharing) but not
        // the object (no Edit permission on Shipment__c).
        insertAsSystem(TestDataFactory.newShipmentGroupShares(unsharedShipments, reader.Id, 'Edit'));
    }

    private static User agent() {
        return userWithKey(AGENT_KEY);
    }

    private static User reader() {
        return userWithKey(READER_KEY);
    }

    private static User userWithKey(String key) {
        String username = key + '.' + UserInfo.getOrganizationId() + '@example.com.rutacargo';
        return [SELECT Id FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1];
    }

    private static Set<Id> shipmentIdsOf(String accountName) {
        return new Map<Id, Shipment__c>([
            SELECT Id FROM Shipment__c WHERE Account__r.Name = :accountName WITH SYSTEM_MODE
        ]).keySet();
    }

    private static Map<Id, String> reissueAsAgent(Set<Id> shipmentIds) {
        Map<Id, String> codes;
        System.runAs(agent()) {
            codes = DeliveryAccessCode.reissueCodes(shipmentIds);
        }
        return codes;
    }

    // Two shipments A and B created by the agent through insertWithCodes, with their first codes.
    private static Map<Id, String> insertTwoAsAgent() {
        Id customerId = [SELECT Id FROM Account WHERE Name = :SHARED_ACCOUNT WITH SYSTEM_MODE LIMIT 1].Id;
        List<Shipment__c> rows = TestDataFactory.newShipments(customerId, 2);
        Map<Id, String> codes;
        System.runAs(agent()) {
            codes = DeliveryAccessCode.insertWithCodes(rows);
        }
        Assert.areEqual(2, codes.size(), 'insertWithCodes must return the codes of shipments A and B');
        return codes;
    }

    // ─── Generator ────────────────────────────────────────────────────────

    @IsTest
    static void generateCode_returnsTwelveCharactersFromTheAlphabet() {
        // AC-F.4: a code is 12 characters from ABCDEFGHJKMNPQRSTUVWXYZ23456789
        Test.startTest();
        String first = DeliveryAccessCode.generateCode();
        String second = DeliveryAccessCode.generateCode();
        Test.stopTest();

        Assert.isTrue(first != null && CODE_FORMAT.matcher(first).matches(), 'First code must be 12 alphabet characters');
        Assert.isTrue(second != null && CODE_FORMAT.matcher(second).matches(), 'Second code must be 12 alphabet characters');
        Assert.areNotEqual(first, second, 'Two generated codes must differ');
    }

    @IsTest
    static void generateCode_drawsEveryCharacterOfTheAlphabet() {
        // AC-F.4 (X8): 500 codes (6000 draws) reach all 31 alphabet characters,
        // so rejection sampling covers the whole alphabet and nothing else
        Set<String> seen = new Set<String>();

        Test.startTest();
        for (Integer i = 0; i < SAMPLE_SIZE; i++) {
            seen.addAll(DeliveryAccessCode.generateCode().split(''));
        }
        Test.stopTest();

        Assert.areEqual(new Set<String>(ALPHABET.split('')), seen,
            'The generator must draw exactly the 31 alphabet characters');
    }

    // ─── Stored value (CODE-001) ──────────────────────────────────────────

    @IsTest
    static void hashCode_storesVersionHundredRoundsSaltAndHash() {
        // AC-F.4: the stored value is v1$100$<base64 128-bit salt>$<base64 SHA-256>
        Test.startTest();
        String first = DeliveryAccessCode.hashCode(FIRST_CODE);
        String second = DeliveryAccessCode.hashCode(SECOND_CODE);
        Test.stopTest();

        Assert.isTrue(STORED_HASH_FORMAT.matcher(first).matches(), 'First stored value must be v1$100$salt$hash, got: ' + first);
        Assert.isTrue(STORED_HASH_FORMAT.matcher(second).matches(), 'Second stored value must be v1$100$salt$hash, got: ' + second);
    }

    @IsTest
    static void hashCode_fitsTheHashField() {
        // AC-F.4: the stored value fits Delivery_Access_Code_Hash__c (Text 100)
        String stored = DeliveryAccessCode.hashCode(FIRST_CODE);
        Assert.isTrue(stored.length() <= HASH_FIELD_LENGTH,
            'The stored value must fit Text(100), length: ' + stored.length());
    }

    @IsTest
    static void hashCode_isTheHundredRoundSaltedDigest() {
        // AC-F.4 (CODE-001): the hash is 100 SHA-256 rounds over salt + code, then salt + digest
        Test.startTest();
        String first = DeliveryAccessCode.hashCode(FIRST_CODE);
        String second = DeliveryAccessCode.hashCode(SECOND_CODE);
        Test.stopTest();

        Assert.areEqual(recompute(FIRST_CODE, saltOf(first), EXPECTED_ROUNDS), first,
            'The first stored value must be the 100-round salted digest');
        Assert.areEqual(recompute(SECOND_CODE, saltOf(second), EXPECTED_ROUNDS), second,
            'The second stored value must be the 100-round salted digest');
    }

    @IsTest
    static void hashCode_isNotASingleRoundDigest() {
        // AC-F.4 (CODE-001): a single SHA-256 round over salt + code does not give the stored hash
        String first = DeliveryAccessCode.hashCode(FIRST_CODE);
        String second = DeliveryAccessCode.hashCode(SECOND_CODE);

        String firstSingle = recompute(FIRST_CODE, saltOf(first), 1);
        String secondSingle = recompute(SECOND_CODE, saltOf(second), 1);

        Assert.areNotEqual(firstSingle.substringAfterLast('$'), first.substringAfterLast('$'),
            'The first hash must not be a single SHA-256 round');
        Assert.areNotEqual(secondSingle.substringAfterLast('$'), second.substringAfterLast('$'),
            'The second hash must not be a single SHA-256 round');
    }

    @IsTest
    static void hashCode_usesANewSaltEachTime() {
        // AC-F.4: the same code hashed twice gets two different salts
        String first = DeliveryAccessCode.hashCode(FIRST_CODE);
        String second = DeliveryAccessCode.hashCode(FIRST_CODE);
        Assert.areNotEqual(first.split('\\$')[2], second.split('\\$')[2], 'Each hash must get its own salt');
    }

    // ─── issueCodes (before insert) ───────────────────────────────────────

    @IsTest
    static void issueCodes_overwritesAHashSentByTheCaller() {
        // AC-F.4: a hash value sent by the caller is replaced
        List<Shipment__c> shipments = new List<Shipment__c>{
            shipmentWithHash('caller-value-a'),
            shipmentWithHash('caller-value-b')
        };

        Test.startTest();
        DeliveryAccessCode.issueCodes(shipments);
        Test.stopTest();

        Assert.isTrue(STORED_HASH_FORMAT.matcher(shipments[0].Delivery_Access_Code_Hash__c).matches(),
            'caller-value-a must be replaced by an iterated salted hash');
        Assert.isTrue(STORED_HASH_FORMAT.matcher(shipments[1].Delivery_Access_Code_Hash__c).matches(),
            'caller-value-b must be replaced by an iterated salted hash');
    }

    @IsTest
    static void issueCodes_keepsNoClearCode_whenNotCalledFromInsertWithCodes() {
        // AC-F.4 (CODE-002): outside insertWithCodes the clear codes are not kept
        List<Shipment__c> shipments = new List<Shipment__c>{ new Shipment__c(), new Shipment__c() };

        Test.startTest();
        DeliveryAccessCode.issueCodes(shipments);
        Test.stopTest();

        Assert.isTrue(DeliveryAccessCode.pendingCodesByHash.isEmpty(), 'No clear code may be kept pending');
        Assert.isTrue(DeliveryAccessCode.issuedCodesById.isEmpty(), 'No clear code may be kept by Id');
    }

    // ─── matches ──────────────────────────────────────────────────────────

    @IsTest
    static void matches_acceptsTheShipmentsOwnCode() {
        // AC-F.4: matches accepts each shipment's own code
        Shipment__c first = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));
        Shipment__c second = shipmentWithHash(DeliveryAccessCode.hashCode(SECOND_CODE));

        Test.startTest();
        Boolean firstMatches = DeliveryAccessCode.matches(first, FIRST_CODE);
        Boolean secondMatches = DeliveryAccessCode.matches(second, SECOND_CODE);
        Test.stopTest();

        Assert.isTrue(firstMatches, 'The first shipment must accept its own code');
        Assert.isTrue(secondMatches, 'The second shipment must accept its own code');
    }

    @IsTest
    static void matches_rejectsAnotherShipmentsCode() {
        // AC-F.4: matches rejects another shipment's code
        Shipment__c first = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));
        Shipment__c second = shipmentWithHash(DeliveryAccessCode.hashCode(SECOND_CODE));

        Test.startTest();
        Boolean firstMatches = DeliveryAccessCode.matches(first, SECOND_CODE);
        Boolean secondMatches = DeliveryAccessCode.matches(second, FIRST_CODE);
        Test.stopTest();

        Assert.isFalse(firstMatches, 'The first shipment must reject the second code');
        Assert.isFalse(secondMatches, 'The second shipment must reject the first code');
    }

    @IsTest
    static void matches_acceptsTheCodeInLowerCaseWithSurroundingSpaces() {
        // AC-F.4: the input is normalized (trim, upper case) before hashing
        Shipment__c first = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));
        Shipment__c second = shipmentWithHash(DeliveryAccessCode.hashCode(SECOND_CODE));

        Test.startTest();
        Boolean lowerCase = DeliveryAccessCode.matches(first, '  abcdefghjkmn ');
        Boolean mixedCase = DeliveryAccessCode.matches(second, '\t23456789pqRS');
        Test.stopTest();

        Assert.isTrue(lowerCase, 'A lower-case code with spaces must match');
        Assert.isTrue(mixedCase, 'A mixed-case code with a tab must match');
    }

    @IsTest
    static void matches_acceptsTheCodeGroupedAsXxxxXxxxXxxx() {
        // AC-F.4: XXXX-XXXX-XXXX and XXXX XXXX XXXX are the same code
        Shipment__c first = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));
        Shipment__c second = shipmentWithHash(DeliveryAccessCode.hashCode(SECOND_CODE));

        Test.startTest();
        Boolean hyphens = DeliveryAccessCode.matches(first, 'abcd-efgh-jkmn');
        Boolean spaces = DeliveryAccessCode.matches(second, '2345 6789 PQRS');
        Test.stopTest();

        Assert.isTrue(hyphens, 'abcd-efgh-jkmn must match ABCDEFGHJKMN');
        Assert.isTrue(spaces, '2345 6789 PQRS must match 23456789PQRS');
    }

    @IsTest
    static void matches_rejectsACodeThatDiffersOnlyInTheLastCharacter() {
        // AC-F.4: the whole code is compared, not a prefix
        Shipment__c shipment = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));

        Test.startTest();
        Boolean result = DeliveryAccessCode.matches(shipment, FIRST_CODE.left(11) + 'P');
        Test.stopTest();

        Assert.isFalse(result, 'A code that differs in its last character must be rejected');
    }

    @IsTest
    static void matches_readsTheRoundsFromTheStoredValue() {
        // AC-F.4: the version and the rounds are read from the stored value
        Blob salt = Crypto.generateAesKey(128);
        Shipment__c sevenRounds = shipmentWithHash(recompute(FIRST_CODE, salt, 7));
        Shipment__c twoHundredRounds = shipmentWithHash(recompute(SECOND_CODE, salt, 200));

        Test.startTest();
        Boolean seven = DeliveryAccessCode.matches(sevenRounds, FIRST_CODE);
        Boolean twoHundred = DeliveryAccessCode.matches(twoHundredRounds, SECOND_CODE);
        Test.stopTest();

        Assert.isTrue(seven, 'A v1 value stored with 7 rounds must match its code');
        Assert.isTrue(twoHundred, 'A v1 value stored with 200 rounds must match its code');
    }

    @IsTest
    static void matches_returnsFalse_whenRoundsExceedTheLimit() {
        // AC-F.4: a stored value asking for more than 1000 rounds matches nothing
        String stored = DeliveryAccessCode.hashCode(FIRST_CODE).replace('v1$100$', 'v1$5000$');
        Assert.isFalse(DeliveryAccessCode.matches(shipmentWithHash(stored), FIRST_CODE),
            'A stored value with 5000 rounds must match nothing');
    }

    @IsTest
    static void matches_returnsFalse_whenTheVersionIsUnknown() {
        // AC-F.4: only version v1 is read
        String stored = DeliveryAccessCode.hashCode(FIRST_CODE).replace('v1$', 'v2$');
        Assert.isFalse(DeliveryAccessCode.matches(shipmentWithHash(stored), FIRST_CODE),
            'A stored value of version v2 must match nothing');
    }

    @IsTest
    static void matches_returnsFalse_whenTheStoredValueIsASingleSaltedHash() {
        // AC-F.4: the previous <salt>$<hash> format is not accepted
        String stored = DeliveryAccessCode.hashCode(FIRST_CODE).substringAfter('v1$100$');
        Assert.isFalse(DeliveryAccessCode.matches(shipmentWithHash(stored), FIRST_CODE),
            'A stored value without version and rounds must match nothing');
    }

    @IsTest
    static void matches_returnsFalse_whenCodeIsNull() {
        // AC-F.4: blank input is rejected
        Shipment__c shipment = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));
        Assert.isFalse(DeliveryAccessCode.matches(shipment, null), 'A null code must be rejected');
    }

    @IsTest
    static void matches_returnsFalse_whenCodeIsBlank() {
        // AC-F.4: blank input is rejected
        Shipment__c shipment = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));
        Assert.isFalse(DeliveryAccessCode.matches(shipment, '   '), 'A blank code must be rejected');
    }

    @IsTest
    static void matches_returnsFalse_whenCodeIsOnlyHyphens() {
        // AC-F.4: an input that normalizes to nothing is rejected
        Shipment__c shipment = shipmentWithHash(DeliveryAccessCode.hashCode(FIRST_CODE));
        Assert.isFalse(DeliveryAccessCode.matches(shipment, '- - -'), 'An input of hyphens must be rejected');
    }

    @IsTest
    static void matches_returnsFalse_whenHashIsBlank() {
        // AC-F.4: a shipment without a hash matches nothing
        Assert.isFalse(DeliveryAccessCode.matches(shipmentWithHash(null), FIRST_CODE),
            'A shipment without a hash must match nothing');
    }

    @IsTest
    static void matches_returnsFalse_whenHashIsAClearCode() {
        // AC-F.4: a clear code stored in the hash field matches nothing
        Assert.isFalse(DeliveryAccessCode.matches(shipmentWithHash(FIRST_CODE), FIRST_CODE),
            'A clear code stored as hash must not match');
    }

    @IsTest
    static void matches_returnsFalse_whenShipmentIsNull() {
        // AC-F.4: no shipment, no match
        Assert.isFalse(DeliveryAccessCode.matches(null, FIRST_CODE), 'A null shipment must match nothing');
    }

    // ─── reissueCodes (AC-F.16) ───────────────────────────────────────────

    @IsTest
    static void reissueCodes_returnsOneDistinctAlphabetCodePerGivenId() {
        // AC-F.16: run as a support agent over 251 shipments, the returned map
        // holds a 12-character alphabet code for exactly the given Ids, all distinct
        Set<Id> shipmentIds = shipmentIdsOf(SHARED_ACCOUNT);

        Test.startTest();
        Map<Id, String> codes = reissueAsAgent(shipmentIds);
        Test.stopTest();

        Assert.areEqual(shipmentIds, codes.keySet(), 'The map must hold exactly the 251 given Ids');
        Assert.areEqual(BULK_SIZE, new Set<String>(codes.values()).size(), 'The 251 new codes must be distinct');
        for (String code : codes.values()) {
            Assert.isTrue(CODE_FORMAT.matcher(code).matches(), 'Each new code must be 12 alphabet characters');
        }
    }

    @IsTest
    static void reissueCodes_storesANewHashThatMatchesEachReturnedCode() {
        // AC-F.16: each of the 251 shipments stores a new v1$100 salted hash that
        // matches its returned code and differs from the hash it had before
        Set<Id> shipmentIds = shipmentIdsOf(SHARED_ACCOUNT);
        Map<Id, Shipment__c> before = readHashes(shipmentIds);

        Test.startTest();
        Map<Id, String> codes = reissueAsAgent(shipmentIds);
        Test.stopTest();

        Map<Id, Shipment__c> after = readHashes(shipmentIds);
        for (Id shipmentId : shipmentIds) {
            String stored = after.get(shipmentId).Delivery_Access_Code_Hash__c;
            Assert.isTrue(STORED_HASH_FORMAT.matcher(stored).matches(), 'The new hash must be v1$100$salt$hash');
            Assert.isFalse(before.get(shipmentId).Delivery_Access_Code_Hash__c == stored, 'The hash must be replaced');
            Assert.isTrue(DeliveryAccessCode.matches(after.get(shipmentId), codes.get(shipmentId)),
                'The stored hash must match the returned code');
        }
    }

    @IsTest
    static void reissueCodes_newCodesVerify() {
        // AC-F.16: the returned code of shipments A and B verifies on its shipment
        Map<Id, String> first = insertTwoAsAgent();

        Test.startTest();
        Map<Id, String> reissued = reissueAsAgent(first.keySet());
        Test.stopTest();

        for (Id shipmentId : first.keySet()) {
            Assert.isTrue(DeliveryAccessCode.verify(shipmentId, reissued.get(shipmentId)),
                'The reissued code must verify on its shipment');
        }
    }

    @IsTest
    static void reissueCodes_previousCodesNoLongerVerify() {
        // AC-F.16: after the reissue, the previous codes of A and B are rejected
        Map<Id, String> first = insertTwoAsAgent();
        for (Id shipmentId : first.keySet()) {
            Assert.isTrue(DeliveryAccessCode.verify(shipmentId, first.get(shipmentId)),
                'Before the reissue the first code must verify');
        }

        Test.startTest();
        reissueAsAgent(first.keySet());
        Test.stopTest();

        for (Id shipmentId : first.keySet()) {
            Assert.isFalse(DeliveryAccessCode.verify(shipmentId, first.get(shipmentId)),
                'After the reissue the previous code must not verify');
        }
    }

    @IsTest
    static void reissueCodes_keepsNoClearCodeInMemory_afterReturning() {
        // AC-F.16: the registered Ids and the clear codes are cleared when the call ends
        Set<Id> shipmentIds = shipmentIdsOf(SHARED_ACCOUNT);

        Test.startTest();
        reissueAsAgent(shipmentIds);
        Test.stopTest();

        Assert.isTrue(DeliveryAccessCode.reissuingIds.isEmpty(), 'No Id may stay registered for reissue');
        Assert.isTrue(DeliveryAccessCode.reissuedCodesById.isEmpty(), 'No clear code may stay in memory');
    }

    @IsTest
    static void reissueCodes_throwsAndKeepsTheHash_whenTheAgentCannotEditTheShipment() {
        // AC-F.16 (P10, no escalation): user mode, so shipments not shared with the
        // agent cannot be reissued; the hashes stay and no state is kept
        Set<Id> shipmentIds = shipmentIdsOf(UNSHARED_ACCOUNT);
        Map<Id, Shipment__c> before = readHashes(shipmentIds);

        Test.startTest();
        Boolean reissued = true;
        try {
            reissueAsAgent(shipmentIds);
        } catch (System.DmlException e) {
            reissued = false;
        }
        Test.stopTest();

        Assert.isFalse(reissued, 'An agent without access to the shipments must not reissue their codes');
        Map<Id, Shipment__c> after = readHashes(shipmentIds);
        for (Id shipmentId : shipmentIds) {
            Assert.areEqual(before.get(shipmentId).Delivery_Access_Code_Hash__c,
                after.get(shipmentId).Delivery_Access_Code_Hash__c, 'A refused reissue must keep the hash');
        }
        Assert.isTrue(DeliveryAccessCode.reissuingIds.isEmpty(), 'No Id may stay registered after a failure');
        Assert.isTrue(DeliveryAccessCode.reissuedCodesById.isEmpty(), 'No clear code may stay after a failure');
    }

    @IsTest
    static void reissueCodes_throwsAndKeepsTheHash_whenTheUserHasNoEditPermissionOnShipments() {
        // AC-F.16 (P10, no escalation): user mode also applies the object
        // permission, so a user with an Edit share on the records but no Edit on
        // Shipment__c cannot reissue; the hashes stay and no state is kept. The
        // platform refuses a user-mode DML without the object permission with a
        // System.TypeException (DML operation UPDATE not allowed), not a DmlException.
        Set<Id> shipmentIds = shipmentIdsOf(UNSHARED_ACCOUNT);
        Map<Id, Shipment__c> before = readHashes(shipmentIds);

        Test.startTest();
        Boolean reissued = true;
        System.runAs(reader()) {
            try {
                DeliveryAccessCode.reissueCodes(shipmentIds);
            } catch (System.TypeException e) {
                reissued = false;
            }
        }
        Test.stopTest();

        Assert.isFalse(reissued, 'A user without Edit on Shipment__c must not reissue codes, even with an Edit share');
        Map<Id, Shipment__c> after = readHashes(shipmentIds);
        for (Id shipmentId : shipmentIds) {
            Assert.areEqual(before.get(shipmentId).Delivery_Access_Code_Hash__c,
                after.get(shipmentId).Delivery_Access_Code_Hash__c, 'A refused reissue must keep the hash');
        }
        Assert.isTrue(DeliveryAccessCode.reissuedCodesById.isEmpty(), 'No clear code may stay after a refusal');
    }

    @IsTest
    static void reissueCodes_returnsAnEmptyMap_whenNoIdsAreGiven() {
        // AC-F.16: nothing to reissue, nothing returned
        Assert.isTrue(DeliveryAccessCode.reissueCodes(new Set<Id>()).isEmpty(), 'An empty set must return an empty map');
    }

    @IsTest
    static void reissueCodes_returnsAnEmptyMap_whenIdsAreNull() {
        // AC-F.16: nothing to reissue, nothing returned
        Assert.isTrue(DeliveryAccessCode.reissueCodes(null).isEmpty(), 'A null set must return an empty map');
    }

    // ─── verify (AC-F.17) ─────────────────────────────────────────────────

    @IsTest
    static void verify_returnsTrue_forEachShipmentsOwnCode() {
        // AC-F.17: A's code verifies on A, and B's code on B
        Map<Id, String> codes = insertTwoAsAgent();
        List<Id> ids = new List<Id>(codes.keySet());

        Test.startTest();
        Boolean a = DeliveryAccessCode.verify(ids[0], codes.get(ids[0]));
        Boolean b = DeliveryAccessCode.verify(ids[1], codes.get(ids[1]));
        Test.stopTest();

        Assert.isTrue(a, 'A must accept its own code');
        Assert.isTrue(b, 'B must accept its own code');
    }

    @IsTest
    static void verify_returnsTrue_forTheOwnCodeInLowerCaseOrGrouped() {
        // AC-F.17: A's code typed in lower case, and as xxxx-xxxx-xxxx with spaces around
        Map<Id, String> codes = insertTwoAsAgent();
        List<Id> ids = new List<Id>(codes.keySet());
        String a = codes.get(ids[0]);
        String b = codes.get(ids[1]);

        Test.startTest();
        Boolean lowerCase = DeliveryAccessCode.verify(ids[0], a.toLowerCase());
        Boolean grouped = DeliveryAccessCode.verify(ids[1], ' ' + b.left(4) + '-' + b.mid(4, 4) + '-' + b.right(4) + ' ');
        Test.stopTest();

        Assert.isTrue(lowerCase, 'The own code in lower case must verify');
        Assert.isTrue(grouped, 'The own code as XXXX-XXXX-XXXX must verify');
    }

    @IsTest
    static void verify_returnsFalse_forAnotherShipmentsCode() {
        // AC-F.17: B's code on A, and A's code on B, are rejected
        Map<Id, String> codes = insertTwoAsAgent();
        List<Id> ids = new List<Id>(codes.keySet());

        Test.startTest();
        Boolean bOnA = DeliveryAccessCode.verify(ids[0], codes.get(ids[1]));
        Boolean aOnB = DeliveryAccessCode.verify(ids[1], codes.get(ids[0]));
        Test.stopTest();

        Assert.isFalse(bOnA, 'B\'s code must not verify on A');
        Assert.isFalse(aOnB, 'A\'s code must not verify on B');
    }

    @IsTest
    static void verify_returnsFalse_whenCodeIsBlank() {
        // AC-F.17: a blank code is rejected
        Id a = new List<Id>(insertTwoAsAgent().keySet())[0];
        Assert.isFalse(DeliveryAccessCode.verify(a, '  '), 'A blank code must be rejected');
    }

    @IsTest
    static void verify_returnsFalse_whenCodeIsNull() {
        // AC-F.17: a null code is rejected
        Id a = new List<Id>(insertTwoAsAgent().keySet())[0];
        Assert.isFalse(DeliveryAccessCode.verify(a, null), 'A null code must be rejected');
    }

    @IsTest
    static void verify_returnsFalse_andDoesNotQuery_whenCodeIsMalformed() {
        // AC-F.17: malformed codes (too short, too long, outside the alphabet) are
        // rejected before any query
        Map<Id, String> codes = insertTwoAsAgent();
        Id a = new List<Id>(codes.keySet())[0];
        String own = codes.get(a);

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        Boolean tooShort = DeliveryAccessCode.verify(a, own.left(11));
        Boolean tooLong = DeliveryAccessCode.verify(a, own + 'A');
        Boolean outsideAlphabet = DeliveryAccessCode.verify(a, own.left(11) + '0');
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.isFalse(tooShort, 'An 11-character code must be rejected');
        Assert.isFalse(tooLong, 'A 13-character code must be rejected');
        Assert.isFalse(outsideAlphabet, 'A code with 0 (outside the alphabet) must be rejected');
        Assert.areEqual(0, queriesUsed, 'A malformed code must be rejected before any query');
    }

    @IsTest
    static void verify_returnsFalse_whenTheIdIsUnknown() {
        // AC-F.17: an Id of no shipment is rejected, whatever the code
        String own = insertTwoAsAgent().values()[0];
        Id unknown = Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000000';

        Assert.isFalse(DeliveryAccessCode.verify(unknown, own), 'An unknown shipment Id must be rejected');
    }

    @IsTest
    static void verify_computesOneHash_whetherTheIdIsKnownOrUnknown() {
        // AC-F.17 (X16): a wrong code on an existing shipment and a well-formed
        // code on an unknown Id cost the same hash work, so the time of a call
        // does not tell whether the shipment exists
        Map<Id, String> codes = insertTwoAsAgent();
        List<Id> ids = new List<Id>(codes.keySet());
        Id unknown = Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '000000000000';

        Test.startTest();
        Integer start = DeliveryAccessCode.hashesComputed;
        Boolean onKnown = DeliveryAccessCode.verify(ids[0], codes.get(ids[1]));
        Integer afterKnown = DeliveryAccessCode.hashesComputed;
        Boolean onUnknown = DeliveryAccessCode.verify(unknown, codes.get(ids[0]));
        Integer afterUnknown = DeliveryAccessCode.hashesComputed;
        Test.stopTest();

        Assert.isFalse(onKnown, 'B\'s code must not verify on A');
        Assert.isFalse(onUnknown, 'A code must not verify on an unknown Id');
        Assert.areEqual(1, afterKnown - start, 'A wrong code on an existing shipment must compute one hash');
        Assert.areEqual(1, afterUnknown - afterKnown, 'A code on an unknown Id must also compute one hash');
    }

    @IsTest
    static void verify_returnsFalse_whenTheIdIsNull() {
        // AC-F.17: no shipment, no match
        String own = insertTwoAsAgent().values()[0];
        Assert.isFalse(DeliveryAccessCode.verify(null, own), 'A null shipment Id must be rejected');
    }
}
