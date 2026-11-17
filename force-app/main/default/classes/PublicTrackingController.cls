/**
 * REQ-001 — Public tracking (guest users of the RutaCargo site).
 *
 * Runs WITHOUT SHARING on purpose: guest users have no object access to Shipment__c.
 * Access is controlled here instead: a shipment is only returned when the caller already
 * knows its tracking number or order reference, and only the public fields of BR-01 /
 * AC-001.2 leave the server (never recipient data, prices, costs or notes — BR-02, BR-03).
 */
public without sharing class PublicTrackingController {
  public static final String SEARCH_BY_TRACKING = 'TRACKING';
  public static final String SEARCH_BY_REFERENCE = 'REFERENCE';
  // A reference is chosen by each customer and may repeat; cap the rows it can return.
  private static final Integer MAX_ROWS_PER_REFERENCE = 20;

  public class TrackingResult {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String searchValue;
    @AuraEnabled
    public Boolean found;
    @AuraEnabled
    public String trackingNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer statusOrder;
    @AuraEnabled
    public String originCity;
    @AuraEnabled
    public String destinationCity;
    @AuraEnabled
    public String lastLocation;
    @AuraEnabled
    public Datetime lastUpdate;
    @AuraEnabled
    public Date estimatedDelivery;
  }

  @AuraEnabled
  public static List<TrackingResult> track(String searchBy, String searchText) {
    try {
      return search(searchBy, searchText);
    } catch (TrackingException e) {
      throw RutaCargoErrors.aura(e.getMessage());
    }
  }

  public class TrackingException extends Exception {
  }

  /** AC-001.1 / AC-001.5: split by commas or line breaks, trim, drop blanks and duplicates. */
  public static List<String> parseValues(String searchText) {
    List<String> values = new List<String>();
    Set<String> seen = new Set<String>();
    if (String.isBlank(searchText)) {
      return values;
    }
    for (String raw : searchText.split('[,\\r\\n]+')) {
      String value = raw.trim();
      if (String.isNotBlank(value) && seen.add(value.toUpperCase())) {
        values.add(value);
      }
    }
    return values;
  }

  public static List<TrackingResult> search(
    String searchBy,
    String searchText
  ) {
    List<String> values = parseValues(searchText);
    if (values.isEmpty()) {
      throw new TrackingException(
        'Enter at least one tracking number or order reference.'
      );
    }
    if (values.size() > ShipmentConstants.MAX_TRACKING_VALUES) {
      throw new TrackingException(
        'You can search up to ' +
          ShipmentConstants.MAX_TRACKING_VALUES +
          ' values at a time.'
      );
    }
    Boolean byReference = SEARCH_BY_REFERENCE.equalsIgnoreCase(searchBy);
    if (!byReference && !SEARCH_BY_TRACKING.equalsIgnoreCase(searchBy)) {
      throw new TrackingException(
        'Choose whether to search by tracking number or by order reference.'
      );
    }

    Map<String, List<Shipment__c>> matches = new Map<String, List<Shipment__c>>();
    for (String value : values) {
      matches.put(value.toUpperCase(), new List<Shipment__c>());
    }
    // SOQL text comparison is case-insensitive (AC-001.5).
    List<Shipment__c> rows = byReference
      ? [
          SELECT
            Name,
            Customer_Reference__c,
            Status__c,
            Origin_City__c,
            Destination_City__c,
            Last_Location__c,
            Last_Update__c,
            Estimated_Delivery__c
          FROM Shipment__c
          WHERE Customer_Reference__c IN :values
          WITH SYSTEM_MODE
          ORDER BY Name
          LIMIT 200
        ]
      : [
          SELECT
            Name,
            Customer_Reference__c,
            Status__c,
            Origin_City__c,
            Destination_City__c,
            Last_Location__c,
            Last_Update__c,
            Estimated_Delivery__c
          FROM Shipment__c
          WHERE Name IN :values
          WITH SYSTEM_MODE
          ORDER BY Name
        ];
    for (Shipment__c row : rows) {
      String matchedValue = byReference ? row.Customer_Reference__c : row.Name;
      List<Shipment__c> bucket = matchedValue == null
        ? null
        : matches.get(matchedValue.trim().toUpperCase());
      if (bucket != null && bucket.size() < MAX_ROWS_PER_REFERENCE) {
        bucket.add(row);
      }
    }

    List<TrackingResult> results = new List<TrackingResult>();
    for (String value : values) {
      List<Shipment__c> found = matches.get(value.toUpperCase());
      if (found.isEmpty()) {
        results.add(notFound(value)); // AC-001.3
      }
      for (Shipment__c shipment : found) {
        results.add(toResult(value, shipment));
      }
    }
    return results;
  }

  private static TrackingResult notFound(String value) {
    TrackingResult result = new TrackingResult();
    result.key = 'NF-' + value.toUpperCase();
    result.searchValue = value;
    result.found = false;
    result.statusOrder = ShipmentConstants.STATUSES.size() + 1;
    return result;
  }

  // AC-001.2 / BR-01: the only fields a visitor may see.
  private static TrackingResult toResult(String value, Shipment__c shipment) {
    TrackingResult result = new TrackingResult();
    result.key = shipment.Name + '-' + value.toUpperCase();
    result.searchValue = value;
    result.found = true;
    result.trackingNumber = shipment.Name;
    result.status = shipment.Status__c;
    result.statusOrder = ShipmentConstants.statusOrder(shipment.Status__c);
    result.originCity = shipment.Origin_City__c;
    result.destinationCity = shipment.Destination_City__c;
    result.lastLocation = shipment.Last_Location__c;
    result.lastUpdate = shipment.Last_Update__c;
    result.estimatedDelivery = shipment.Estimated_Delivery__c;
    return result;
  }
}
