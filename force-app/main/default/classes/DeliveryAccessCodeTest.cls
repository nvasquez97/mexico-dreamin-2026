/**
 * @description Unit tests of DeliveryAccessCode: the generator (alphabet, length,
 *              uniform coverage of the alphabet), the salted hash format and the
 *              matching rules (normalization, blank input, blank or malformed
 *              hash, full-length comparison). No DML: shipments are in memory.
 *              Covers AC-F.4 of odd/tasks/foundation.md (D1, X8, X16).
 */
@IsTest
private with sharing class DeliveryAccessCodeTest {

    private static final String ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    private static final Pattern CODE_FORMAT = Pattern.compile('^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{10}$');
    private static final Pattern STORED_HASH_FORMAT = Pattern.compile('^[A-Za-z0-9+/]{22}==\\$[A-Za-z0-9+/]{43}=$');
    private static final Integer SAMPLE_SIZE = 500;

    // Issues codes for two in-memory shipments and returns them, aligned with the list.
    private static List<Shipment__c> issueTwo() {
        List<Shipment__c> shipments = new List<Shipment__c>{ new Shipment__c(), new Shipment__c() };
        DeliveryAccessCode.issueCodes(shipments);
        return shipments;
    }

    @IsTest
    static void generateCode_returnsTenCharactersFromTheAlphabet() {
        // AC-F.4: a code is 10 characters from ABCDEFGHJKMNPQRSTUVWXYZ23456789
        Test.startTest();
        String first = DeliveryAccessCode.generateCode();
        String second = DeliveryAccessCode.generateCode();
        Test.stopTest();

        Assert.isTrue(first != null && CODE_FORMAT.matcher(first).matches(), 'First code must be 10 alphabet characters');
        Assert.isTrue(second != null && CODE_FORMAT.matcher(second).matches(), 'Second code must be 10 alphabet characters');
        Assert.areNotEqual(first, second, 'Two generated codes must differ');
    }

    @IsTest
    static void generateCode_drawsEveryCharacterOfTheAlphabet() {
        // AC-F.4 (X8): 500 codes (5000 draws) reach all 31 alphabet characters,
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

    @IsTest
    static void issueCodes_storesASaltedHashAndNotTheCode() {
        // AC-F.4: each shipment stores <base64 salt>$<base64 SHA-256>, never the clear code
        Test.startTest();
        List<Shipment__c> shipments = issueTwo();
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();
        Test.stopTest();

        Assert.areEqual(2, codes.size(), 'One clear code must be returned per shipment');
        for (Integer i = 0; i < shipments.size(); i++) {
            String hash = shipments[i].Delivery_Access_Code_Hash__c;
            Assert.isTrue(hash != null && STORED_HASH_FORMAT.matcher(hash).matches(),
                'Shipment ' + i + ' must store <base64 salt>$<base64 SHA-256>');
            Assert.isFalse(hash.toUpperCase().contains(codes[i]), 'Shipment ' + i + ' must not store its clear code');
        }
        Assert.areNotEqual(shipments[0].Delivery_Access_Code_Hash__c.substringBefore('$'),
            shipments[1].Delivery_Access_Code_Hash__c.substringBefore('$'), 'Each shipment must get its own salt');
    }

    @IsTest
    static void issueCodes_overwritesAHashSentByTheCaller() {
        // AC-F.4: a hash value sent by the caller is replaced
        List<Shipment__c> shipments = new List<Shipment__c>{
            new Shipment__c(Delivery_Access_Code_Hash__c = 'caller-value-a'),
            new Shipment__c(Delivery_Access_Code_Hash__c = 'caller-value-b')
        };

        Test.startTest();
        DeliveryAccessCode.issueCodes(shipments);
        Test.stopTest();

        Assert.isTrue(STORED_HASH_FORMAT.matcher(shipments[0].Delivery_Access_Code_Hash__c).matches(),
            'caller-value-a must be replaced by a salted hash');
        Assert.isTrue(STORED_HASH_FORMAT.matcher(shipments[1].Delivery_Access_Code_Hash__c).matches(),
            'caller-value-b must be replaced by a salted hash');
    }

    @IsTest
    static void matches_acceptsEachShipmentsOwnCode() {
        // AC-F.4: matches accepts each shipment's own code
        List<Shipment__c> shipments = issueTwo();
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();

        Test.startTest();
        Boolean firstMatches = DeliveryAccessCode.matches(shipments[0], codes[0]);
        Boolean secondMatches = DeliveryAccessCode.matches(shipments[1], codes[1]);
        Test.stopTest();

        Assert.isTrue(firstMatches, 'The first shipment must accept its own code');
        Assert.isTrue(secondMatches, 'The second shipment must accept its own code');
    }

    @IsTest
    static void matches_rejectsAnotherShipmentsCode() {
        // AC-F.4: matches rejects another shipment's code
        List<Shipment__c> shipments = issueTwo();
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();

        Test.startTest();
        Boolean firstMatches = DeliveryAccessCode.matches(shipments[0], codes[1]);
        Boolean secondMatches = DeliveryAccessCode.matches(shipments[1], codes[0]);
        Test.stopTest();

        Assert.isFalse(firstMatches, 'The first shipment must reject the second code');
        Assert.isFalse(secondMatches, 'The second shipment must reject the first code');
    }

    @IsTest
    static void matches_acceptsTheCodeInLowerCaseWithSurroundingSpaces() {
        // AC-F.4: the input is normalized (trim, upper case) before hashing
        List<Shipment__c> shipments = issueTwo();
        List<String> codes = DeliveryAccessCode.lastIssuedCodes();

        Test.startTest();
        Boolean lowerCase = DeliveryAccessCode.matches(shipments[0], '  ' + codes[0].toLowerCase() + ' ');
        Boolean mixedCase = DeliveryAccessCode.matches(shipments[1], '\t' + codes[1].left(5).toLowerCase() + codes[1].substring(5));
        Test.stopTest();

        Assert.isTrue(lowerCase, 'A lower-case code with spaces must match');
        Assert.isTrue(mixedCase, 'A mixed-case code with a tab must match');
    }

    @IsTest
    static void matches_rejectsACodeThatDiffersOnlyInTheLastCharacter() {
        // AC-F.4: the whole code is compared, not a prefix
        List<Shipment__c> shipments = issueTwo();
        String code = DeliveryAccessCode.lastIssuedCodes()[0];
        String lastCharacter = code.right(1);
        String otherLast = lastCharacter == '2' ? '3' : '2';

        Test.startTest();
        Boolean result = DeliveryAccessCode.matches(shipments[0], code.left(9) + otherLast);
        Test.stopTest();

        Assert.isFalse(result, 'A code that differs in its last character must be rejected');
    }

    @IsTest
    static void matches_returnsFalse_whenCodeIsNull() {
        // AC-F.4: blank input is rejected
        Shipment__c shipment = issueTwo()[0];
        Assert.isFalse(DeliveryAccessCode.matches(shipment, null), 'A null code must be rejected');
    }

    @IsTest
    static void matches_returnsFalse_whenCodeIsBlank() {
        // AC-F.4: blank input is rejected
        Shipment__c shipment = issueTwo()[0];
        Assert.isFalse(DeliveryAccessCode.matches(shipment, '   '), 'A blank code must be rejected');
    }

    @IsTest
    static void matches_returnsFalse_whenHashIsBlank() {
        // AC-F.4: a shipment without a hash matches nothing
        Shipment__c shipment = issueTwo()[0];
        String code = DeliveryAccessCode.lastIssuedCodes()[0];
        shipment.Delivery_Access_Code_Hash__c = null;
        Assert.isFalse(DeliveryAccessCode.matches(shipment, code), 'A shipment without a hash must match nothing');
    }

    @IsTest
    static void matches_returnsFalse_whenHashIsMalformed() {
        // AC-F.4: a stored value that is not <base64 salt>$<base64 SHA-256> matches nothing
        Shipment__c shipment = issueTwo()[0];
        String code = DeliveryAccessCode.lastIssuedCodes()[0];
        shipment.Delivery_Access_Code_Hash__c = code;
        Assert.isFalse(DeliveryAccessCode.matches(shipment, code), 'A clear code stored as hash must not match');
    }

    @IsTest
    static void matches_returnsFalse_whenShipmentIsNull() {
        // AC-F.4: no shipment, no match
        Assert.isFalse(DeliveryAccessCode.matches(null, 'ABCDEFGHJK'), 'A null shipment must match nothing');
    }

    @IsTest
    static void lastIssuedCodes_returnsACopy() {
        // AC-F.4: the caller cannot alter the codes kept for the transaction
        issueTwo();
        DeliveryAccessCode.lastIssuedCodes().clear();
        Assert.areEqual(2, DeliveryAccessCode.lastIssuedCodes().size(), 'Clearing the returned list must not clear the codes');
    }
}
