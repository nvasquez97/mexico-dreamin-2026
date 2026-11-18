/**
 * @description Stateless verification of a recipient on the public site
 *              (req-002-003 S1; owner decision D1; hardening-1 S1; policy X16,
 *              P1, P10, P11): tracking number + destination postal code +
 *              delivery access code, all as individual Strings from the caller,
 *              never a record Id.
 *              Reads the shipment by Name in system mode with no row lock. The
 *              attempt guard is kept per PAIR (shipment, typed postal code): its
 *              Shipment_Key__c is the shipment Id, ":" and the hex SHA-256 of the
 *              typed postal code normalized exactly as the comparison does
 *              (whitespace removed, upper case; a blank value hashes a fixed
 *              empty token). For an existing shipment the pair's row, if any, is
 *              read FOR UPDATE before anything is compared, and a locked pair is
 *              refused before any hash work. Otherwise the postal code is
 *              compared and DeliveryAccessCode.matches runs exactly once on every
 *              path: an unknown tracking number, a wrong postal code or a
 *              malformed code is checked against a decoy stored value, so every
 *              failure costs the same hash work (E2). Every failure returns the
 *              same outcome and message, and EVERY failure for an existing
 *              shipment is counted on the pair of the postal code that was typed,
 *              whatever it is: the right postal code and any other one answer the
 *              same way (5 x NOT_MATCHED, then LOCKED), so the lock reveals
 *              nothing, and a guest who does not know the recipient's postal code
 *              only locks pairs that are not the recipient's (SEC-002). Unknown
 *              tracking numbers never create a guard. The guard row is written by
 *              upsert on Shipment_Key__c, then re-read FOR UPDATE; 5 consecutive
 *              counted failures lock the pair for 15 minutes and the counter
 *              stays at 5 while it is locked; a failure that finds the row
 *              already locked (a parallel first request on a pair that had no
 *              row yet) is not counted; a success makes no DML here and
 *              resetAttempts resets a non-zero counter of the verified pair.
 *              Guard rows keyed on the shipment Id alone (written before
 *              hardening-1) match no pair key and are ignored.
 *              Failures and the lock are RETURNED, never thrown, so the guard DML
 *              commits on the site. The only Shipment__c write is saveReschedule,
 *              which sets Estimated_Delivery__c, Delivery_Instructions__c and
 *              Reschedule_Count__c only; every other write touches only
 *              Recipient_Access_Guard__c. The pair key and its hash are never
 *              returned or logged.
 */
