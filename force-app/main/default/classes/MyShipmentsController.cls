/**
 * "My shipments" for registered customers (REQ-007).
 *
 * WITH SHARING and USER MODE: customers read Shipment__c through the
 * RutaCargo_Customer permission set and the RutaCargo Customers sharing set.
 * As defence in depth every query is also filtered by the account taken from
 * the session (BR-07). Only customer-facing fields are selected: never
 * carrier cost, margin, internal notes or credit data (BR-03).
 */
public with sharing class MyShipmentsController {
    private static final Integer MAX_ROWS = 200;
    private static final Set<String> STATUSES = new Set<String>{
        'Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'
    };

    /** One row of the list (AC-007.1). */
    public class ShipmentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Datetime requestDate;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String status;
        @AuraEnabled public String serviceType;
        @AuraEnabled public Decimal price;
    }

    /** Detail page: what the customer entered, the price and the current status (AC-007.3). */
    public class ShipmentDetail {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime requestDate;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String serviceType;
        @AuraEnabled public String pickupAddress;
        @AuraEnabled public String originCity;
        @AuraEnabled public String pickupPostalCode;
        @AuraEnabled public Date pickupDate;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String recipientAddress;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String destinationPostalCode;
        @AuraEnabled public String recipientPhone;
        @AuraEnabled public String recipientEmail;
        @AuraEnabled public String packageDescription;
        @AuraEnabled public Decimal weightKg;
        @AuraEnabled public Decimal declaredValue;
        @AuraEnabled public String customerReference;
        @AuraEnabled public String deliveryInstructions;
        @AuraEnabled public Date estimatedDelivery;
        @AuraEnabled public String lastLocation;
        @AuraEnabled public Datetime lastUpdate;
    }

    /**
     * @param status optional status filter from the closed list (AC-007.2)
     * @param searchTerm optional text matched against tracking number, recipient or reference
     * @return the customer's shipments, most recent first (at most 200)
     */
    @AuraEnabled
    public static List<ShipmentRow> getMyShipments(String status, String searchTerm) {
        Id accountId = CustomerContext.getCurrentAccountId();
        if (String.isNotBlank(status) && !STATUSES.contains(status)) {
            throw AuraErrors.of('Choose a valid status.');
        }
        // Only fixed fragments are concatenated; every user value travels as a bind variable.
        String soql = 'SELECT Id, Name, CreatedDate, Recipient_Name__c, Destination_City__c, Status__c, Service_Type__c, Price__c ' +
            'FROM Shipment__c WHERE Account__c = :accountId';
        Map<String, Object> binds = new Map<String, Object>{ 'accountId' => accountId, 'maxRows' => MAX_ROWS };
        if (String.isNotBlank(status)) {
            soql += ' AND Status__c = :status';
            binds.put('status', status);
        }
        if (String.isNotBlank(searchTerm)) {
            soql += ' AND (Name LIKE :likeTerm OR Recipient_Name__c LIKE :likeTerm OR Customer_Reference__c LIKE :likeTerm)';
            binds.put('likeTerm', '%' + escapeLike(searchTerm.trim().left(80)) + '%');
        }
        soql += ' ORDER BY CreatedDate DESC, Name DESC LIMIT :maxRows';
        List<ShipmentRow> rows = new List<ShipmentRow>();
        for (Shipment__c s : (List<Shipment__c>) Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
            ShipmentRow row = new ShipmentRow();
            row.id = s.Id;
            row.trackingNumber = s.Name;
            row.requestDate = s.CreatedDate;
            row.recipientName = s.Recipient_Name__c;
            row.destinationCity = s.Destination_City__c;
            row.status = s.Status__c;
            row.serviceType = s.Service_Type__c;
            row.price = s.Price__c;
            rows.add(row);
        }
        return rows;
    }

    /**
     * @param shipmentId id of one of the customer's shipments
     * @return the shipment detail
     * @throws AuraHandledException "Shipment not found." when it does not exist or belongs to another customer
     */
    @AuraEnabled
    public static ShipmentDetail getShipmentDetail(Id shipmentId) {
        Id accountId = CustomerContext.getCurrentAccountId();
        List<Shipment__c> rows = [
            SELECT Name, Status__c, CreatedDate, Price__c, Service_Type__c, Pickup_Address__c, Origin_City__c,
                Pickup_Postal_Code__c, Pickup_Date__c, Recipient_Name__c, Recipient_Address__c, Destination_City__c,
                Destination_Postal_Code__c, Recipient_Phone__c, Recipient_Email__c, Package_Description__c,
                Weight_Kg__c, Declared_Value__c, Customer_Reference__c, Delivery_Instructions__c,
                Estimated_Delivery__c, Last_Location__c, Last_Update__c
            FROM Shipment__c
            WHERE Id = :shipmentId AND Account__c = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw AuraErrors.of('Shipment not found.');
        }
        return toDetail(rows[0]);
    }

    private static ShipmentDetail toDetail(Shipment__c s) {
        ShipmentDetail d = new ShipmentDetail();
        d.trackingNumber = s.Name;
        d.status = s.Status__c;
        d.requestDate = s.CreatedDate;
        d.price = s.Price__c;
        d.serviceType = s.Service_Type__c;
        d.pickupAddress = s.Pickup_Address__c;
        d.originCity = s.Origin_City__c;
        d.pickupPostalCode = s.Pickup_Postal_Code__c;
        d.pickupDate = s.Pickup_Date__c;
        d.recipientName = s.Recipient_Name__c;
        d.recipientAddress = s.Recipient_Address__c;
        d.destinationCity = s.Destination_City__c;
        d.destinationPostalCode = s.Destination_Postal_Code__c;
        d.recipientPhone = s.Recipient_Phone__c;
        d.recipientEmail = s.Recipient_Email__c;
        d.packageDescription = s.Package_Description__c;
        d.weightKg = s.Weight_Kg__c;
        d.declaredValue = s.Declared_Value__c;
        d.customerReference = s.Customer_Reference__c;
        d.deliveryInstructions = s.Delivery_Instructions__c;
        d.estimatedDelivery = s.Estimated_Delivery__c;
        d.lastLocation = s.Last_Location__c;
        d.lastUpdate = s.Last_Update__c;
        return d;
    }

    /** Escapes LIKE wildcards so the customer's text is matched literally (AC-007.2). */
    private static String escapeLike(String value) {
        return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
    }
}
