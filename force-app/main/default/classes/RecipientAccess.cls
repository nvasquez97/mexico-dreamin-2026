/**
 * @description Stateless verification of a recipient on the public site
 *              (req-002-003 S1; owner decision D1; policy X16, P1, P10, P11):
 *              tracking number + destination postal code + delivery access code,
 *              all as individual Strings from the caller, never a record Id.
 *              Reads the shipment by Name in system mode with no row lock, refuses
 *              a shipment locked by its Recipient_Access_Guard__c row before any
 *              hash work, compares the postal code (trimmed, spaces removed, any
 *              case) and ALWAYS runs DeliveryAccessCode.matches exactly once: an
 *              unknown tracking number, a wrong postal code or a malformed code
 *              is checked against a decoy stored value, so every failure costs the
 *              same hash work (E2). Every failure returns the same outcome and
 *              message. Only failures with the right postal code and a wrong code
 *              are counted on the guard row (upsert on Shipment_Key__c, then
 *              FOR UPDATE); 5 consecutive counted failures lock the shipment for 15
 *              minutes and reset the counter; a success resets a non-zero counter.
 *              Failures and the lock are RETURNED, never thrown, so the guard DML
 *              commits on the site. The only Shipment__c write is saveReschedule,
 *              which sets Estimated_Delivery__c, Delivery_Instructions__c and
 *              Reschedule_Count__c only; every other write touches only
 *              Recipient_Access_Guard__c.
 */
// SECURITY-JUSTIFICATION: the site guest user has no object permission and no
// sharing on Shipment__c or Recipient_Access_Guard__c (project rule: the guest
// receives no object permissions), so the verified recipient's read of one
// shipment, the attempt counter and the reschedule write must run without sharing
// and in system mode. Scope: one shipment found by the exact tracking number the
// caller typed (bind variable, never an Id from the client); reads only the fields
// of the delivery details plus the hash for the comparison (never returned); writes
// only the guard row and, after a successful verification, the three reschedule
// fields. Compensating control: a 12-character random access code checked in
// constant time against an iterated salted hash, the postal code, identical failure
// responses with equal hash work, and a lock of 15 minutes after 5 failures
// (D1, X16). Callers are RecipientDeliveryController (with sharing) only.
// (pending owner approval, 2026-11-17)
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
     *              guard, or a reset of a non-zero counter on success. Used by
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
     * @description Verifies without any DML or lock on success, for a caller that
     *              makes a callout next (T2 downloadProof): a counted failure is
     *              still written to the guard. After the callout the caller
     *              calls resetAttempts.
     * @param trackingNumber the tracking number typed by the recipient
     * @param postalCode the destination postal code typed by the recipient
     * @param accessCode the delivery access code typed by the recipient
     * @return the verification (never null, never thrown)
     */
    public static Verification verifyBeforeCallout(String trackingNumber, String postalCode, String accessCode) {
        Shipment__c row = findShipment(trackingNumber);
        Recipient_Access_Guard__c guard = row == null ? null : findGuard(row.Id);
        if (guard != null && guard.Locked_Until__c != null && guard.Locked_Until__c > Datetime.now()) {
            return new Verification(Outcome.LOCKED, LOCKED_MESSAGE);
        }
        Boolean postalMatches = row != null && normalizedPostalCode(row.Destination_Postal_Code__c) != null
            && normalizedPostalCode(row.Destination_Postal_Code__c) == normalizedPostalCode(postalCode);
        String code = String.isBlank(accessCode) ? '' : accessCode.replaceAll(TYPING_SEPARATORS, '').toUpperCase();
        Boolean wellFormed = CODE_FORMAT.matcher(code).matches();
        Boolean checkRow = postalMatches && wellFormed && String.isNotBlank(row.Delivery_Access_Code_Hash__c);
        // Exactly one hash computation on every path that reaches here (E2).
        Shipment__c target = checkRow ? row : new Shipment__c(Delivery_Access_Code_Hash__c = DECOY_STORED_VALUE);
        Boolean codeMatches = DeliveryAccessCode.matches(target, wellFormed ? code : FILLER_CODE);
        if (checkRow && codeMatches) {
            return verified(row, guard);
        }
        if (postalMatches) {
            countFailure(row.Id);
        }
        return new Verification(Outcome.NOT_MATCHED, NOT_MATCHED_MESSAGE);
    }

    /**
     * @description Resets a non-zero attempt counter of a verified shipment,
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
            WHERE Shipment_Key__c = :String.valueOf(verification.shipmentId)
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
    public class RecipientAccessException extends Exception {}

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

    private static Recipient_Access_Guard__c findGuard(Id shipmentId) {
        List<Recipient_Access_Guard__c> guards = [
            SELECT Id, Failed_Attempts__c, Locked_Until__c FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :String.valueOf(shipmentId)
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return guards.isEmpty() ? null : guards[0];
    }

    private static String normalizedPostalCode(String value) {
        return String.isBlank(value) ? null : value.replaceAll(WHITESPACE, '').toUpperCase();
    }

    private static Verification verified(Shipment__c row, Recipient_Access_Guard__c guard) {
        Verification result = new Verification(Outcome.VERIFIED, null);
        result.shipmentId = row.Id;
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

    // Counts one failure with the right postal code: the guard row is created or
    // touched by upsert on Shipment_Key__c (one row per shipment, and the row is
    // locked by that write), re-read FOR UPDATE, incremented; the fifth failure
    // locks the shipment for 15 minutes and resets the counter.
    private static void countFailure(Id shipmentId) {
        String key = String.valueOf(shipmentId);
        upsertGuard(new Recipient_Access_Guard__c(Shipment__c = shipmentId, Shipment_Key__c = key));
        Recipient_Access_Guard__c guard = [
            SELECT Id, Failed_Attempts__c, Locked_Until__c FROM Recipient_Access_Guard__c
            WHERE Shipment_Key__c = :key
            WITH SYSTEM_MODE
            LIMIT 1
            FOR UPDATE
        ];
        Decimal failures = (guard.Failed_Attempts__c ?? 0) + 1;
        if (failures >= MAX_FAILED_ATTEMPTS) {
            guard.Locked_Until__c = Datetime.now().addMinutes(LOCK_MINUTES);
            failures = 0;
        }
        guard.Failed_Attempts__c = failures;
        Database.update(guard, AccessLevel.SYSTEM_MODE);
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
