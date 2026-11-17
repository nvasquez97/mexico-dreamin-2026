/**
 * REQ-006 / REQ-007 — shipments of the logged-in customer.
 *
 * BR-07: every query is scoped to the Account of the running site user, resolved on the server.
 * Customer users get no object permissions on Shipment__c; this controller (WITHOUT SHARING,
 * explicit account filter) is the only way they reach shipments, and it only returns the
 * fields the customer entered plus price and status — never cost, margin, notes (BR-03).
 */
public without sharing class CustomerShipmentController {
  private static final Integer PAGE_SIZE = 25;

  public class ShipmentRow {
    @AuraEnabled
    public String trackingNumber;
    @AuraEnabled
    public Datetime requestDate;
    @AuraEnabled
    public String recipientName;
    @AuraEnabled
    public String destinationCity;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String serviceType;
    @AuraEnabled
    public Decimal price;
    @AuraEnabled
    public String customerReference;
  }

  public class ShipmentPage {
    @AuraEnabled
    public List<ShipmentRow> rows;
    @AuraEnabled
    public Boolean hasMore;
    @AuraEnabled
    public Integer totalCount;
  }

  public class ShipmentDetail {
    @AuraEnabled
    public String trackingNumber;
    @AuraEnabled
    public Datetime requestDate;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String serviceType;
    @AuraEnabled
    public Decimal price;
    @AuraEnabled
    public String customerReference;
    @AuraEnabled
    public String pickupAddress;
    @AuraEnabled
    public String pickupCity;
    @AuraEnabled
    public String pickupPostalCode;
    @AuraEnabled
    public Date pickupDate;
    @AuraEnabled
    public String recipientName;
    @AuraEnabled
    public String recipientAddress;
    @AuraEnabled
    public String destinationCity;
    @AuraEnabled
    public String destinationPostalCode;
    @AuraEnabled
    public String recipientPhone;
    @AuraEnabled
    public String recipientEmail;
    @AuraEnabled
    public String deliveryInstructions;
    @AuraEnabled
    public String packageDescription;
    @AuraEnabled
    public Decimal weightKg;
    @AuraEnabled
    public Decimal declaredValue;
    @AuraEnabled
    public Date estimatedDelivery;
    @AuraEnabled
    public String lastLocation;
    @AuraEnabled
    public Datetime lastUpdate;
    @AuraEnabled
    public Datetime deliveredAt;
  }

  // ------------------------------------------------------------- REQ-006

  @AuraEnabled
  public static ShipmentRequestService.PickupWindow getPickupWindow() {
    currentAccountId();
    return ShipmentRequestService.pickupWindow();
  }

  @AuraEnabled
  public static ShipmentRequestService.QuoteResult getQuote(
    ShipmentRequestService.ShipmentRequest request
  ) {
    currentAccountId();
    try {
      return ShipmentRequestService.quote(request);
    } catch (ShipmentRequestService.RequestException e) {
      throw RutaCargoErrors.aura(e.getMessage());
    }
  }

  @AuraEnabled
  public static ShipmentRequestService.CreatedShipment createShipment(
    ShipmentRequestService.ShipmentRequest request
  ) {
    Id accountId = currentAccountId();
    try {
      return ShipmentRequestService.create(accountId, request);
    } catch (ShipmentRequestService.RequestException e) {
      throw RutaCargoErrors.aura(e.getMessage());
    }
  }

  // ------------------------------------------------------------- REQ-007

  /** AC-007.1 / AC-007.2 — most recent first, optional status filter and free-text search. */
  @AuraEnabled
  public static ShipmentPage getMyShipments(
    String status,
    String searchTerm,
    Integer offsetRows
  ) {
    Id accountId = currentAccountId();
    String statusFilter = ShipmentConstants.canonicalStatus(status);
    String term = String.isBlank(searchTerm)
      ? null
      : '%' + escapeLike(searchTerm.trim()) + '%';
    Integer offsetValue = offsetRows == null ||
      offsetRows < 0
      ? 0
      : Math.min(offsetRows, 2000);

    String whereClause = 'WHERE Account__c = :accountId';
    if (statusFilter != null) {
      whereClause += ' AND Status__c = :statusFilter';
    }
    if (term != null) {
      whereClause += ' AND (Name LIKE :term OR Recipient_Name__c LIKE :term OR Customer_Reference__c LIKE :term)';
    }
    Map<String, Object> binds = new Map<String, Object>{
      'accountId' => accountId,
      'statusFilter' => statusFilter,
      'term' => term,
      'pageSize' => PAGE_SIZE + 1,
      'offsetValue' => offsetValue
    };
    List<Shipment__c> records = Database.queryWithBinds(
      'SELECT Name, CreatedDate, Recipient_Name__c, Destination_City__c, Status__c, Service_Type__c, ' +
        'Price__c, Customer_Reference__c FROM Shipment__c ' +
        whereClause +
        ' ORDER BY CreatedDate DESC, Name DESC LIMIT :pageSize OFFSET :offsetValue',
      binds,
      AccessLevel.SYSTEM_MODE
    );
    Integer total = Database.countQueryWithBinds(
      'SELECT COUNT() FROM Shipment__c ' + whereClause,
      binds,
      AccessLevel.SYSTEM_MODE
    );

    ShipmentPage page = new ShipmentPage();
    page.rows = new List<ShipmentRow>();
    page.hasMore = records.size() > PAGE_SIZE;
    page.totalCount = total;
    for (Integer i = 0; i < Math.min(records.size(), PAGE_SIZE); i++) {
      Shipment__c record = records[i];
      ShipmentRow row = new ShipmentRow();
      row.trackingNumber = record.Name;
      row.requestDate = record.CreatedDate;
      row.recipientName = record.Recipient_Name__c;
      row.destinationCity = record.Destination_City__c;
      row.status = record.Status__c;
      row.serviceType = record.Service_Type__c;
      row.price = record.Price__c;
      row.customerReference = record.Customer_Reference__c;
      page.rows.add(row);
    }
    return page;
  }

  /** AC-007.3 */
  @AuraEnabled
  public static ShipmentDetail getMyShipment(String trackingNumber) {
    Id accountId = currentAccountId();
    String key = trackingNumber == null
      ? ''
      : trackingNumber.trim().toUpperCase();
    List<Shipment__c> records = [
      SELECT
        Name,
        CreatedDate,
        Status__c,
        Service_Type__c,
        Price__c,
        Customer_Reference__c,
        Pickup_Address__c,
        Origin_City__c,
        Pickup_Postal_Code__c,
        Pickup_Date__c,
        Recipient_Name__c,
        Recipient_Address__c,
        Destination_City__c,
        Destination_Postal_Code__c,
        Recipient_Phone__c,
        Recipient_Email__c,
        Delivery_Instructions__c,
        Package_Description__c,
        Weight_Kg__c,
        Declared_Value__c,
        Estimated_Delivery__c,
        Last_Location__c,
        Last_Update__c,
        Delivered_At__c
      FROM Shipment__c
      WHERE Name = :key AND Account__c = :accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (records.isEmpty()) {
      // Same answer whether it does not exist or belongs to someone else (BR-07).
      throw RutaCargoErrors.aura(
        'We could not find that shipment in your account.'
      );
    }
    Shipment__c s = records[0];
    ShipmentDetail detail = new ShipmentDetail();
    detail.trackingNumber = s.Name;
    detail.requestDate = s.CreatedDate;
    detail.status = s.Status__c;
    detail.serviceType = s.Service_Type__c;
    detail.price = s.Price__c;
    detail.customerReference = s.Customer_Reference__c;
    detail.pickupAddress = s.Pickup_Address__c;
    detail.pickupCity = s.Origin_City__c;
    detail.pickupPostalCode = s.Pickup_Postal_Code__c;
    detail.pickupDate = s.Pickup_Date__c;
    detail.recipientName = s.Recipient_Name__c;
    detail.recipientAddress = s.Recipient_Address__c;
    detail.destinationCity = s.Destination_City__c;
    detail.destinationPostalCode = s.Destination_Postal_Code__c;
    detail.recipientPhone = s.Recipient_Phone__c;
    detail.recipientEmail = s.Recipient_Email__c;
    detail.deliveryInstructions = s.Delivery_Instructions__c;
    detail.packageDescription = s.Package_Description__c;
    detail.weightKg = s.Weight_Kg__c;
    detail.declaredValue = s.Declared_Value__c;
    detail.estimatedDelivery = s.Estimated_Delivery__c;
    detail.lastLocation = s.Last_Location__c;
    detail.lastUpdate = s.Last_Update__c;
    detail.deliveredAt = s.Delivered_At__c;
    return detail;
  }

  @AuraEnabled(cacheable=true)
  public static List<String> getStatuses() {
    return ShipmentConstants.STATUSES;
  }

  // ------------------------------------------------------------- helpers

  @TestVisible
  private static Id currentAccountId() {
    Id accountId = [
      SELECT AccountId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      WITH SYSTEM_MODE
    ]
    .AccountId;
    if (accountId == null) {
      throw RutaCargoErrors.aura('Please log in with your customer account.');
    }
    return accountId;
  }

  private static String escapeLike(String value) {
    return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
  }
}