// SECURITY-JUSTIFICATION: the site guest user has no object permission and no
// sharing on Shipment__c or Recipient_Access_Guard__c (project rule: the guest
// receives no object permissions), so the verified recipient's read of one
// shipment, the per-pair attempt counter and the reschedule write must run without
// sharing and in system mode. Scope: one shipment found by the exact tracking
// number the caller typed (bind variable, never an Id from the client); reads only
// the fields of the delivery details plus the hash for the comparison (never
// returned); writes only the guard row of the (shipment, typed postal code) pair
// and, after a successful verification, the three reschedule fields. Compensating
// control: a 12-character random access code checked in constant time against an
// iterated salted hash, the postal code, identical failure responses with equal
// hash work for every postal code, and a lock of 15 minutes after 5 failures per
// pair, read FOR UPDATE before the comparison (D1, X16, SEC-002, SEC-011). Callers
// are RecipientDeliveryController (with sharing) only.
// (pending owner approval, 2026-11-18)
public without sharing class RecipientAccess {

    public static final String NOT_MATCHED_MESSAGE = 'The details do not match this shipment';
    public static final String LOCKED_MESSAGE = 'Too many attempts. Please try again in 15 minutes.';
    @TestVisible
    private static final Integer MAX_FAILED_ATTEMPTS = 5;
    @TestVisible
    private static final Integer LOCK_MINUTES = 15;
    private static final Integer MAX_TRACKING_NUMBER_LENGTH = 80;
    private static final String WHITESPACE = '\\s';
    private static final String TYPING_SEPARATORS = '[\\s-]';
    private static final Pattern CODE_FORMAT = Pattern.compile('^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$');
    // A well-formed v1 stored value with a fixed, public salt and the same rounds
    // as a real one: checked when there is no shipment to check against, so the
    // hash work is the same. It can never match.
    private static final String DECOY_STORED_VALUE =
        'v1$100$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    // Checked instead of a malformed or blank code: 12 characters outside the code
    // alphabet, so it can never match a real code.
    private static final String FILLER_CODE = '000000000000';

    // Pair key: shipment Id + KEY_SEPARATOR + hex SHA-256 of the normalized typed
    // postal code; a blank postal code hashes this fixed token.
    private static final String KEY_SEPARATOR = ':';
    private static final String BLANK_POSTAL_CODE_TOKEN = '';
    private static final String PAIR_DIGEST = 'SHA-256';

    // Test seam for "now" (AC-H1.3: the lock expires on the clock).
    @TestVisible
    private static Datetime nowOverride;

    // Test seam: when not null, records the order of the steps of a verification
    // (AC-H1.3: the pair row is read FOR UPDATE before the code comparison). It
    // holds step names only, never a key, a hash or a typed value.
    @TestVisible
    private static List<String> trace;

    /** @description Result of a verification. */
    public enum Outcome { VERIFIED, NOT_MATCHED, LOCKED }

    /**
     * @description The result of one verification. Built only by this class; the
     *              shipment it carries has the delivery-detail fields and no Id or
     *              hash. Callers keep it on the server and never receive it from a
     *              client.
     */
    public with sharing class Verification {
        /** @description VERIFIED, NOT_MATCHED or LOCKED. */
        public Outcome outcome { get; private set; }
        /** @description The message for the recipient; null when verified. */
        public String message { get; private set; }
        /** @description The verified tracking number (the shipment's Name); null otherwise. */
        public String trackingNumber { get; private set; }
        /** @description The verified shipment's detail fields (no Id, no hash); null otherwise. */
        public Shipment__c shipment { get; private set; }
        private Id shipmentId;
        private String pairKey;
        private Decimal failedAttempts;
        private Shipment__c lockedRow;

        private Verification(Outcome outcome, String message) {
            this.outcome = outcome;
            this.message = message;
        }

        /**
         * @description Whether the three values matched.
         * @return true only for VERIFIED
         */
        public Boolean isVerified() {
            return outcome == RecipientAccess.Outcome.VERIFIED;
        }
    }

    /**
     * @description Verifies and records the result: a counted failure on the
     *              typed pair's guard, or a reset of a non-zero counter of the
     *              verified pair on success. Used by
     *              getDeliveryDetails and rescheduleDelivery.
     * @param trackingNumber the tracking number typed by the recipient
     * @param postalCode the destination postal code typed by the recipient
     * @param accessCode the delivery access code typed by the recipient
     * @return the verification (never null, never thrown)
     */
    public static Verification verify(String trackingNumber, String postalCode, String accessCode) {
        Verification result = verifyBeforeCallout(trackingNumber, postalCode, accessCode);
        resetAttempts(result);
        return result;
    }

    /**
     * @description Verifies without any DML on success, for a caller that makes
     *              a callout next (T2 downloadProof): an existing guard row of the
     *              typed pair is read FOR UPDATE before the comparison, and a
     *              counted failure is still written to it. After the callout the
     *              caller calls resetAttempts.
     * @param trackingNumber the tracking number typed by the recipient
     * @param postalCode the destination postal code typed by the recipient
     * @param accessCode the delivery access code typed by the recipient
     * @return the verification (never null, never thrown)
     */
    public static Verification verifyBeforeCallout(String trackingNumber, String postalCode, String accessCode) {
        Shipment__c row = findShipment(trackingNumber);
        String pairKey = row == null ? null : pairKeyOf(row.Id, postalCode);
        Recipient_Access_Guard__c guard = pairKey == null ? null : lockPairGuard(pairKey);
        if (isLocked(guard)) {
            return new Verification(Outcome.LOCKED, LOCKED_MESSAGE);
        }
        Boolean postalMatches = row != null && normalizedPostalCode(row.Destination_Postal_Code__c) != null
            && normalizedPostalCode(row.Destination_Postal_Code__c) == normalizedPostalCode(postalCode);
        String code = String.isBlank(accessCode) ? '' : accessCode.replaceAll(TYPING_SEPARATORS, '').toUpperCase();
        Boolean wellFormed = CODE_FORMAT.matcher(code).matches();
        Boolean checkRow = postalMatches && wellFormed && String.isNotBlank(row.Delivery_Access_Code_Hash__c);
        // Exactly one hash computation on every path that reaches here (E2).
        Shipment__c target = checkRow ? row : new Shipment__c(Delivery_Access_Code_Hash__c = DECOY_STORED_VALUE);
        note('codeCompared');
        Boolean codeMatches = DeliveryAccessCode.matches(target, wellFormed ? code : FILLER_CODE);
        if (checkRow && codeMatches) {
            return verified(row, guard, pairKey);
        }
        // Every failure for an existing shipment counts on the typed pair (SEC-002).
        if (row != null) {
            countFailure(row.Id, pairKey);
        }
        return new Verification(Outcome.NOT_MATCHED, NOT_MATCHED_MESSAGE);
    }

    /**
     * @description Resets a non-zero attempt counter of the verified pair,
     *              locking only its guard row. Does nothing otherwise.
     * @param verification a result of verify or verifyBeforeCallout
     */
    public static void resetAttempts(Verification verification) {
        if (verification == null || !verification.isVerified()
                || verification.failedAttempts == null || verification.failedAttempts == 0) {
            return;
        }
        List<Recipient_Access_Guard__c> guards = [
            SELECT Id, Failed_Attempts__c FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :verification.pairKey
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (!guards.isEmpty() && guards[0].Failed_Attempts__c != 0) {
            guards[0].Failed_Attempts__c = 0;
            Database.update(guards, AccessLevel.SYSTEM_MODE);
        }
        verification.failedAttempts = 0;
    }

    /**
     * @description Locks the verified shipment FOR UPDATE for a reschedule and
     *              returns its current detail fields (no Id, no hash), so the
     *              caller checks the rules on the locked values.
     * @param verification a VERIFIED result of verify
     * @return the locked shipment's detail fields
     */
    public static Shipment__c lockForReschedule(Verification verification) {
        requireVerified(verification);
        Shipment__c locked = [
            SELECT Id, Name, Status__c, Recipient_Name__c, Recipient_Address__c, Destination_City__c,
                Destination_Postal_Code__c, Recipient_Phone__c, Estimated_Delivery__c,
                Original_Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c, Proof_Id__c
            FROM Shipment__c
            WHERE Id = :verification.shipmentId
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        verification.lockedRow = locked;
        return detailsOf(locked);
    }

    /**
     * @description Saves a reschedule of the shipment locked by lockForReschedule:
     *              sets ONLY Estimated_Delivery__c, Delivery_Instructions__c and
     *              Reschedule_Count__c (the locked count, null as 0, plus 1).
     *              The caller has checked the rules on the locked values.
     * @param verification the VERIFIED result passed to lockForReschedule
     * @param newDate the new estimated delivery date
     * @param instructions the new delivery instructions, or null to clear them
     * @return the shipment's refreshed detail fields
     */
    public static Shipment__c saveReschedule(Verification verification, Date newDate, String instructions) {
        requireVerified(verification);
        if (verification.lockedRow == null || newDate == null) {
            throw new RecipientAccessException('Lock the shipment before saving a reschedule.');
        }
        Decimal count = verification.lockedRow.Reschedule_Count__c ?? 0;
        Database.update(new Shipment__c(
            Id = verification.shipmentId,
            Estimated_Delivery__c = newDate,
            Delivery_Instructions__c = instructions,
            Reschedule_Count__c = count + 1
        ), AccessLevel.SYSTEM_MODE);
        verification.lockedRow = null;
        return lockForReschedule(verification);
    }

    /** @description Thrown when the API is misused by server code (never by a recipient's input). */
    public with sharing class RecipientAccessException extends Exception {}

    // ─── Internals ───────────────────────────────────────────────────────

    // The shipment with this exact tracking number (trimmed, upper case), or null.
    private static Shipment__c findShipment(String trackingNumber) {
        String name = String.isBlank(trackingNumber) ? '' : trackingNumber.trim().toUpperCase();
        if (String.isBlank(name) || name.length() > MAX_TRACKING_NUMBER_LENGTH) {
            return null;
        }
        List<Shipment__c> rows = [
            SELECT Id, Name, Status__c, Recipient_Name__c, Recipient_Address__c, Destination_City__c,
                Destination_Postal_Code__c, Recipient_Phone__c, Estimated_Delivery__c,
                Original_Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c, Proof_Id__c,
                Delivery_Access_Code_Hash__c
            FROM Shipment__c
            WHERE Name = :name
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    // The guard key of the pair (shipment, typed postal code): the 18-character
    // shipment Id, ":" and the hex SHA-256 of exactly normalizedPostalCode(typed),
    // or of a fixed token when it is blank. Never returned or logged.
    private static String pairKeyOf(Id shipmentId, String typedPostalCode) {
        String token = normalizedPostalCode(typedPostalCode) ?? BLANK_POSTAL_CODE_TOKEN;
        Blob digest = Crypto.generateDigest(PAIR_DIGEST, Blob.valueOf(token));
        return String.valueOf(shipmentId) + KEY_SEPARATOR + EncodingUtil.convertToHex(digest);
    }

    // The existing guard row of the pair, read FOR UPDATE before the comparison,
    // so parallel requests on the pair are serialized (SEC-011); null when the
    // pair has no row yet. A SELECT FOR UPDATE is not DML: the callout of
    // downloadProof may follow.
    private static Recipient_Access_Guard__c lockPairGuard(String pairKey) {
        List<Recipient_Access_Guard__c> guards = [
            SELECT Id, Failed_Attempts__c, Locked_Until__c FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :pairKey
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        note(guards.isEmpty() ? 'pairReadForUpdate:none' : 'pairReadForUpdate:row');
        return guards.isEmpty() ? null : guards[0];
    }

    private static Boolean isLocked(Recipient_Access_Guard__c guard) {
        return guard != null && guard.Locked_Until__c != null && guard.Locked_Until__c > now();
    }

    private static Datetime now() {
        return nowOverride ?? Datetime.now();
    }

    private static void note(String step) {
        if (trace != null) {
            trace.add(step);
        }
    }

    private static String normalizedPostalCode(String value) {
        return String.isBlank(value) ? null : value.replaceAll(WHITESPACE, '').toUpperCase();
    }

    private static Verification verified(Shipment__c row, Recipient_Access_Guard__c guard, String pairKey) {
        Verification result = new Verification(Outcome.VERIFIED, null);
        result.shipmentId = row.Id;
        result.pairKey = pairKey;
        result.trackingNumber = row.Name;
        result.shipment = detailsOf(row);
        result.failedAttempts = guard?.Failed_Attempts__c;
        return result;
    }

    // A copy with the detail fields only: no Id, no Name, no hash.
    private static Shipment__c detailsOf(Shipment__c row) {
        return new Shipment__c(
            Status__c = row.Status__c,
            Recipient_Name__c = row.Recipient_Name__c,
            Recipient_Address__c = row.Recipient_Address__c,
            Destination_City__c = row.Destination_City__c,
            Destination_Postal_Code__c = row.Destination_Postal_Code__c,
            Recipient_Phone__c = row.Recipient_Phone__c,
            Estimated_Delivery__c = row.Estimated_Delivery__c,
            Original_Estimated_Delivery__c = row.Original_Estimated_Delivery__c,
            Delivery_Instructions__c = row.Delivery_Instructions__c,
            Reschedule_Count__c = row.Reschedule_Count__c,
            Proof_Id__c = row.Proof_Id__c
        );
    }

    // Counts one failure on the typed pair: the guard row is created or touched by
    // upsert on Shipment_Key__c (one row per pair, and the row is locked by that
    // write), re-read FOR UPDATE and re-checked: a row that is already locked is
    // not counted (CODE-001, X16: a parallel first request on a pair that had no
    // row when it was read); otherwise incremented, and the fifth failure locks
    // the pair for 15 minutes with the counter kept at 5.
    @TestVisible
    private static void countFailure(Id shipmentId, String key) {
        upsertGuard(new Recipient_Access_Guard__c(Shipment__c = shipmentId, Shipment_Key__c = key));
        Recipient_Access_Guard__c guard = [
            SELECT Id, Failed_Attempts__c, Locked_Until__c FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :key
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (isLocked(guard)) {
            return;
        }
        Decimal failures = (guard.Failed_Attempts__c ?? 0) + 1;
        if (failures >= MAX_FAILED_ATTEMPTS) {
            guard.Locked_Until__c = now().addMinutes(LOCK_MINUTES);
            failures = MAX_FAILED_ATTEMPTS;
        }
        guard.Failed_Attempts__c = failures;
        Database.update(guard, AccessLevel.SYSTEM_MODE);
        note('failureCounted');
    }

    // Upsert on the unique external Id; a concurrent first insert of the same key
    // makes this one fail with DUPLICATE_VALUE, so it is retried once (then the
    // row exists and the upsert updates it).
    private static void upsertGuard(Recipient_Access_Guard__c guard) {
        try {
            Database.upsert(guard, Recipient_Access_Guard__c.Shipment_Key__c, true, AccessLevel.SYSTEM_MODE);
        } catch (DmlException duplicate) {
            if (duplicate.getDmlType(0) != StatusCode.DUPLICATE_VALUE) {
                throw duplicate;
            }
            guard.Id = null;
            Database.upsert(guard, Recipient_Access_Guard__c.Shipment_Key__c, true, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void requireVerified(Verification verification) {
        if (verification == null || !verification.isVerified() || verification.shipmentId == null) {
            throw new RecipientAccessException('Only a verified recipient can change a shipment.');
        }
    }
}
