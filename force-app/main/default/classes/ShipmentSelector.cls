/**
 * All Shipment__c queries used by the site and the carrier service.
 *
 * SHARING JUSTIFICATION: Shipment__c is Private and is deliberately not shared with guest or
 * external users (no object permissions). Visitors, recipients and customers reach shipments only
 * through the services that call this selector, and each service restricts the rows itself
 * (tracking number or reference for BR-01, postal code for BR-02, caller's account for BR-07).
 * Hence the queries use system mode explicitly. Callers must never pass client-supplied
 * field names or sort expressions; sort orders are chosen from a closed list here.
 */
public without sharing class ShipmentSelector {
    public static final Set<String> STATUSES = new Set<String>{
        'Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'
    };
    public static final Integer MAX_ROWS = 200;

    /**
     * @param trackingNumbers tracking numbers (case-insensitive match)
     * @param sortBy status, estimatedDelivery or blank
     * @return public-tracking rows
     */
    public static List<Shipment__c> byTrackingNumbers(Set<String> trackingNumbers, String sortBy) {
        if (sortBy == 'status') {
            return [
                SELECT Id, Name, Status__c, Origin_City__c, Destination_City__c, Last_Location__c, Last_Update__c, Estimated_Delivery__c
                FROM Shipment__c WHERE Name IN :trackingNumbers
                WITH SYSTEM_MODE ORDER BY Status__c, Name LIMIT :MAX_ROWS
            ];
        }
        return [
            SELECT Id, Name, Status__c, Origin_City__c, Destination_City__c, Last_Location__c, Last_Update__c, Estimated_Delivery__c
            FROM Shipment__c WHERE Name IN :trackingNumbers
            WITH SYSTEM_MODE ORDER BY Estimated_Delivery__c NULLS LAST, Name LIMIT :MAX_ROWS
        ];
    }

    /**
     * @param references customer order references (case-insensitive match)
     * @param sortBy status, estimatedDelivery or blank
     * @return public-tracking rows
     */
    public static List<Shipment__c> byReferences(Set<String> references, String sortBy) {
        if (sortBy == 'status') {
            return [
                SELECT Id, Name, Status__c, Origin_City__c, Destination_City__c, Last_Location__c, Last_Update__c, Estimated_Delivery__c, Customer_Reference__c
                FROM Shipment__c WHERE Customer_Reference__c IN :references
                WITH SYSTEM_MODE ORDER BY Status__c, Name LIMIT :MAX_ROWS
            ];
        }
        return [
            SELECT Id, Name, Status__c, Origin_City__c, Destination_City__c, Last_Location__c, Last_Update__c, Estimated_Delivery__c, Customer_Reference__c
            FROM Shipment__c WHERE Customer_Reference__c IN :references
            WITH SYSTEM_MODE ORDER BY Estimated_Delivery__c NULLS LAST, Name LIMIT :MAX_ROWS
        ];
    }

    /**
     * Row for the recipient flows. Locks the row so verification counters and reschedules are serialized.
     * @param trackingNumber exact tracking number
     * @return the shipment or null
     */
    public static Shipment__c forRecipientUpdate(String trackingNumber) {
        List<Shipment__c> rows = [
            SELECT Id, Name, Status__c, Recipient_Name__c, Recipient_Address__c, Recipient_Phone__c,
                   Destination_Postal_Code__c, Estimated_Delivery__c, Original_Estimated_Delivery__c,
                   Delivery_Instructions__c, Reschedule_Count__c, Proof_Id__c, Failed_Verifications__c, Locked_Until__c
            FROM Shipment__c WHERE Name = :trackingNumber
            WITH SYSTEM_MODE LIMIT 1 FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Row for the carrier status service. Locks the row (concurrent updates for the same shipment).
     * @param trackingNumber exact tracking number
     * @return the shipment or null
     */
    public static Shipment__c forStatusUpdate(String trackingNumber) {
        List<Shipment__c> rows = [
            SELECT Id, Name, Status__c, Last_Update__c
            FROM Shipment__c WHERE Name = :trackingNumber
            WITH SYSTEM_MODE LIMIT 1 FOR UPDATE
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @param accountId the caller's account (derived server-side, BR-07)
     * @param status optional status filter (validated against the closed list by the caller)
     * @param term optional search term over tracking number, recipient and reference
     * @return the account's shipments, newest first
     */
    public static List<Shipment__c> forAccount(Id accountId, String status, String term) {
        // Query text is assembled only from the fixed fragments below; user input travels as bind variables.
        String soql = 'SELECT Id, Name, CreatedDate, Recipient_Name__c, Destination_City__c, Status__c, Service_Type__c, Price__c, Customer_Reference__c ' +
            'FROM Shipment__c WHERE Account__c = :accountId';
        Map<String, Object> binds = new Map<String, Object>{ 'accountId' => accountId, 'maxRows' => MAX_ROWS };
        if (!String.isBlank(status)) {
            soql += ' AND Status__c = :statusFilter';
            binds.put('statusFilter', status);
        }
        if (!String.isBlank(term)) {
            soql += ' AND (Name LIKE :likeTerm OR Recipient_Name__c LIKE :likeTerm OR Customer_Reference__c LIKE :likeTerm)';
            binds.put('likeTerm', '%' + term.trim() + '%');
        }
        soql += ' ORDER BY CreatedDate DESC, Name DESC LIMIT :maxRows';
        return (List<Shipment__c>) Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /**
     * @param accountId the caller's account
     * @param trackingNumber exact tracking number
     * @return the shipment if it belongs to the account, else null
     */
    public static Shipment__c oneForAccount(Id accountId, String trackingNumber) {
        List<Shipment__c> rows = [
            SELECT Id, Name, CreatedDate, Recipient_Name__c, Destination_City__c, Status__c, Service_Type__c, Price__c,
                   Customer_Reference__c, Pickup_Address__c, Pickup_Postal_Code__c, Pickup_Date__c, Origin_City__c,
                   Recipient_Address__c, Destination_Postal_Code__c, Recipient_Phone__c, Recipient_Email__c,
                   Delivery_Instructions__c, Package_Description__c, Weight_Kg__c, Declared_Value__c, Estimated_Delivery__c
            FROM Shipment__c WHERE Account__c = :accountId AND Name = :trackingNumber
            WITH SYSTEM_MODE LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }
}
