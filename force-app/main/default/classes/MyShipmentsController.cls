/**
 * @description "My shipments" of registered customers on the site
 *              (odd/tasks/req-006-007-customer-shipments.md, S4; REQ-007).
 *              listShipments returns the customer's own shipments, most recent
 *              first, at most 200 (G3), filtered by a status of the closed
 *              picklist and searched by tracking number, recipient or reference
 *              (trimmed, at most 50 characters, LIKE wildcards escaped, bound:
 *              P8); getShipment returns the detail of one own shipment by its
 *              tracking number. Both read in user mode with sharing (the sharing
 *              set gives each customer the shipments of their account) and keep
 *              only the rows whose Account__c is the user's own account (defense
 *              in depth, BR-07; a separate Id-only filter, since customers cannot
 *              read Account__c): another customer's or an unknown tracking number
 *              is the same "not found". The DTOs carry no record or account Id and
 *              no internal field (BR-03); the detail leaves out the recipient's
 *              address, phone, email and the delivery instructions (BR-02, G7).
 *              Dates are Mexico City time (BR-06). Errors are generic.
 */
public with sharing class MyShipmentsController {

    /** @description The generic refusal for a caller without a customer account (guest, internal user). */
    public static final String NOT_AVAILABLE_MESSAGE = 'This service is available only to signed-in customers.';
    /** @description The generic message for a status outside the picklist or a search that is too long. */
    public static final String INVALID_FILTER_MESSAGE = 'Check the status filter and the search text.';
    /** @description The one answer for another customer's, an unknown or a malformed tracking number. */
    public static final String NOT_FOUND_MESSAGE = 'Shipment not found.';

    private static final Integer MAX_ROWS = 200;
    private static final Integer MAX_SEARCH_LENGTH = 50;
    private static final String GUEST_USER_TYPE = 'Guest';
    private static final String DATE_TIME_FORMAT = 'yyyy-MM-dd HH:mm';
    private static final Pattern TRACKING_FORMAT = Pattern.compile('^RC\\d{9}$');
    // Constant fragments only: the client's values are always binds.
    private static final String LIST_QUERY = 'SELECT Id, Name, CreatedDate, Recipient_Name__c, Destination_City__c, '
        + 'Status__c, Service_Type__c, Price__c FROM Shipment__c';
    private static final String STATUS_CONDITION = 'Status__c = :status';
    private static final String SEARCH_CONDITION =
        '(Name LIKE :pattern OR Recipient_Name__c LIKE :pattern OR Customer_Reference__c LIKE :pattern)';
    private static final String LIST_ORDER = ' ORDER BY CreatedDate DESC, Name DESC LIMIT :maxRows';

    /** @description One row of the list: exactly the seven AC-007.1 fields. */
    public class ShipmentRow {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String requestDate;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String status;
        @AuraEnabled public String serviceType;
        @AuraEnabled public Decimal price;
    }

    /** @description The detail of one shipment (AC-007.3). */
    public class ShipmentDetail {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String requestDate;
        @AuraEnabled public String status;
        @AuraEnabled public String serviceType;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Date estimatedDelivery;
        @AuraEnabled public String lastUpdate;
        @AuraEnabled public String lastLocation;
        @AuraEnabled public String pickupAddress;
        @AuraEnabled public String pickupCity;
        @AuraEnabled public String pickupPostalCode;
        @AuraEnabled public Date pickupDate;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String destinationPostalCode;
        @AuraEnabled public Decimal weightKg;
        @AuraEnabled public String packageDescription;
        @AuraEnabled public Decimal declaredValue;
        @AuraEnabled public String customerReference;
    }

    /**
     * @description The customer's own shipments, most recent first, at most 200 (AC-007.1, AC-007.2).
     * @param status a Status__c picklist value, or blank for every status
     * @param searchTerm part of a tracking number, recipient name or reference, or blank
     * @return the rows
     * @throws AuraHandledException a generic refusal or the generic filter error
     */
    @AuraEnabled
    public static List<ShipmentRow> listShipments(String status, String searchTerm) {
        Id accountId = requireCustomerAccount();
        String statusFilter = String.isBlank(status) ? null : status.trim();
        String search = String.isBlank(searchTerm) ? null : searchTerm.trim();
        if ((statusFilter != null && !statusValues().contains(statusFilter))
            || (search != null && search.length() > MAX_SEARCH_LENGTH)) {
            throw userError(INVALID_FILTER_MESSAGE);
        }
        Map<String, Object> binds = new Map<String, Object>{ 'maxRows' => MAX_ROWS };
        List<String> conditions = new List<String>();
        if (statusFilter != null) {
            conditions.add(STATUS_CONDITION);
            binds.put('status', statusFilter);
        }
        if (search != null) {
            conditions.add(SEARCH_CONDITION);
            binds.put('pattern', '%' + escapeLike(search) + '%');
        }
        String query = LIST_QUERY + (conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ')) + LIST_ORDER;
        List<Shipment__c> visible = (List<Shipment__c>) runQuery(query, binds);
        Set<Id> own = ownShipmentIds(visible, accountId);
        List<ShipmentRow> rows = new List<ShipmentRow>();
        for (Shipment__c shipment : visible) {
            if (own.contains(shipment.Id)) {
                rows.add(toRow(shipment));
            }
        }
        return rows;
    }

    /**
     * @description The detail of one of the customer's own shipments (AC-007.3).
     * @param trackingNumber the tracking number (RC + 9 digits)
     * @return the detail
     * @throws AuraHandledException a generic refusal or "not found"
     */
    @AuraEnabled
    public static ShipmentDetail getShipment(String trackingNumber) {
        Id accountId = requireCustomerAccount();
        String tracking = String.isBlank(trackingNumber) ? '' : trackingNumber.trim();
        if (!TRACKING_FORMAT.matcher(tracking).matches()) {
            throw userError(NOT_FOUND_MESSAGE);
        }
        List<Shipment__c> found;
        try {
            found = [
                SELECT Id, Name, CreatedDate, Status__c, Service_Type__c, Price__c, Estimated_Delivery__c, Last_Update__c,
                    Last_Location__c, Pickup_Address__c, Origin_City__c, Pickup_Postal_Code__c, Pickup_Date__c,
                    Recipient_Name__c, Destination_City__c, Destination_Postal_Code__c, Weight_Kg__c,
                    Package_Description__c, Declared_Value__c, Customer_Reference__c
                FROM Shipment__c
                WHERE Name = :tracking
                WITH USER_MODE
                LIMIT 1
            ];
        } catch (QueryException e) {
            throw userError(NOT_AVAILABLE_MESSAGE);
        }
        if (found.isEmpty() || ownShipmentIds(found, accountId).isEmpty()) {
            throw userError(NOT_FOUND_MESSAGE);
        }
        return toDetail(found[0]);
    }

    // BR-07: only a signed-in user with a customer account (User.AccountId).
    private static Id requireCustomerAccount() {
        if (UserInfo.getUserType() == GUEST_USER_TYPE) {
            throw userError(NOT_AVAILABLE_MESSAGE);
        }
        Id accountId = ShipmentRequestRules.customerAccountId();
        if (accountId == null) {
            throw userError(NOT_AVAILABLE_MESSAGE);
        }
        return accountId;
    }

    // S4 defense in depth (BR-07): of the shipments the user may read (user
    // mode with sharing), only those of the user's own account.
    private static Set<Id> ownShipmentIds(List<Shipment__c> visible, Id accountId) {
        // SECURITY-JUSTIFICATION: a customer user cannot read Shipment__c.Account__c
        // in user mode ("No such column 'Account__c'"): it is a required lookup,
        // which takes no field permission ("You cannot deploy to a required
        // field"), and customers get no Read on Account (G2, G8). Scope: the Ids
        // already returned to this user by a user-mode query, the Account__c
        // filter only; only Ids come back and nothing is sent to the client.
        // Compensating control: it can only remove rows from what sharing and
        // FLS already allow, never add one. (pending owner approval, 2026-11-18)
        return new Map<Id, Shipment__c>([
            SELECT Id FROM Shipment__c WHERE Id IN :visible AND Account__c = :accountId WITH SYSTEM_MODE
        ]).keySet();
    }

    // User mode with sharing; the query text is built from constants only.
    private static List<SObject> runQuery(String query, Map<String, Object> binds) {
        try {
            return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
        } catch (QueryException e) {
            throw userError(NOT_AVAILABLE_MESSAGE);
        }
    }

    // The closed list of statuses (P8): the active Status__c picklist values.
    private static Set<String> statusValues() {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : Shipment__c.Status__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    // "%", "_" and the escape character itself match literally (P8).
    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }

    private static String inMexicoCity(Datetime value) {
        return value == null ? null : value.format(DATE_TIME_FORMAT, ShipmentRequestRules.MEXICO_CITY_TIME_ZONE);
    }

    private static ShipmentRow toRow(Shipment__c shipment) {
        ShipmentRow row = new ShipmentRow();
        row.trackingNumber = shipment.Name;
        row.requestDate = inMexicoCity(shipment.CreatedDate);
        row.recipientName = shipment.Recipient_Name__c;
        row.destinationCity = shipment.Destination_City__c;
        row.status = shipment.Status__c;
        row.serviceType = shipment.Service_Type__c;
        row.price = shipment.Price__c;
        return row;
    }

    private static ShipmentDetail toDetail(Shipment__c shipment) {
        ShipmentDetail detail = new ShipmentDetail();
        detail.trackingNumber = shipment.Name;
        detail.requestDate = inMexicoCity(shipment.CreatedDate);
        detail.status = shipment.Status__c;
        detail.serviceType = shipment.Service_Type__c;
        detail.price = shipment.Price__c;
        detail.estimatedDelivery = shipment.Estimated_Delivery__c;
        detail.lastUpdate = inMexicoCity(shipment.Last_Update__c);
        detail.lastLocation = shipment.Last_Location__c;
        detail.pickupAddress = shipment.Pickup_Address__c;
        detail.pickupCity = shipment.Origin_City__c;
        detail.pickupPostalCode = shipment.Pickup_Postal_Code__c;
        detail.pickupDate = shipment.Pickup_Date__c;
        detail.recipientName = shipment.Recipient_Name__c;
        detail.destinationCity = shipment.Destination_City__c;
        detail.destinationPostalCode = shipment.Destination_Postal_Code__c;
        detail.weightKg = shipment.Weight_Kg__c;
        detail.packageDescription = shipment.Package_Description__c;
        detail.declaredValue = shipment.Declared_Value__c;
        detail.customerReference = shipment.Customer_Reference__c;
        return detail;
    }

    private static AuraHandledException userError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
