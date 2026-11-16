/**
 * Public shipment tracking for site visitors without login (REQ-001).
 *
 * Runs WITHOUT SHARING and in SYSTEM MODE on purpose: the site guest user has
 * no object permissions (project security rule), and BR-01 makes the status of
 * any shipment public to whoever has its tracking number or reference.
 * Exposure is limited by: a closed list of search modes and sort orders, bind
 * variables only, at most 10 values, and a response that carries ONLY the
 * AC-001.2 fields (no recipient, price, customer or internal data).
 */
public without sharing class PublicTrackingController {
    public static final Integer MAX_VALUES = 10;
    private static final Integer MAX_ROWS = 100;
    private static final Pattern TRACKING_PATTERN = Pattern.compile('^RC[0-9]{9}$');
    private static final Set<String> SEARCH_MODES = new Set<String>{ 'trackingNumber', 'reference' };
    private static final Set<String> SORT_ORDERS = new Set<String>{ 'status', 'estimatedDelivery' };
    /** Lifecycle order used when sorting by status (AC-001.4). */
    private static final List<String> STATUS_ORDER = new List<String>{
        'Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'
    };

    /** Response: shipments found plus the values that matched nothing (AC-001.3). */
    public class TrackingResult {
        @AuraEnabled public List<ShipmentStatus> shipments = new List<ShipmentStatus>();
        @AuraEnabled public List<String> notFound = new List<String>();
    }

    /** Public view of a shipment: exactly the fields listed in AC-001.2 (BR-01). */
    public class ShipmentStatus {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String originCity;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String lastLocation;
        @AuraEnabled public Datetime lastUpdate;
        @AuraEnabled public Date estimatedDelivery;
    }

    /**
     * @param searchBy trackingNumber or reference (AC-001.1)
     * @param rawValues up to 10 values separated by commas or line breaks
     * @param sortBy status or estimatedDelivery (AC-001.4)
     * @return shipments found and values not found
     * @throws AuraHandledException with a user-facing message on invalid input
     */
    @AuraEnabled
    public static TrackingResult track(String searchBy, String rawValues, String sortBy) {
        if (!SEARCH_MODES.contains(searchBy)) {
            throw AuraErrors.of('Choose a valid search: tracking number or order reference.');
        }
        if (!SORT_ORDERS.contains(sortBy)) {
            throw AuraErrors.of('Choose a valid sort: status or estimated delivery date.');
        }
        Map<String, String> originalByKey = parseValues(rawValues);
        List<Shipment__c> rows = searchBy == 'trackingNumber'
            ? queryByTrackingNumber(originalByKey)
            : queryByReference(originalByKey.keySet());
        return buildResult(searchBy, originalByKey, rows, sortBy);
    }

    /** Splits, trims and de-duplicates ignoring case (AC-001.1, AC-001.5). Key = lower case. */
    private static Map<String, String> parseValues(String rawValues) {
        Map<String, String> originalByKey = new Map<String, String>();
        for (String part : (rawValues ?? '').split('[,\\r\\n]+')) {
            String value = part.trim();
            if (String.isNotBlank(value) && !originalByKey.containsKey(value.toLowerCase())) {
                originalByKey.put(value.toLowerCase(), value);
            }
        }
        if (originalByKey.isEmpty()) {
            throw AuraErrors.of('Enter at least one tracking number or order reference.');
        }
        if (originalByKey.size() > MAX_VALUES) {
            throw AuraErrors.of('You can search up to 10 values at a time.');
        }
        return originalByKey;
    }

    private static List<Shipment__c> queryByTrackingNumber(Map<String, String> originalByKey) {
        Set<String> trackingNumbers = new Set<String>();
        for (String key : originalByKey.keySet()) {
            String candidate = key.toUpperCase();
            if (TRACKING_PATTERN.matcher(candidate).matches()) {
                trackingNumbers.add(candidate);
            }
        }
        if (trackingNumbers.isEmpty()) {
            return new List<Shipment__c>();
        }
        // System mode: see class comment. Only public fields are selected.
        return [
            SELECT Name, Customer_Reference__c, Status__c, Origin_City__c, Destination_City__c,
                Last_Location__c, Last_Update__c, Estimated_Delivery__c
            FROM Shipment__c
            WHERE Name IN :trackingNumbers
            WITH SYSTEM_MODE
            LIMIT :MAX_ROWS
        ];
    }

    private static List<Shipment__c> queryByReference(Set<String> references) {
        // SOQL equality on text ignores case (AC-001.5). System mode: see class comment.
        return [
            SELECT Name, Customer_Reference__c, Status__c, Origin_City__c, Destination_City__c,
                Last_Location__c, Last_Update__c, Estimated_Delivery__c
            FROM Shipment__c
            WHERE Customer_Reference__c IN :references
            WITH SYSTEM_MODE
            LIMIT :MAX_ROWS
        ];
    }

    private static TrackingResult buildResult(
        String searchBy, Map<String, String> originalByKey, List<Shipment__c> rows, String sortBy
    ) {
        TrackingResult result = new TrackingResult();
        Set<String> matchedKeys = new Set<String>();
        for (Shipment__c row : rows) {
            String key = (searchBy == 'trackingNumber' ? row.Name : row.Customer_Reference__c).toLowerCase();
            matchedKeys.add(key);
            result.shipments.add(toPublicStatus(row));
        }
        for (String key : originalByKey.keySet()) {
            if (!matchedKeys.contains(key)) {
                result.notFound.add(originalByKey.get(key));
            }
        }
        sortShipments(result.shipments, sortBy);
        return result;
    }

    private static ShipmentStatus toPublicStatus(Shipment__c row) {
        ShipmentStatus item = new ShipmentStatus();
        item.trackingNumber = row.Name;
        item.status = row.Status__c;
        item.originCity = row.Origin_City__c;
        item.destinationCity = row.Destination_City__c;
        item.lastLocation = row.Last_Location__c;
        item.lastUpdate = row.Last_Update__c;
        item.estimatedDelivery = row.Estimated_Delivery__c;
        return item;
    }

    private static void sortShipments(List<ShipmentStatus> shipments, String sortBy) {
        List<SortableStatus> sortable = new List<SortableStatus>();
        for (ShipmentStatus item : shipments) {
            sortable.add(new SortableStatus(item, sortBy));
        }
        sortable.sort();
        shipments.clear();
        for (SortableStatus entry : sortable) {
            shipments.add(entry.item);
        }
    }

    private class SortableStatus implements Comparable {
        private final ShipmentStatus item;
        private final String sortBy;

        SortableStatus(ShipmentStatus item, String sortBy) {
            this.item = item;
            this.sortBy = sortBy;
        }

        public Integer compareTo(Object other) {
            ShipmentStatus that = ((SortableStatus) other).item;
            Integer byKey = sortBy == 'status' ? compareStatus(item, that) : compareEstimated(item, that);
            return byKey != 0 ? byKey : item.trackingNumber.compareTo(that.trackingNumber);
        }

        private Integer compareStatus(ShipmentStatus a, ShipmentStatus b) {
            return STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status);
        }

        private Integer compareEstimated(ShipmentStatus a, ShipmentStatus b) {
            if (a.estimatedDelivery == b.estimatedDelivery) {
                return 0;
            }
            if (a.estimatedDelivery == null) {
                return 1;
            }
            if (b.estimatedDelivery == null) {
                return -1;
            }
            return a.estimatedDelivery < b.estimatedDelivery ? -1 : 1;
        }
    }
}
