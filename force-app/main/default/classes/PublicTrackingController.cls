/**
 * @description Public shipment tracking for the RutaCargo site, callable by the
 *              site guest user without login (req-001 S1, BR-01). Searches up to
 *              10 values by tracking number or by order reference and returns
 *              only the BR-01 fields of at most 50 shipments, through the
 *              justified PublicTrackingSelector. Not cacheable: the site caches
 *              guest Apex responses on the CDN (enableApexCDNCaching, P5).
 *              Every rejection and every unexpected error reaches the caller as
 *              an AuraHandledException with a fixed generic message (X7); a miss
 *              is always just "not found", whatever the reason (P4).
 */
public with sharing class PublicTrackingController {

    @TestVisible
    private static final String COUNT_MESSAGE = 'Enter up to 10 values.';
    @TestVisible
    private static final String GENERIC_MESSAGE = 'We could not complete the search. Please try again.';
    private static final String MODE_TRACKING_NUMBER = 'TRACKING_NUMBER';
    private static final String MODE_REFERENCE = 'REFERENCE';
    // Closed list of modes; Set.contains is case-sensitive.
    private static final Set<String> MODES = new Set<String>{ MODE_TRACKING_NUMBER, MODE_REFERENCE };
    private static final Integer MAX_RAW_ENTRIES = 100;
    private static final Integer MAX_VALUES = 10;
    private static final Integer MAX_VALUE_LENGTH = 50;
    private static final Integer MAX_RESULTS = 50;
    private static final Pattern TRACKING_FORMAT = Pattern.compile('^RC\\d{9}$');
    // The visitor separates values with commas or line breaks (REQ-001).
    private static final String VALUE_SEPARATORS = '[,\\r\\n]';
    private static final String MEXICO_CITY = 'America/Mexico_City';
    private static final String LAST_UPDATE_FORMAT = 'yyyy-MM-dd HH:mm';
    private static final String ISO_DATE_FORMAT = 'yyyy-MM-dd';

    /** @description Test seam: when true, search fails with an unexpected exception (AC-001.1, X7). */
    @TestVisible
    private static Boolean failForTest = false;

    /** @description A rejection whose message is safe to show to the caller. */
    private class SearchRejectedException extends Exception {}

    /** @description An unexpected failure raised by the test seam. */
    private class SearchFailureException extends Exception {}

    /**
     * @description Searches shipments for an anonymous visitor.
     * @param mode TRACKING_NUMBER or REFERENCE (closed list)
     * @param values at most 100 entries; each may hold several values separated
     *               by commas or line breaks; at most 10 distinct values after
     *               trimming and case-insensitive de-duplication
     * @return the BR-01 results, the values not found and the truncation flag
     * @throws AuraHandledException with "Enter up to 10 values." for too many
     *         values, or "We could not complete the search. Please try again."
     *         for anything else
     */
    @AuraEnabled
    public static PublicTrackingResult search(String mode, List<String> values) {
        try {
            return runSearch(mode, values);
        } catch (SearchRejectedException rejected) {
            throw userError(rejected.getMessage());
        } catch (Exception unexpected) {
            throw userError(GENERIC_MESSAGE);
        }
    }

    private static PublicTrackingResult runSearch(String mode, List<String> values) {
        if (values != null && values.size() > MAX_RAW_ENTRIES) {
            throw new SearchRejectedException(COUNT_MESSAGE);
        }
        if (mode == null || !MODES.contains(mode)) {
            throw new SearchRejectedException(GENERIC_MESSAGE);
        }
        if (failForTest) {
            throw new SearchFailureException('Internal failure raised by the test seam');
        }
        Boolean byTrackingNumber = mode.equals(MODE_TRACKING_NUMBER);
        Map<String, String> spellingByKey = new Map<String, String>();
        List<String> keys = normalize(values, spellingByKey);
        List<Shipment__c> rows = selectRows(byTrackingNumber, queryableKeys(keys, byTrackingNumber));
        return buildResult(rows, keys, spellingByKey, byTrackingNumber);
    }

    // Splits, trims, drops empties and de-duplicates case-insensitively. Returns
    // the upper-case keys in input order; spellingByKey keeps the first spelling.
    private static List<String> normalize(List<String> values, Map<String, String> spellingByKey) {
        List<String> keys = new List<String>();
        if (values == null) {
            return keys;
        }
        for (String entry : values) {
            if (entry == null) {
                continue;
            }
            for (String piece : entry.split(VALUE_SEPARATORS)) {
                String trimmed = piece.trim();
                String key = trimmed.toUpperCase();
                if (trimmed.length() == 0 || spellingByKey.containsKey(key)) {
                    continue;
                }
                if (keys.size() == MAX_VALUES) {
                    throw new SearchRejectedException(COUNT_MESSAGE);
                }
                keys.add(key);
                spellingByKey.put(key, trimmed);
            }
        }
        return keys;
    }

    // Values worth a query: at most 50 characters and, by tracking number, ^RC\d{9}$.
    private static Set<String> queryableKeys(List<String> keys, Boolean byTrackingNumber) {
        Set<String> queryable = new Set<String>();
        for (String key : keys) {
            Boolean fits = key.length() <= MAX_VALUE_LENGTH;
            if (fits && (!byTrackingNumber || TRACKING_FORMAT.matcher(key).matches())) {
                queryable.add(key);
            }
        }
        return queryable;
    }

    private static List<Shipment__c> selectRows(Boolean byTrackingNumber, Set<String> queryable) {
        if (queryable.isEmpty()) {
            return new List<Shipment__c>();
        }
        return byTrackingNumber
            ? PublicTrackingSelector.selectByTrackingNumbers(queryable)
            : PublicTrackingSelector.selectByReferences(queryable);
    }

    private static PublicTrackingResult buildResult(
        List<Shipment__c> rows, List<String> keys, Map<String, String> spellingByKey, Boolean byTrackingNumber
    ) {
        PublicTrackingResult result = new PublicTrackingResult();
        result.truncated = rows.size() > MAX_RESULTS;
        Set<String> matchedKeys = new Set<String>();
        for (Integer i = 0; i < rows.size() && i < MAX_RESULTS; i++) {
            Shipment__c row = rows[i];
            result.results.add(toTrackedShipment(row));
            String matched = byTrackingNumber ? row.Name : row.Customer_Reference__c;
            matchedKeys.add(matched == null ? '' : matched.toUpperCase());
        }
        if (result.truncated) {
            // A value cut off by the cap is not proven missing.
            return result;
        }
        for (String key : keys) {
            if (!matchedKeys.contains(key)) {
                result.notFound.add(spellingByKey.get(key));
            }
        }
        return result;
    }

    private static PublicTrackingResult.TrackedShipment toTrackedShipment(Shipment__c row) {
        PublicTrackingResult.TrackedShipment shipment = new PublicTrackingResult.TrackedShipment();
        shipment.trackingNumber = row.Name;
        shipment.status = row.Status__c;
        shipment.originCity = row.Origin_City__c;
        shipment.destinationCity = row.Destination_City__c;
        shipment.lastLocation = row.Last_Location__c;
        shipment.lastUpdate = row.Last_Update__c?.format(LAST_UPDATE_FORMAT, MEXICO_CITY);
        shipment.estimatedDelivery = row.Estimated_Delivery__c == null
            ? null
            : Datetime.newInstanceGmt(row.Estimated_Delivery__c, Time.newInstance(0, 0, 0, 0)).formatGmt(ISO_DATE_FORMAT);
        return shipment;
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
