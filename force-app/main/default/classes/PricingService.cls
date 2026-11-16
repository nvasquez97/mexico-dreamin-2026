/**
 * Calculates the shipment price with the current rate (BR-08), stored in
 * Shipping_Rate__mdt, and enforces the package limits (AC-006.4).
 * Price = base + per-kg x weight + insurance % x declared value, rounded
 * half-up to cents. RutaCargo determines the price: callers never send it.
 */
public with sharing class PricingService {
    public static final Decimal MAX_WEIGHT_KG = 30;
    public static final Decimal MAX_DECLARED_VALUE = 50000;

    /** Business error with a message safe to show to the customer. */
    public class PricingException extends Exception {}

    /**
     * @param serviceType Standard or Express
     * @param weightKg weight in kg, greater than 0 and at most 30
     * @param declaredValue declared value in MXN, from 0 to 50,000
     * @return the price in MXN rounded to 2 decimals
     * @throws PricingException when an input is outside the allowed values
     */
    public static Decimal calculatePrice(String serviceType, Decimal weightKg, Decimal declaredValue) {
        Shipping_Rate__mdt rate = getRate(serviceType);
        if (weightKg == null || weightKg <= 0) {
            throw new PricingException('Enter a weight greater than 0 kg.');
        }
        if (weightKg > MAX_WEIGHT_KG) {
            throw new PricingException('The maximum weight is 30 kg.');
        }
        if (declaredValue == null || declaredValue < 0) {
            throw new PricingException('Enter a declared value of 0 MXN or more.');
        }
        if (declaredValue > MAX_DECLARED_VALUE) {
            throw new PricingException('The maximum declared value is 50,000 MXN.');
        }
        Decimal price = rate.Base_Price__c +
            rate.Price_Per_Kg__c * weightKg +
            declaredValue * rate.Insurance_Percent__c / 100;
        return price.setScale(2, System.RoundingMode.HALF_UP);
    }

    /**
     * @param serviceType Standard or Express
     * @return business days from pickup to estimated delivery (AC-006.6)
     * @throws PricingException when the service type is unknown
     */
    public static Integer getTransitBusinessDays(String serviceType) {
        return getRate(serviceType).Transit_Business_Days__c.intValue();
    }

    private static Shipping_Rate__mdt getRate(String serviceType) {
        Shipping_Rate__mdt rate = String.isBlank(serviceType) ? null : Shipping_Rate__mdt.getInstance(serviceType);
        // getInstance matches DeveloperName case-insensitively; require the exact picklist value.
        if (rate == null || rate.DeveloperName != serviceType) {
            throw new PricingException('Choose a valid service type: Standard or Express.');
        }
        return rate;
    }
}
