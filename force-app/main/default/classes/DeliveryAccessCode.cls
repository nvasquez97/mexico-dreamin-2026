/**
 * @description Per-shipment delivery access code (owner decision D1, policy X7,
 *              X8 and X16). A code is 12 characters from an unambiguous alphabet,
 *              drawn with Crypto.getRandomInteger() and rejection sampling. Only
 *              an iterated salted hash is stored in
 *              Shipment__c.Delivery_Access_Code_Hash__c, as
 *              `v1$<rounds>$<base64 128-bit salt>$<base64 hash>`: round 1 is
 *              SHA-256(salt + code), each next round SHA-256(salt + previous
 *              digest), 100 rounds. The clear codes are bound to record Ids and
 *              returned only by insertWithCodes and reissueCodes; rows inserted
 *              or updated any other way keep no clear code, and a plain update
 *              cannot change the hash (ShipmentTriggerHandler). verify checks a
 *              typed code against one shipment's stored hash. A clear code or a
 *              hash is never written to a debug log or an exception message, and
 *              a clear code never to a field.
 */
public with sharing class DeliveryAccessCode {

    private static final String ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    private static final Integer CODE_LENGTH = 12;
    private static final Integer FIVE_BIT_MASK = 31;
    private static final Integer SALT_BITS = 128;
    private static final String DIGEST = 'SHA-256';
    private static final String VERSION = 'v1';
    private static final Integer ROUNDS = 100;
    private static final Integer MAX_ROUNDS = 1000;
    private static final String SEPARATOR = '$';
    private static final String TYPING_SEPARATORS = '[\\s-]';
    private static final Pattern STORED_FORMAT =
        Pattern.compile('^v1\\$([1-9][0-9]{0,3})\\$[A-Za-z0-9+/]{22}==\\$[A-Za-z0-9+/]{43}=$');
    private static final Pattern CODE_FORMAT = Pattern.compile('^[' + ALPHABET + ']{' + CODE_LENGTH + '}$');

    // Clear codes of the rows being inserted through insertWithCodes, keyed by
    // the stored hash (unique per row thanks to its random salt): set in before
    // insert, moved to issuedCodesById in after insert of the same row.
    @TestVisible
    private static Map<String, String> pendingCodesByHash = new Map<String, String>();

    // Clear codes bound to inserted record Ids, until insertWithCodes returns them.
    @TestVisible
    private static Map<Id, String> issuedCodesById = new Map<Id, String>();

    // Lets a test observe the Id binding of a Database.insert(rows, false).
    @TestVisible
    private static Boolean captureForTest = false;

    private static Integer captureDepth = 0;

    // Ids of the shipments being reissued by reissueCodes, only for the duration
    // of that call: the before-update trigger replaces the hash only for them.
    @TestVisible
    private static Set<Id> reissuingIds = new Set<Id>();

    // Clear codes issued by the before-update trigger for the registered Ids,
    // until reissueCodes returns them.
    @TestVisible
    private static Map<Id, String> reissuedCodesById = new Map<Id, String>();

    /**
     * @description Inserts the shipments all-or-none in user mode (the running
     *              user's object and field permissions apply) and returns the
     *              clear code of each inserted shipment. The codes are removed
     *              from memory as they are returned; when the outermost call ends,
     *              every other clear code is discarded too. A failed insert throws
     *              and leaves no clear code in memory.
     * @param rows the new shipments
     * @return record Id to clear code, for exactly the given rows
     */
    public static Map<Id, String> insertWithCodes(List<Shipment__c> rows) {
        Map<Id, String> codes = new Map<Id, String>();
        if (rows == null || rows.isEmpty()) {
            return codes;
        }
        captureDepth++;
        try {
            Database.insert(rows, true, AccessLevel.USER_MODE);
            for (Shipment__c row : rows) {
                if (issuedCodesById.containsKey(row.Id)) {
                    codes.put(row.Id, issuedCodesById.remove(row.Id));
                }
            }
        } finally {
            captureDepth--;
            if (captureDepth == 0) {
                pendingCodesByHash.clear();
                issuedCodesById.clear();
            }
        }
        return codes;
    }

    /**
     * @description Sanctioned reissue (AC-F.16): gives each shipment a new code and
     *              a new salted hash, and returns the new clear codes. The shipments
     *              are updated all-or-none in user mode with no field value of the
     *              caller, so the running user needs Edit on Shipment__c and on each
     *              record (object permission and sharing apply). The Ids are
     *              registered only for the duration of the call, so the
     *              before-update trigger replaces the hash only for them; every
     *              other update keeps the stored hash. The previous codes stop
     *              matching. A failed update throws and leaves no clear code in
     *              memory.
     * @param shipmentIds the shipments whose codes are reissued
     * @return record Id to new clear code, for exactly the given Ids
     */
    public static Map<Id, String> reissueCodes(Set<Id> shipmentIds) {
        Map<Id, String> codes = new Map<Id, String>();
        if (shipmentIds == null || shipmentIds.isEmpty()) {
            return codes;
        }
        List<Shipment__c> rows = new List<Shipment__c>();
        for (Id shipmentId : shipmentIds) {
            if (shipmentId != null) {
                rows.add(new Shipment__c(Id = shipmentId));
            }
        }
        reissuingIds.addAll(shipmentIds);
        try {
            Database.update(rows, true, AccessLevel.USER_MODE);
            for (Shipment__c row : rows) {
                if (reissuedCodesById.containsKey(row.Id)) {
                    codes.put(row.Id, reissuedCodesById.get(row.Id));
                }
            }
        } finally {
            reissuingIds.clear();
            reissuedCodesById.clear();
        }
        return codes;
    }

    /**
     * @description Before update: for the shipments registered by an active
     *              reissueCodes call, issues a new code, overwrites
     *              Delivery_Access_Code_Hash__c with its iterated salted hash and
     *              binds the clear code to the record Id (the Id already exists in
     *              before update). Every other shipment is left unchanged. Runs
     *              after the protected-field revert. No SOQL or DML.
     * @param shipments the shipments being updated (Trigger.new)
     */
    public static void replaceReissuedCodes(List<Shipment__c> shipments) {
        if (shipments == null || reissuingIds.isEmpty()) {
            return;
        }
        for (Shipment__c shipment : shipments) {
            if (shipment.Id != null && reissuingIds.contains(shipment.Id)) {
                String code = generateCode();
                shipment.Delivery_Access_Code_Hash__c = hashCode(code);
                reissuedCodesById.put(shipment.Id, code);
            }
        }
    }

    /**
     * @description Checks a code typed by a person against the stored hash of one
     *              shipment (AC-F.17). The input is trimmed, upper-cased and its
     *              spaces and hyphens removed; anything that is not then 12
     *              characters of the code alphabet is rejected before any query.
     *              Reads only Delivery_Access_Code_Hash__c of that one Id, compares
     *              in constant time through matches, and never returns or logs the
     *              hash. Callers exposed to external users must rate-limit
     *              (REQ-002).
     * @param shipmentId the shipment the code is claimed for
     * @param code the typed code
     * @return true only when the code is that shipment's code; false for a blank
     *         or malformed code, or an unknown Id
     */
    public static Boolean verify(Id shipmentId, String code) {
        if (shipmentId == null || String.isBlank(code)) {
            return false;
        }
        String normalized = code.trim().replaceAll(TYPING_SEPARATORS, '').toUpperCase();
        if (!CODE_FORMAT.matcher(normalized).matches()) {
            return false;
        }
        // SECURITY-JUSTIFICATION: Delivery_Access_Code_Hash__c has no field
        // permission for any user by design (D1, AC-F.8), so the user-mode default
        // of API 67 cannot read it; this one query ignores FLS (record sharing still
        // follows the class's with sharing). Scope: only the hash field of the one
        // given Id, used only for the comparison below; the hash is never returned
        // or logged. Compensating control: constant-time comparison, and callers
        // exposed to external users must rate-limit attempts (REQ-002).
        // (pending owner approval, 2026-11-17)
        List<Shipment__c> rows = [
            SELECT Delivery_Access_Code_Hash__c
            FROM Shipment__c
            WHERE Id = :shipmentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            return false;
        }
        return matches(rows[0], normalized);
    }

    /**
     * @description Generates one clear code. Each character takes the low five
     *              bits of a cryptographically secure random integer (0-31) and
     *              rejects 31, so the 31 alphabet characters are equally likely.
     * @return a 12-character code from ABCDEFGHJKMNPQRSTUVWXYZ23456789
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
     * @description Before insert: issues a new code for every shipment and
     *              overwrites Delivery_Access_Code_Hash__c with its iterated salted
     *              hash. Inside insertWithCodes the clear code is kept, keyed by
     *              that hash, until after insert binds it to the record Id;
     *              otherwise it is discarded here. No SOQL or DML.
     * @param shipments the shipments being inserted (Trigger.new)
     */
    public static void issueCodes(List<Shipment__c> shipments) {
        if (shipments == null) {
            return;
        }
        Boolean capturing = isCapturing();
        for (Shipment__c shipment : shipments) {
            String code = generateCode();
            String stored = hashCode(code);
            shipment.Delivery_Access_Code_Hash__c = stored;
            if (capturing) {
                pendingCodesByHash.put(stored, code);
            }
        }
    }

    /**
     * @description After insert: binds each pending clear code to the Id of the
     *              record that stores its hash, and removes it from the pending
     *              codes. A row whose hash was changed after issueCodes gets no
     *              code. No SOQL or DML.
     * @param shipments the inserted shipments (Trigger.new)
     */
    public static void bindCodes(List<Shipment__c> shipments) {
        if (shipments == null || pendingCodesByHash.isEmpty()) {
            return;
        }
        for (Shipment__c shipment : shipments) {
            String code = pendingCodesByHash.remove(shipment.Delivery_Access_Code_Hash__c);
            if (code != null && shipment.Id != null) {
                issuedCodesById.put(shipment.Id, code);
            }
        }
    }

    /**
     * @description Checks a code entered by a person against the stored hash. The
     *              input is upper-cased and its spaces and hyphens are removed, so
     *              abcd-efgh-jkmn matches ABCDEFGHJKMN. The version and the rounds
     *              are read from the stored value (v1, 1 to 1000 rounds); the
     *              comparison covers every character with no early exit.
     * @param shipment a shipment with Delivery_Access_Code_Hash__c queried
     * @param code the code to check
     * @return true only when the code is the shipment's code
     */
    public static Boolean matches(Shipment__c shipment, String code) {
        if (shipment == null || String.isBlank(code)) {
            return false;
        }
        String normalized = code.replaceAll(TYPING_SEPARATORS, '').toUpperCase();
        String stored = shipment.Delivery_Access_Code_Hash__c;
        if (String.isBlank(normalized) || String.isBlank(stored)) {
            return false;
        }
        Matcher parts = STORED_FORMAT.matcher(stored);
        if (!parts.matches()) {
            return false;
        }
        Integer rounds = Integer.valueOf(parts.group(1));
        if (rounds > MAX_ROUNDS) {
            return false;
        }
        Blob salt = EncodingUtil.base64Decode(stored.split('\\' + SEPARATOR)[2]);
        return constantTimeEquals(storedValue(normalized, salt, rounds), stored);
    }

    // A new stored value for a clear code, with a fresh 128-bit salt.
    @TestVisible
    private static String hashCode(String code) {
        return storedValue(code, Crypto.generateAesKey(SALT_BITS), ROUNDS);
    }

    private static Boolean isCapturing() {
        return captureDepth > 0 || captureForTest;
    }

    // v1$<rounds>$<base64 salt>$<base64 digest>; the bytes are joined through hex.
    private static String storedValue(String code, Blob salt, Integer rounds) {
        String saltHex = EncodingUtil.convertToHex(salt);
        Blob hash = Crypto.generateDigest(DIGEST,
            EncodingUtil.convertFromHex(saltHex + EncodingUtil.convertToHex(Blob.valueOf(code))));
        for (Integer round = 2; round <= rounds; round++) {
            hash = Crypto.generateDigest(DIGEST,
                EncodingUtil.convertFromHex(saltHex + EncodingUtil.convertToHex(hash)));
        }
        return VERSION + SEPARATOR + rounds + SEPARATOR
            + EncodingUtil.base64Encode(salt) + SEPARATOR + EncodingUtil.base64Encode(hash);
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
