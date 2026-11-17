/**
 * BR-08 — current rate. RutaCargo determines the price on the server; the price shown to
 * the customer before confirming (AC-006.2) and the one saved (AC-006.5) come from here.
 *   Standard: 120 MXN + 18 MXN per kg
 *   Express:  220 MXN + 30 MXN per kg
 *   Both:     + 1.5% of the declared value as insurance
 */
public inherited sharing class ShipmentPricing {
  public static final Decimal INSURANCE_RATE = 0.015;

  private static final Map<String, Decimal> BASE_PRICE = new Map<String, Decimal>{
    ShipmentConstants.SERVICE_STANDARD => 120,
    ShipmentConstants.SERVICE_EXPRESS => 220
  };
  private static final Map<String, Decimal> PRICE_PER_KG = new Map<String, Decimal>{
    ShipmentConstants.SERVICE_STANDARD => 18,
    ShipmentConstants.SERVICE_EXPRESS => 30
  };

  public class Quote {
    @AuraEnabled
    public Decimal basePrice;
    @AuraEnabled
    public Decimal weightCharge;
    @AuraEnabled
    public Decimal insurance;
    @AuraEnabled
    public Decimal total;
  }

  public static Quote quote(
    String serviceType,
    Decimal weightKg,
    Decimal declaredValue
  ) {
    if (!BASE_PRICE.containsKey(serviceType)) {
      throw new IllegalArgumentException(
        'Unknown service type: ' + serviceType
      );
    }
    if (
      weightKg == null ||
      weightKg <= 0 ||
      declaredValue == null ||
      declaredValue < 0
    ) {
      throw new IllegalArgumentException(
        'Weight and declared value are required to calculate the price.'
      );
    }
    Quote q = new Quote();
    q.basePrice = BASE_PRICE.get(serviceType);
    q.weightCharge = (PRICE_PER_KG.get(serviceType) * weightKg)
      .setScale(2, RoundingMode.HALF_UP);
    q.insurance = (declaredValue * INSURANCE_RATE)
      .setScale(2, RoundingMode.HALF_UP);
    q.total = q.basePrice + q.weightCharge + q.insurance;
    return q;
  }

  public static Decimal calculate(
    String serviceType,
    Decimal weightKg,
    Decimal declaredValue
  ) {
    return quote(serviceType, weightKg, declaredValue).total;
  }
}
