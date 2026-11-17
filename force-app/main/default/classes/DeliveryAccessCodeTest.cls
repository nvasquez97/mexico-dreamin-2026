/**
 * @description Unit tests of DeliveryAccessCode: the generator (12 characters,
 *              uniform coverage of the alphabet), the stored value
 *              `v1$<rounds>$<base64 salt>$<base64 hash>` (100 salted SHA-256
 *              rounds, recomputed here independently) and the matching rules
 *              (normalization of lower case, spaces and hyphens, blank input,
 *              blank, malformed or unknown stored values, rounds read from the
 *              stored value). No DML: shipments are in memory.
 *              Covers AC-F.4 of odd/tasks/foundation.md (D1, X8, X16).
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
}
