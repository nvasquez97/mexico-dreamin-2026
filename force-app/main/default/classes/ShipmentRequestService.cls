/**
 * REQ-006 — validation, pricing and creation of a door-to-door shipment request.
 */
public without sharing class ShipmentRequestService {
  private static final Pattern EMAIL_PATTERN = Pattern.compile(
    '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$'
  );
  private static final Pattern PHONE_PATTERN = Pattern.compile(
    '^\\+?[0-9 ()\\-]{10,20}$'
  );

  public class ShipmentRequest {
    @AuraEnabled
    public String pickupAddress { get; set; }
    @AuraEnabled
    public String pickupCity { get; set; }
    @AuraEnabled
    public String pickupPostalCode { get; set; }
    @AuraEnabled
    public Date pickupDate { get; set; }
    @AuraEnabled
    public String recipientName { get; set; }
    @AuraEnabled
    public String recipientAddress { get; set; }
    @AuraEnabled
    public String destinationCity { get; set; }
    @AuraEnabled
    public String destinationPostalCode { get; set; }
    @AuraEnabled
    public String recipientPhone { get; set; }
    @AuraEnabled
    public String recipientEmail { get; set; }
    @AuraEnabled
    public String serviceType { get; set; }
    @AuraEnabled
    public Decimal weightKg { get; set; }
    @AuraEnabled
    public String packageDescription { get; set; }
    @AuraEnabled
    public Decimal declaredValue { get; set; }
    @AuraEnabled
    public String customerReference { get; set; }
    @AuraEnabled
    public String deliveryInstructions { get; set; }
  }

  public class RequestException extends Exception {
  }

  public class QuoteResult {
    @AuraEnabled
    public ShipmentPricing.Quote price;
    @AuraEnabled
    public Date estimatedDelivery;
  }

  public class CreatedShipment {
    @AuraEnabled
    public String trackingNumber;
    @AuraEnabled
    public Decimal price;
    @AuraEnabled
    public Date estimatedDelivery;
    @AuraEnabled
    public String status;
  }

  public class PickupWindow {
    @AuraEnabled
    public Date minDate;
    @AuraEnabled
    public Date maxDate;
    @AuraEnabled
    public Decimal maxWeightKg;
    @AuraEnabled
    public Decimal maxDeclaredValue;
  }

  /** AC-006.3: a business day between the next day and 15 days later (Mexico City). */
  public static PickupWindow pickupWindow() {
    PickupWindow window = new PickupWindow();
    Date today = RutaCargoDates.today();
    window.minDate = today.addDays(1);
    window.maxDate = today.addDays(ShipmentConstants.MAX_PICKUP_DAYS_AHEAD);
    window.maxWeightKg = ShipmentConstants.MAX_WEIGHT_KG;
    window.maxDeclaredValue = ShipmentConstants.MAX_DECLARED_VALUE;
    return window;
  }

  /** AC-006.6 */
  public static Date estimatedDelivery(Date pickupDate, String serviceType) {
    return RutaCargoDates.addBusinessDays(
      pickupDate,
      ShipmentConstants.transitBusinessDays(serviceType)
    );
  }

  /** AC-006.2 — price with the current rate, recalculated on the server. */
  public static QuoteResult quote(ShipmentRequest request) {
    validate(request);
    QuoteResult result = new QuoteResult();
    result.price = ShipmentPricing.quote(
      request.serviceType,
      request.weightKg,
      request.declaredValue
    );
    result.estimatedDelivery = estimatedDelivery(
      request.pickupDate,
      request.serviceType
    );
    return result;
  }

  /** AC-006.5 — created under the customer, in Requested status, with its tracking number. */
  public static CreatedShipment create(Id accountId, ShipmentRequest request) {
    validate(request);
    Shipment__c shipment = new Shipment__c(
      Account__c = accountId,
      Status__c = ShipmentConstants.STATUS_REQUESTED,
      Service_Type__c = request.serviceType,
      Pickup_Address__c = clean(request.pickupAddress),
      Origin_City__c = clean(request.pickupCity),
      Pickup_Postal_Code__c = clean(request.pickupPostalCode),
      Pickup_Date__c = request.pickupDate,
      Recipient_Name__c = clean(request.recipientName),
      Recipient_Address__c = clean(request.recipientAddress),
      Destination_City__c = clean(request.destinationCity),
      Destination_Postal_Code__c = clean(request.destinationPostalCode),
      Recipient_Phone__c = clean(request.recipientPhone),
      Recipient_Email__c = clean(request.recipientEmail),
      Package_Description__c = clean(request.packageDescription),
      Weight_Kg__c = request.weightKg,
      Declared_Value__c = request.declaredValue,
      Customer_Reference__c = clean(request.customerReference),
      Delivery_Instructions__c = clean(request.deliveryInstructions),
      Price__c = ShipmentPricing.calculate(
        request.serviceType,
        request.weightKg,
        request.declaredValue
      ),
      Estimated_Delivery__c = estimatedDelivery(
        request.pickupDate,
        request.serviceType
      ),
      Reschedule_Count__c = 0,
      Last_Update__c = RutaCargoDates.now()
    );
    Database.insert(shipment, AccessLevel.SYSTEM_MODE); // Name is an auto number: RC + 9 digits, consecutive (BR-05)
    Shipment__c saved = [
      SELECT Name, Price__c, Estimated_Delivery__c, Status__c
      FROM Shipment__c
      WHERE Id = :shipment.Id
      WITH SYSTEM_MODE
    ];
    CreatedShipment created = new CreatedShipment();
    created.trackingNumber = saved.Name;
    created.price = saved.Price__c;
    created.estimatedDelivery = saved.Estimated_Delivery__c;
    created.status = saved.Status__c;
    return created;
  }

  public static void validate(ShipmentRequest request) {
    List<String> errors = new List<String>();
    if (request == null) {
      throw new RequestException('The shipment request is empty.');
    }
    requireText(errors, request.pickupAddress, 'Pickup address', 1000);
    requireText(errors, request.pickupCity, 'Pickup city', 80);
    requirePostalCode(errors, request.pickupPostalCode, 'Pickup postal code');
    requireText(errors, request.recipientName, 'Recipient name', 120);
    requireText(errors, request.recipientAddress, 'Recipient address', 1000);
    requireText(errors, request.destinationCity, 'Destination city', 80);
    requirePostalCode(
      errors,
      request.destinationPostalCode,
      'Destination postal code'
    );
    requireText(
      errors,
      request.packageDescription,
      'Description of the contents',
      255
    );
    optionalText(errors, request.customerReference, 'Order reference', 80);
    optionalText(
      errors,
      request.deliveryInstructions,
      'Delivery instructions',
      1000
    );

    if (
      String.isBlank(request.recipientPhone) ||
      !PHONE_PATTERN.matcher(request.recipientPhone.trim()).matches()
    ) {
      errors.add('Recipient phone must have at least 10 digits.');
    }
    if (
      String.isBlank(request.recipientEmail) ||
      !EMAIL_PATTERN.matcher(request.recipientEmail.trim()).matches()
    ) {
      errors.add('Recipient email is not valid.');
    }
    if (
      request.serviceType != ShipmentConstants.SERVICE_STANDARD &&
      request.serviceType != ShipmentConstants.SERVICE_EXPRESS
    ) {
      errors.add('Service type must be Standard or Express.');
    }
    // AC-006.4
    if (
      request.weightKg == null ||
      request.weightKg <= 0 ||
      request.weightKg > ShipmentConstants.MAX_WEIGHT_KG
    ) {
      errors.add(
        'Weight must be greater than 0 and at most ' +
          ShipmentConstants.MAX_WEIGHT_KG +
          ' kg.'
      );
    }
    if (
      request.declaredValue == null ||
      request.declaredValue < 0 ||
      request.declaredValue > ShipmentConstants.MAX_DECLARED_VALUE
    ) {
      errors.add('Declared value must be between 0 and 50,000 MXN.');
    }
    // AC-006.3
    PickupWindow window = pickupWindow();
    if (request.pickupDate == null) {
      errors.add('Pickup date is required.');
    } else if (
      request.pickupDate < window.minDate ||
      request.pickupDate > window.maxDate
    ) {
      errors.add(
        'Pickup date must be between ' +
          RutaCargoDates.format(window.minDate) +
          ' and ' +
          RutaCargoDates.format(window.maxDate) +
          '.'
      );
    } else if (!RutaCargoDates.isBusinessDay(request.pickupDate)) {
      errors.add('Pickup date must be a business day (Monday to Friday).');
    }
    if (!errors.isEmpty()) {
      throw new RequestException(String.join(errors, ' '));
    }
  }

  private static void requireText(
    List<String> errors,
    String value,
    String label,
    Integer maxLength
  ) {
    if (String.isBlank(value)) {
      errors.add(label + ' is required.');
    } else {
      optionalText(errors, value, label, maxLength);
    }
  }

  private static void optionalText(
    List<String> errors,
    String value,
    String label,
    Integer maxLength
  ) {
    if (value != null && value.trim().length() > maxLength) {
      errors.add(label + ' can have up to ' + maxLength + ' characters.');
    }
  }

  private static void requirePostalCode(
    List<String> errors,
    String value,
    String label
  ) {
    if (
      String.isBlank(value) ||
      !ShipmentConstants.POSTAL_CODE_PATTERN.matcher(value.trim()).matches()
    ) {
      errors.add(label + ' must have 5 digits.');
    }
  }

  private static String clean(String value) {
    return String.isBlank(value) ? null : value.trim();
  }
}
