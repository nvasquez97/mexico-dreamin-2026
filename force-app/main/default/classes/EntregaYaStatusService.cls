/**
 * @description Applies one EntregaYa status change to a shipment (req-004 S1,
 *              decision D2). The request arrives as individual fields
 *              (EntregaYaStatusRequest, never an SObject: policy X6) and is
 *              validated in a fixed order: missing fields, tracking number
 *              (RC + 9 digits), status (exact match of the six picklist values),
 *              location (1-255 characters after trimming), timestamp (ISO-8601
 *              with a mandatory offset, not more than 10 minutes ahead of the
 *              server clock: B5), proof id for Delivered (B1) and, when a proof id
 *              is present, its format (1-100 letters, digits, hyphens or
 *              underscores: B9). The shipment is
 *              then locked with FOR UPDATE; the update is ignored when the shipment
 *              already has a Last_Update__c at or after the timestamp (B2), and is
 *              otherwise saved in user mode, so the caller's sharing and FLS apply.
 *              Lock timeouts (UNABLE_TO_LOCK_ROW on the update, or the FOR UPDATE
 *              wait timeout) become RETRYABLE and any other error INTERNAL (B7):
 *              the caller gets a closed error code and a fixed message, never
 *              exception text or field API names (X7).
 *              While apply() writes, isApplying() is true: the Shipment__c trigger
 *              refuses every other update by holders of RutaCargo_EntregaYa_Sender
 *              (AC-004.9).
 *              Limits: 1 SOQL and 1 DML per call (one POST per change).
 */
