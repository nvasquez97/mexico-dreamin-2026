/**
 * Apex for the logged-in customer pages: quote, request a shipment, my shipments (REQ-006, REQ-007).
 *
 * Runs without sharing (external users have no record access to Shipment__c, OWD Private) but EVERY query
 * is scoped to the Account of the running user's Contact (BR-07) and selects explicit fields, so
 * transport cost, margin, internal notes and credit data can never leave (BR-03).
 */
public without sharing class CustomerPortalController {
    private static final Integer PAGE_SIZE = 25;
    private static final Integer MAX_OFFSET = 2000;

    public class ShipmentInput {
        @AuraEnabled public String pickupAddress;
        @AuraEnabled public String pickupCity;
        @AuraEnabled public String pickupPostalCode;
        @AuraEnabled public Date pickupDate;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String recipientAddress;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String destinationPostalCode;
        @AuraEnabled public String recipientPhone;
        @AuraEnabled public String recipientEmail;
        @AuraEnabled public String serviceType;
        @AuraEnabled public Decimal weightKg;
        @AuraEnabled public String packageDescription;
        @AuraEnabled public Decimal declaredValue;
        @AuraEnabled public String customerReference;
        @AuraEnabled public String deliveryInstructions;
    }

    public class CreatedShipment {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Date estimatedDelivery;
    }

    public class MyShipment {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Datetime requestedAt;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String status;
        @AuraEnabled public String serviceType;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String customerReference;
    }

    public class MyShipmentsPage {
        @AuraEnabled public List<MyShipment> shipments = new List<MyShipment>();
        @AuraEnabled public Boolean hasMore = false;
    }

    public class ShipmentDetail {
        @AuraEnabled public MyShipment summary;
        @AuraEnabled public ShipmentInput input;
        @AuraEnabled public Date estimatedDelivery;
        @AuraEnabled public String lastLocation;
        @AuraEnabled public Datetime lastUpdate;
    }

    /** AC-006.2: price shown before confirming. */
    @AuraEnabled
    public static Decimal quote(String serviceType, Decimal weightKg, Decimal declaredValue) {
        currentAccountId();
        validateWeightAndValue(weightKg, declaredValue);
        return ShipmentPricing.calculate(serviceType, weightKg, declaredValue);
    }

    @AuraEnabled
    public static CreatedShipment createShipment(Map<String, Object> form) {
        Id accountId = currentAccountId();
        ShipmentInput i = fromForm(form);
        validate(i);
        Date est = ShipmentRules.estimatedDelivery(i.pickupDate, i.serviceType);
        // BR-08/BR-09: price and status are decided here, never taken from the browser
        Shipment__c s = new Shipment__c(
            Account__c = accountId,
            Status__c = 'Requested',
            Service_Type__c = i.serviceType,
            Pickup_Address__c = i.pickupAddress.trim(),
            Origin_City__c = i.pickupCity.trim(),
            Pickup_Postal_Code__c = i.pickupPostalCode.trim(),
            Pickup_Date__c = i.pickupDate,
            Recipient_Name__c = i.recipientName.trim(),
            Recipient_Address__c = i.recipientAddress.trim(),
            Destination_City__c = i.destinationCity.trim(),
            Destination_Postal_Code__c = i.destinationPostalCode.trim(),
            Recipient_Phone__c = i.recipientPhone.trim(),
            Recipient_Email__c = i.recipientEmail.trim(),
            Package_Description__c = i.packageDescription.trim(),
            Weight_Kg__c = i.weightKg,
            Declared_Value__c = i.declaredValue,
            Customer_Reference__c = blankToNull(i.customerReference),
            Delivery_Instructions__c = blankToNull(i.deliveryInstructions),
            Price__c = ShipmentPricing.calculate(i.serviceType, i.weightKg, i.declaredValue),
            Estimated_Delivery__c = est,
            Original_Estimated_Delivery__c = est,
            Reschedule_Count__c = 0
        );
        Database.insert(s, AccessLevel.SYSTEM_MODE);
        Shipment__c saved = [SELECT Name, Price__c, Estimated_Delivery__c FROM Shipment__c WHERE Id = :s.Id WITH SYSTEM_MODE];
        CreatedShipment out = new CreatedShipment();
        out.trackingNumber = saved.Name;
        out.price = saved.Price__c;
        out.estimatedDelivery = saved.Estimated_Delivery__c;
        return out;
    }

    /** AC-007.1 / AC-007.2: most recent first, filter by status, search by tracking, recipient or reference. */
    @AuraEnabled
    public static MyShipmentsPage listShipments(String status, String searchTerm, Integer offset) {
        Id accountId = currentAccountId();
        Integer off = Math.min(Math.max(offset == null ? 0 : offset, 0), MAX_OFFSET);
        Map<String, Object> binds = new Map<String, Object>{ 'accountId' => accountId, 'pageSize' => PAGE_SIZE + 1, 'off' => off };
        String soql = 'SELECT Name, CreatedDate, Recipient_Name__c, Destination_City__c, Status__c, Service_Type__c, Price__c, '
            + 'Customer_Reference__c FROM Shipment__c WHERE Account__c = :accountId';
        if (String.isNotBlank(status)) {
            soql += ' AND Status__c = :status';
            binds.put('status', status);
        }
        if (String.isNotBlank(searchTerm)) {
            soql += ' AND (Name LIKE :term OR Recipient_Name__c LIKE :term OR Customer_Reference__c LIKE :term)';
            binds.put('term', '%' + String.escapeSingleQuotes(searchTerm.trim()).replace('%', '\\%').replace('_', '\\_') + '%');
        }
        soql += ' ORDER BY CreatedDate DESC, Id DESC LIMIT :pageSize OFFSET :off';
        List<Shipment__c> rows = Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);

        MyShipmentsPage page = new MyShipmentsPage();
        for (Integer n = 0; n < rows.size() && n < PAGE_SIZE; n++) {
            page.shipments.add(toSummary(rows[n]));
        }
        page.hasMore = rows.size() > PAGE_SIZE && off + PAGE_SIZE <= MAX_OFFSET;
        return page;
    }

    /** AC-007.3 */
    @AuraEnabled
    public static ShipmentDetail getShipment(String trackingNumber) {
        Id accountId = currentAccountId();
        String tn = trackingNumber == null ? '' : trackingNumber.trim();
        List<Shipment__c> rows = [
            SELECT Name, CreatedDate, Status__c, Service_Type__c, Price__c, Customer_Reference__c, Pickup_Address__c,
                   Origin_City__c, Pickup_Postal_Code__c, Pickup_Date__c, Recipient_Name__c, Recipient_Address__c,
                   Destination_City__c, Destination_Postal_Code__c, Recipient_Phone__c, Recipient_Email__c,
                   Package_Description__c, Weight_Kg__c, Declared_Value__c, Delivery_Instructions__c,
                   Estimated_Delivery__c, Last_Location__c, Last_Update__c
            FROM Shipment__c WHERE Name = :tn AND Account__c = :accountId WITH SYSTEM_MODE LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw ShipmentRules.userError('Shipment not found.');
        }
        Shipment__c s = rows[0];
        ShipmentDetail d = new ShipmentDetail();
        d.summary = toSummary(s);
        d.estimatedDelivery = s.Estimated_Delivery__c;
        d.lastLocation = s.Last_Location__c;
        d.lastUpdate = s.Last_Update__c;
        ShipmentInput i = new ShipmentInput();
        i.pickupAddress = s.Pickup_Address__c;
        i.pickupCity = s.Origin_City__c;
        i.pickupPostalCode = s.Pickup_Postal_Code__c;
        i.pickupDate = s.Pickup_Date__c;
        i.recipientName = s.Recipient_Name__c;
        i.recipientAddress = s.Recipient_Address__c;
        i.destinationCity = s.Destination_City__c;
        i.destinationPostalCode = s.Destination_Postal_Code__c;
        i.recipientPhone = s.Recipient_Phone__c;
        i.recipientEmail = s.Recipient_Email__c;
        i.serviceType = s.Service_Type__c;
        i.weightKg = s.Weight_Kg__c;
        i.packageDescription = s.Package_Description__c;
        i.declaredValue = s.Declared_Value__c;
        i.customerReference = s.Customer_Reference__c;
        i.deliveryInstructions = s.Delivery_Instructions__c;
        d.input = i;
        return d;
    }

    /** Date window the form must enforce (AC-006.3), computed in Mexico City time. */
    @AuraEnabled(cacheable=true)
    public static Map<String, Date> pickupWindow() {
        Date t = ShipmentRules.today();
        return new Map<String, Date>{ 'min' => t.addDays(1), 'max' => t.addDays(15) };
    }

    // ---------------------------------------------------------------- helpers
    /** The browser sends a plain object; typed Apex wrapper parameters are not bound reliably in LWR sites. */
    @TestVisible
    private static ShipmentInput fromForm(Map<String, Object> f) {
        if (f == null) {
            throw ShipmentRules.userError('Complete the form.');
        }
        ShipmentInput i = new ShipmentInput();
        try {
            i.pickupAddress = text(f, 'pickupAddress');
            i.pickupCity = text(f, 'pickupCity');
            i.pickupPostalCode = text(f, 'pickupPostalCode');
            i.pickupDate = text(f, 'pickupDate') == null ? null : Date.valueOf(text(f, 'pickupDate'));
            i.recipientName = text(f, 'recipientName');
            i.recipientAddress = text(f, 'recipientAddress');
            i.destinationCity = text(f, 'destinationCity');
            i.destinationPostalCode = text(f, 'destinationPostalCode');
            i.recipientPhone = text(f, 'recipientPhone');
            i.recipientEmail = text(f, 'recipientEmail');
            i.serviceType = text(f, 'serviceType');
            i.weightKg = text(f, 'weightKg') == null ? null : Decimal.valueOf(text(f, 'weightKg'));
            i.packageDescription = text(f, 'packageDescription');
            i.declaredValue = text(f, 'declaredValue') == null ? null : Decimal.valueOf(text(f, 'declaredValue'));
            i.customerReference = text(f, 'customerReference');
            i.deliveryInstructions = text(f, 'deliveryInstructions');
        } catch (TypeException e) {
            throw ShipmentRules.userError('Check the date, weight and declared value.');
        }
        return i;
    }

    private static String text(Map<String, Object> f, String key) {
        Object v = f.get(key);
        return v == null || String.valueOf(v).trim() == '' ? null : String.valueOf(v);
    }

    @TestVisible
    private static Id currentAccountId() {
        List<User> u = [SELECT Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() AND ContactId != NULL WITH SYSTEM_MODE LIMIT 1];
        if (u.isEmpty() || u[0].Contact.AccountId == null) {
            throw ShipmentRules.userError('Log in with a customer account to continue.');
        }
        return u[0].Contact.AccountId;
    }

    private static void validateWeightAndValue(Decimal weightKg, Decimal declaredValue) {
        if (weightKg == null || weightKg <= 0 || weightKg > ShipmentRules.MAX_WEIGHT_KG) {
            throw ShipmentRules.userError('The weight must be greater than 0 and at most ' + ShipmentRules.MAX_WEIGHT_KG + ' kg.');
        }
        if (declaredValue == null || declaredValue < 0 || declaredValue > ShipmentRules.MAX_DECLARED_VALUE) {
            throw ShipmentRules.userError('The declared value must be between 0 and 50,000 MXN.');
        }
    }

    private static void validate(ShipmentInput i) {
        if (i == null) {
            throw ShipmentRules.userError('Complete the form.');
        }
        List<String> required = new List<String>{
            i.pickupAddress, i.pickupCity, i.pickupPostalCode, i.recipientName, i.recipientAddress, i.destinationCity,
            i.destinationPostalCode, i.recipientPhone, i.recipientEmail, i.packageDescription
        };
        for (String v : required) {
            if (String.isBlank(v)) {
                throw ShipmentRules.userError('Complete all the required fields.');
            }
        }
        if (i.pickupDate == null || String.isBlank(i.serviceType)) {
            throw ShipmentRules.userError('Complete all the required fields.');
        }
        if (!ShipmentRules.isPostalCode(i.pickupPostalCode) || !ShipmentRules.isPostalCode(i.destinationPostalCode)) {
            throw ShipmentRules.userError('Postal codes must have 5 digits.');
        }
        if (!ShipmentRules.isEmail(i.recipientEmail)) {
            throw ShipmentRules.userError('Enter a valid recipient email.');
        }
        if (i.recipientPhone.replaceAll('[^0-9]', '').length() < 10) {
            throw ShipmentRules.userError('Enter a valid recipient phone number (at least 10 digits).');
        }
        if (i.pickupAddress.length() > 1000 || i.recipientAddress.length() > 1000 || (i.deliveryInstructions != null && i.deliveryInstructions.length() > 2000)
            || i.packageDescription.length() > 255 || i.recipientName.length() > 120 || i.pickupCity.length() > 80
            || i.destinationCity.length() > 80 || (i.customerReference != null && i.customerReference.length() > 80)) {
            throw ShipmentRules.userError('One of the fields is too long.');
        }
        // AC-006.3
        Date today = ShipmentRules.today();
        if (i.pickupDate < today.addDays(1) || i.pickupDate > today.addDays(15) || !ShipmentRules.isBusinessDay(i.pickupDate)) {
            throw ShipmentRules.userError('The pickup date must be a business day between tomorrow and 15 days from now.');
        }
        validateWeightAndValue(i.weightKg, i.declaredValue); // AC-006.4
        if (i.serviceType != 'Standard' && i.serviceType != 'Express') {
            throw ShipmentRules.userError('Choose a service type: Standard or Express.');
        }
    }

    private static MyShipment toSummary(Shipment__c s) {
        MyShipment m = new MyShipment();
        m.trackingNumber = s.Name;
        m.requestedAt = s.CreatedDate;
        m.recipientName = s.Recipient_Name__c;
        m.destinationCity = s.Destination_City__c;
        m.status = s.Status__c;
        m.serviceType = s.Service_Type__c;
        m.price = s.Price__c;
        m.customerReference = s.Customer_Reference__c;
        return m;
    }

    private static String blankToNull(String v) {
        return String.isBlank(v) ? null : v.trim();
    }
}
