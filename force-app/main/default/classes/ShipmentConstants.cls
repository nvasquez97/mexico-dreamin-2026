/**
 * Shared constants for the Shipment__c lifecycle and the business rules of the functional design.
 */
public inherited sharing class ShipmentConstants {
  public static final String STATUS_REQUESTED = 'Requested';
  public static final String STATUS_PICKED_UP = 'Picked up';
  public static final String STATUS_IN_TRANSIT = 'In transit';
  public static final String STATUS_OUT_FOR_DELIVERY = 'Out for delivery';
  public static final String STATUS_DELIVERED = 'Delivered';
  public static final String STATUS_EXCEPTION = 'Exception';

  /** Lifecycle order, used to validate carrier statuses and to sort results. */
  public static final List<String> STATUSES = new List<String>{
    STATUS_REQUESTED,
    STATUS_PICKED_UP,
    STATUS_IN_TRANSIT,
    STATUS_OUT_FOR_DELIVERY,
    STATUS_DELIVERED,
    STATUS_EXCEPTION
  };

  public static final String SERVICE_STANDARD = 'Standard';
  public static final String SERVICE_EXPRESS = 'Express';

  public static final String CUSTOMER_INDIVIDUAL = 'Individual';
  public static final String CUSTOMER_BUSINESS = 'Business';

  // AC-001.1
  public static final Integer MAX_TRACKING_VALUES = 10;
  // AC-003.3 / AC-003.4 / AC-003.2
  public static final Set<String> RESCHEDULABLE_STATUSES = new Set<String>{
    STATUS_PICKED_UP,
    STATUS_IN_TRANSIT
  };
  public static final Integer MAX_RESCHEDULES = 2;
  public static final Integer RESCHEDULE_WINDOW_DAYS = 7;
  // AC-006.3 / AC-006.4 / AC-006.6
  public static final Integer MAX_PICKUP_DAYS_AHEAD = 15;
  public static final Decimal MAX_WEIGHT_KG = 30;
  public static final Decimal MAX_DECLARED_VALUE = 50000;
  public static final Integer STANDARD_TRANSIT_BUSINESS_DAYS = 5;
  public static final Integer EXPRESS_TRANSIT_BUSINESS_DAYS = 2;
  // AC-005.4
  public static final Integer MIN_PASSWORD_LENGTH = 10;
  // Recipient verification throttling (protects BR-02 personal data against postal code guessing)
  public static final Integer MAX_VERIFICATION_FAILURES = 5;
  public static final Integer VERIFICATION_LOCK_MINUTES = 15;

  public static final Pattern POSTAL_CODE_PATTERN = Pattern.compile(
    '^[0-9]{5}$'
  );
  public static final Pattern TRACKING_NUMBER_PATTERN = Pattern.compile(
    '^RC[0-9]{9}$'
  );

  public static Integer statusOrder(String status) {
    Integer index = STATUSES.indexOf(status);
    return index < 0 ? STATUSES.size() : index;
  }

  /** Returns the canonical status for a case-insensitive input, or null when it is not a valid status. */
  public static String canonicalStatus(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    for (String status : STATUSES) {
      if (status.equalsIgnoreCase(value.trim())) {
        return status;
      }
    }
    return null;
  }

  public static Integer transitBusinessDays(String serviceType) {
    return serviceType == SERVICE_EXPRESS
      ? EXPRESS_TRANSIT_BUSINESS_DAYS
      : STANDARD_TRANSIT_BUSINESS_DAYS;
  }
}
