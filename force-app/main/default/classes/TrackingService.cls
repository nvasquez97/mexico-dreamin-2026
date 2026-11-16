/**
 * Public tracking (REQ-001). Callable by anyone, including the guest user.
 *
 * SHARING JUSTIFICATION: runs in system mode through ShipmentSelector because the guest user has no
 * object permissions on Shipment__c. Exposure is limited by construction: the caller must know the
 * tracking number or order reference (BR-01), at most 10 values are accepted, and the DTO carries
 * only the AC-001.2 fields.
 */
public without sharing class TrackingService {
    public static final Integer MAX_VALUES = 10;
    public static final String BY_TRACKING = 'trackingNumber';
    public static final String BY_REFERENCE = 'reference';

    public class TrackingException extends Exception {
    }

    /**
     * @param searchBy trackingNumber or reference (closed list)
     * @param rawValues up to 10 values separated by commas or line breaks
     * @param sortBy status, estimatedDelivery or blank (closed list)
     * @return found shipments and the values that matched nothing
     * @throws TrackingException on invalid input
     */
    public static RutaCargoDtos.TrackingResponse search(String searchBy, String rawValues, String sortBy) {
        if (searchBy != BY_TRACKING && searchBy != BY_REFERENCE) {
            throw new TrackingException('Choose to search by tracking number or by order reference.');
        }
        String safeSort = (sortBy == 'status' || sortBy == 'estimatedDelivery') ? sortBy : 'estimatedDelivery';
        List<String> values = parseValues(rawValues);
        if (values.isEmpty()) {
            throw new TrackingException('Enter at least one value.');
        }
        if (values.size() > MAX_VALUES) {
            throw new TrackingException('Enter up to ' + MAX_VALUES + ' values.');
        }
        Set<String> lookup = new Set<String>(values);
        List<Shipment__c> rows = searchBy == BY_TRACKING
            ? ShipmentSelector.byTrackingNumbers(lookup, safeSort)
            : ShipmentSelector.byReferences(lookup, safeSort);

        RutaCargoDtos.TrackingResponse response = new RutaCargoDtos.TrackingResponse();
        Set<String> matchedKeys = new Set<String>();
        for (Shipment__c row : rows) {
            RutaCargoDtos.TrackedShipment item = new RutaCargoDtos.TrackedShipment();
            item.trackingNumber = row.Name;
            item.status = row.Status__c;
            item.originCity = row.Origin_City__c;
            item.destinationCity = row.Destination_City__c;
            item.lastLocation = row.Last_Location__c;
            item.lastUpdate = row.Last_Update__c;
            item.estimatedDelivery = row.Estimated_Delivery__c;
            response.found.add(item);
            matchedKeys.add((searchBy == BY_TRACKING ? row.Name : row.Customer_Reference__c).toLowerCase());
        }
        for (String value : values) {
            if (!matchedKeys.contains(value.toLowerCase())) {
                response.notFound.add(value);
            }
        }
        return response;
    }

    /**
     * Splits on commas and line breaks, trims, drops blanks and case-insensitive duplicates (AC-001.1, AC-001.5).
     * @param rawValues raw user input
     * @return clean values in input order
     */
    public static List<String> parseValues(String rawValues) {
        List<String> result = new List<String>();
        if (String.isBlank(rawValues)) {
            return result;
        }
        Set<String> seen = new Set<String>();
        for (String part : rawValues.split('[,\\r\\n]+')) {
            String value = part.trim();
            if (value.length() > 0 && value.length() <= 80 && seen.add(value.toLowerCase())) {
                result.add(value);
            }
        }
        return result;
    }
}