public with sharing class EntregaYaStatusService {

    /** @description What happened to the update. */
    public enum Outcome { UPDATED, IGNORED, NOT_FOUND, INVALID, RETRYABLE, INTERNAL }

    /** @description Closed list of error codes returned to EntregaYa. */
    public enum ErrorCode {
        INVALID_JSON, MISSING_FIELD, INVALID_TRACKING_NUMBER, INVALID_STATUS, INVALID_LOCATION,
        INVALID_TIMESTAMP, PROOF_ID_REQUIRED, INVALID_PROOF_ID, TRACKING_NOT_FOUND, TEMPORARILY_UNAVAILABLE,
        INTERNAL_ERROR
    }

    private static final String DELIVERED = 'Delivered';
    private static final Set<String> STATUSES = new Set<String>{
        'Requested', 'Picked up', 'In transit', 'Out for delivery', DELIVERED, 'Exception'
    };
    private static final Pattern TRACKING_FORMAT = Pattern.compile('^RC\\d{9}$');
    // yyyy-MM-ddTHH:mm:ss[.fraction](Z|+hh:mm|-hh:mm)
    private static final Pattern TIMESTAMP_FORMAT = Pattern.compile(
        '^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.\\d{1,9})?(?:(Z)|([+-])(\\d{2}):(\\d{2}))$');
    private static final Integer MAX_LOCATION_LENGTH = 255;
    private static final Integer MAX_PROOF_ID_LENGTH = 100;
    private static final Pattern PROOF_ID_FORMAT = Pattern.compile('^[A-Za-z0-9_-]{1,100}$');
    private static final Integer MAX_MINUTES_AHEAD = 10;
    private static final Integer MAX_OFFSET_MINUTES = 14 * 60;
    private static final Integer MIN_YEAR = 1700;
    private static final Integer MAX_YEAR = 4000;
    private static final String LOCK_STATUS = 'UNABLE_TO_LOCK_ROW';
    private static final String LOCK_QUERY_MESSAGE = 'Record Currently Unavailable';

    private static final Map<ErrorCode, String> MESSAGES = new Map<ErrorCode, String>{
        ErrorCode.INVALID_JSON => 'The request body is not valid JSON.',
        ErrorCode.MISSING_FIELD => 'A required field is missing.',
        ErrorCode.INVALID_TRACKING_NUMBER => 'The tracking number must be RC followed by 9 digits.',
        ErrorCode.INVALID_STATUS => 'The status is not one of the accepted values.',
        ErrorCode.INVALID_LOCATION => 'The location must have between 1 and 255 characters.',
        ErrorCode.INVALID_TIMESTAMP => 'The timestamp must be ISO-8601 with an offset and not in the future.',
        ErrorCode.PROOF_ID_REQUIRED => 'A proof id is required when the status is Delivered.',
        ErrorCode.INVALID_PROOF_ID => 'The proof id must have 1 to 100 letters, digits, hyphens or underscores.',
        ErrorCode.TRACKING_NOT_FOUND => 'No shipment has this tracking number.',
        ErrorCode.TEMPORARILY_UNAVAILABLE => 'The shipment is busy. Retry the update later.',
        ErrorCode.INTERNAL_ERROR => 'The update could not be processed.'
    };

    private static final Map<ErrorCode, Outcome> OUTCOMES = new Map<ErrorCode, Outcome>{
        ErrorCode.TRACKING_NOT_FOUND => Outcome.NOT_FOUND,
        ErrorCode.TEMPORARILY_UNAVAILABLE => Outcome.RETRYABLE,
        ErrorCode.INTERNAL_ERROR => Outcome.INTERNAL
    };

    // Test seam: when set, the clock used by the future-timestamp guard (B5).
    @TestVisible
    private static Datetime nowOverride;

    /** @description Failures a test can simulate where the update is written (B7). */
    @TestVisible
    private enum Simulation { LOCK_ON_UPDATE, LOCK_ON_QUERY, UNEXPECTED_DML, UNEXPECTED_OTHER, REAL_SAVE_ERROR }

    // Test seam (also used by T3): when set, the update is not written and the
    // matching failure happens in its place: LOCK_ON_UPDATE as the
    // UNABLE_TO_LOCK_ROW status code of the update, LOCK_ON_QUERY as the
    // QueryException of a FOR UPDATE wait timeout, UNEXPECTED_DML and
    // UNEXPECTED_OTHER as exceptions. REAL_SAVE_ERROR is the only one that
    // writes: it makes the platform refuse the real update (a location over the
    // field length, STRING_TOO_LONG), so the SaveResult carries a non-lock code.
    @TestVisible
    private static Simulation simulatedFailure;

    // True only while apply() writes its own update (AC-004.9).
    private static Boolean applying = false;

    /** @description The result of apply(): an outcome, and for failures a code and its fixed message. */
    public with sharing class Result {
        /** @description What happened to the update. */
        public final Outcome outcome;
        /** @description The error code; null when the update was applied or ignored. */
        public final ErrorCode errorCode;
        /** @description The fixed human message of the error code; null without one. */
        public final String message;

        private Result(Outcome outcome, ErrorCode errorCode) {
            this.outcome = outcome;
            this.errorCode = errorCode;
            this.message = errorCode == null ? null : MESSAGES.get(errorCode);
        }
    }

    /**
     * @description The failure result of an error code, with its outcome and fixed message.
     *              EntregaYaStatusResource uses it for INVALID_JSON.
     * @param code the error code
     * @return the failure result
     */
    public static Result failure(ErrorCode code) {
        return new Result(OUTCOMES.containsKey(code) ? OUTCOMES.get(code) : Outcome.INVALID, code);
    }

    /**
     * @description True only while apply() writes its own update. The Shipment__c
     *              trigger uses it to tell the service's update from a direct one.
     * @return whether the service is writing
     */
    public static Boolean isApplying() {
        return applying;
    }

    /**
     * @description Validates and applies one status change. Never throws.
     * @param request the status change, as individual fields
     * @return UPDATED, IGNORED, or a failure with its error code
     * @example
     * EntregaYaStatusService.Result result = EntregaYaStatusService.apply(request);
     */
    public static Result apply(EntregaYaStatusRequest request) {
        try {
            ErrorCode invalid = validate(request);
            if (invalid != null) {
                return failure(invalid);
            }
            return save(request, parseInstant(request.timestamp));
        } catch (Exception unexpected) {
            return failure(isLockTimeout(unexpected) ? ErrorCode.TEMPORARILY_UNAVAILABLE : ErrorCode.INTERNAL_ERROR);
        }
    }

    // ─── Validation ───────────────────────────────────────────────────────

    private static ErrorCode validate(EntregaYaStatusRequest request) {
        if (request == null || request.trackingNumber == null || request.status == null
                || request.location == null || request.timestamp == null) {
            return ErrorCode.MISSING_FIELD;
        }
        if (!TRACKING_FORMAT.matcher(request.trackingNumber).matches()) {
            return ErrorCode.INVALID_TRACKING_NUMBER;
        }
        if (!STATUSES.contains(request.status)) {
            return ErrorCode.INVALID_STATUS;
        }
        String location = request.location.trim();
        if (location.length() < 1 || location.length() > MAX_LOCATION_LENGTH) {
            return ErrorCode.INVALID_LOCATION;
        }
        Datetime instant = parseInstant(request.timestamp);
        if (instant == null || instant > now().addMinutes(MAX_MINUTES_AHEAD)) {
            return ErrorCode.INVALID_TIMESTAMP;
        }
        if (request.status == DELIVERED && String.isBlank(request.proofId)) {
            return ErrorCode.PROOF_ID_REQUIRED;
        }
        if (request.proofId != null && !isValidProofId(request.proofId)) {
            return ErrorCode.INVALID_PROOF_ID;
        }
        return null;
    }

    // B9: 1-100 ASCII letters, digits, hyphens or underscores. The length is checked
    // first so an oversized value never reaches the regex engine.
    private static Boolean isValidProofId(String proofId) {
        return proofId.length() <= MAX_PROOF_ID_LENGTH && PROOF_ID_FORMAT.matcher(proofId).matches();
    }

    private static Datetime now() {
        return nowOverride ?? System.now();
    }

    // The instant of an ISO-8601 timestamp with a mandatory offset, or null when it
    // is not one. Fractions of a second are dropped (stored values have whole seconds).
    private static Datetime parseInstant(String timestamp) {
        Matcher parts = TIMESTAMP_FORMAT.matcher(timestamp);
        if (!parts.matches()) {
            return null;
        }
        Integer year = Integer.valueOf(parts.group(1));
        Integer month = Integer.valueOf(parts.group(2));
        Integer day = Integer.valueOf(parts.group(3));
        Integer hour = Integer.valueOf(parts.group(4));
        Integer minute = Integer.valueOf(parts.group(5));
        Integer second = Integer.valueOf(parts.group(6));
        Integer offsetMinutes = 0;
        if (parts.group(7) == null) {
            Integer sign = parts.group(8) == '-' ? -1 : 1;
            Integer offsetHour = Integer.valueOf(parts.group(9));
            Integer offsetMinute = Integer.valueOf(parts.group(10));
            if (offsetMinute > 59) {
                return null;
            }
            offsetMinutes = sign * (offsetHour * 60 + offsetMinute);
        }
        if (year < MIN_YEAR || year > MAX_YEAR || month < 1 || month > 12 || day < 1
                || day > Date.daysInMonth(year, month) || hour > 23 || minute > 59 || second > 59
                || Math.abs(offsetMinutes) > MAX_OFFSET_MINUTES) {
            return null;
        }
        return Datetime.newInstanceGmt(year, month, day, hour, minute, second).addMinutes(-offsetMinutes);
    }

    // ─── Persistence ──────────────────────────────────────────────────────

    private static Result save(EntregaYaStatusRequest request, Datetime instant) {
        String trackingNumber = request.trackingNumber;
        List<Shipment__c> matches = [
            SELECT Id, Last_Update__c
            FROM Shipment__c
            WHERE Name = :trackingNumber
            WITH USER_MODE
            LIMIT 1
            FOR UPDATE
        ];
        if (matches.isEmpty()) {
            return failure(ErrorCode.TRACKING_NOT_FOUND);
        }
        Shipment__c current = matches[0];
        if (current.Last_Update__c != null && instant <= current.Last_Update__c) {
            return new Result(Outcome.IGNORED, null);
        }
        Shipment__c change = new Shipment__c(
            Id = current.Id,
            Status__c = request.status,
            Last_Location__c = request.location.trim(),
            Last_Update__c = instant
        );
        if (request.status == DELIVERED) {
            change.Delivered_At__c = instant;
            change.Proof_Id__c = request.proofId.trim();
        }
        StatusCode failedWith;
        applying = true;
        try {
            failedWith = write(change);
        } finally {
            applying = false;
        }
        if (failedWith == null) {
            return new Result(Outcome.UPDATED, null);
        }
        return failure(failedWith == StatusCode.UNABLE_TO_LOCK_ROW
            ? ErrorCode.TEMPORARILY_UNAVAILABLE : ErrorCode.INTERNAL_ERROR);
    }

    // Writes the change in user mode; returns null on success, else the status code
    // of the first error (the save is not all-or-none, so a failed save does not throw).
    private static StatusCode write(Shipment__c change) {
        switch on simulatedFailure {
            when LOCK_ON_UPDATE {
                return StatusCode.UNABLE_TO_LOCK_ROW;
            }
            when LOCK_ON_QUERY {
                throw new QueryException(LOCK_QUERY_MESSAGE + ': simulated lock wait timeout');
            }
            when UNEXPECTED_DML {
                throw new DmlException('FIELD_CUSTOM_VALIDATION_EXCEPTION on Shipment__c.Status__c (simulated)');
            }
            when UNEXPECTED_OTHER {
                throw new NullPointerException();
            }
            when REAL_SAVE_ERROR {
                change.Last_Location__c = 'x'.repeat(MAX_LOCATION_LENGTH + 1);
            }
        }
        Database.SaveResult result = Database.update(change, false, AccessLevel.USER_MODE);
        return result.isSuccess() ? null : result.getErrors()[0].getStatusCode();
    }

    // The QueryException that FOR UPDATE throws when the lock wait times out. It
    // carries no StatusCode, so its message is matched. Never call getNumDml() or
    // getDmlType() here: on a DmlException without DML rows they throw an
    // uncatchable System.UnexpectedException.
    private static Boolean isLockTimeout(Exception unexpected) {
        if (!(unexpected instanceof QueryException)) {
            return false;
        }
        String message = unexpected.getMessage() ?? '';
        return message.contains(LOCK_STATUS) || message.startsWith(LOCK_QUERY_MESSAGE);
    }
}
