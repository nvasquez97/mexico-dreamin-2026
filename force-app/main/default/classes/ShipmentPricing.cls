/**
 * BR-08 current rate. Standard: 120 + 18/kg. Express: 220 + 30/kg.
 * Plus 1.5% of the declared value as insurance. Prices are in MXN.
 */
public with sharing class ShipmentPricing {
    public static Decimal calculate(String serviceType, Decimal weightKg, Decimal declaredValue) {
        Decimal base;
        Decimal perKg;
        if (serviceType == 'Standard') {
            base = 120;
            perKg = 18;
        } else if (serviceType == 'Express') {
            base = 220;
            perKg = 30;
        } else {
            throw ShipmentRules.userError('Choose a service type: Standard or Express.');
        }
        Decimal insurance = (declaredValue == null ? 0 : declaredValue) * 0.015;
        return (base + perKg * weightKg + insurance).setScale(2, RoundingMode.HALF_UP);
    }
}
