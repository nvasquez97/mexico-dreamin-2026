/**
 * @description Per-shipment delivery access code (owner decision D1, policy X8
 *              and X16). A code is 10 characters from an unambiguous alphabet,
 *              drawn with Crypto.getRandomInteger() and rejection sampling. Only
 *              a salted SHA-256 is stored, as `<base64 salt>$<base64 hash>` in
 *              Shipment__c.Delivery_Access_Code_Hash__c. The clear codes live
 *              only in this transaction, aligned with the inserted records, and
 *              are never written to a field, a debug log or an exception message.
 */
public with sharing class DeliveryAccessCode {

    private static final String ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    private static final Integer CODE_LENGTH = 10;
    private static final Integer FIVE_BIT_MASK = 31;
    private static final Integer SALT_BITS = 128;
    private static final String DIGEST = 'SHA-256';
    private static final String SEPARATOR = '$';
    private static final Pattern STORED_FORMAT = Pattern.compile('^[A-Za-z0-9+/]{22}==\\$[A-Za-z0-9+/]{43}=$');

    // A DML of more than 200 records runs the trigger in chunks of 200: the
    // codes of one insert call span every chunk of that DML statement.
    private static final Integer TRIGGER_CHUNK_SIZE = 200;

    private static List<String> issuedCodes = new List<String>();
    private static Integer lastDmlStatement;
    private static Integer lastBatchSize = 0;

    /**
     * @description Generates one clear code. Each character takes the low five
     *              bits of a cryptographically secure random integer (0-31) and
     *              rejects 31, so the 31 alphabet characters are equally likely.
     * @return a 10-character code from ABCDEFGHJKMNPQRSTUVWXYZ23456789
     */
    public static String generateCode() {
        List<String> characters = new List<String>();
        while (characters.size() < CODE_LENGTH) {
            Integer candidate = Crypto.getRandomInteger() & FIVE_BIT_MASK;
            if (candidate < ALPHABET.length()) {
                characters.add(ALPHABET.substring(candidate, candidate + 1));
            }
        }
        return String.join(characters, '');
    }

    /**
     * @description Issues a new code for every shipment: overwrites
     *              Delivery_Access_Code_Hash__c with a fresh salt and hash, and
     *              keeps the clear codes, aligned with the list, for
     *              lastIssuedCodes(). The list restarts with each insert call
     *              and spans the 200-record chunks of that call. No SOQL or DML.
     * @param shipments the shipments being inserted (Trigger.new)
     */
    public static void issueCodes(List<Shipment__c> shipments) {
        if (shipments == null) {
            return;
        }
        if (!continuesTheSameInsert()) {
            issuedCodes = new List<String>();
        }
        lastDmlStatement = Limits.getDmlStatements();
        lastBatchSize = shipments.size();
        for (Shipment__c shipment : shipments) {
            String code = generateCode();
            shipment.Delivery_Access_Code_Hash__c = hashWithSalt(code, Crypto.generateAesKey(SALT_BITS));
            issuedCodes.add(code);
        }
    }

    /**
     * @description The clear codes issued by the last insert of this
     *              transaction, in the order of the inserted list. Read it right
     *              after the insert; it is never persisted.
     * @return a copy of the clear codes
     */
    public static List<String> lastIssuedCodes() {
        return new List<String>(issuedCodes);
    }

    /**
     * @description Checks a code entered by a person against the stored salted
     *              hash. The input is trimmed and upper-cased; the comparison
     *              covers every character with no early exit.
     * @param shipment a shipment with Delivery_Access_Code_Hash__c queried
     * @param code the code to check
     * @return true only when the code is the shipment's code
     */
    public static Boolean matches(Shipment__c shipment, String code) {
        if (shipment == null || String.isBlank(code)) {
            return false;
        }
        String stored = shipment.Delivery_Access_Code_Hash__c;
        if (String.isBlank(stored) || !STORED_FORMAT.matcher(stored).matches()) {
            return false;
        }
        Blob salt = EncodingUtil.base64Decode(stored.substringBefore(SEPARATOR));
        return constantTimeEquals(hashWithSalt(code.trim().toUpperCase(), salt), stored);
    }

    // A batch continues the previous one only when the previous batch was a full
    // 200-record chunk and no new DML statement has started since.
    private static Boolean continuesTheSameInsert() {
        return lastBatchSize == TRIGGER_CHUNK_SIZE && lastDmlStatement == Limits.getDmlStatements();
    }

    private static String hashWithSalt(String code, Blob salt) {
        Blob saltedCode = EncodingUtil.convertFromHex(
            EncodingUtil.convertToHex(salt) + EncodingUtil.convertToHex(Blob.valueOf(code))
        );
        return EncodingUtil.base64Encode(salt) + SEPARATOR
            + EncodingUtil.base64Encode(Crypto.generateDigest(DIGEST, saltedCode));
    }

    private static Boolean constantTimeEquals(String expected, String actual) {
        Integer difference = expected.length() ^ actual.length();
        for (Integer i = 0; i < expected.length(); i++) {
            Integer actualCharacter = i < actual.length() ? actual.charAt(i) : 0;
            difference = difference | (expected.charAt(i) ^ actualCharacter);
        }
        return difference == 0;
    }
}
