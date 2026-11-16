/**
 * Pure business rules for RutaCargo shipments: BR-06 (Mexico City time), BR-08 (rate),
 * AC-006.3/4/6 (pickup window, limits, estimated delivery), AC-003.2 (reschedule window),
 * AC-005.4 (password) and postal-code format. No SOQL or DML.
 */
public with sharing class ShipmentRules {
    public class RuleException extends Exception {
    }

    public static final String SERVICE_STANDARD = 'Standard';
    public static final String SERVICE_EXPRESS = 'Express';
    public static final Decimal MAX_WEIGHT_KG = 30;
    public static final Decimal MAX_DECLARED_VALUE = 50000;
    public static final Integer MAX_PICKUP_DAYS_AHEAD = 15;
    public static final Integer MAX_RESCHEDULE_DAYS_AFTER_ORIGINAL = 7;
    private static final String MEXICO_CITY = 'America/Mexico_City';
    private static final Date KNOWN_MONDAY = Date.newInstance(2026, 11, 16);

    /** Tests set this to freeze "today". */
    @TestVisible
    private static Date todayOverride;

    /**
     * @return today's date in Mexico City time (BR-06)
     */
    public static Date today() {
        if (todayOverride != null) {
            return todayOverride;
        }
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', MEXICO_CITY));
    }

    /**
     * Price per BR-08. Standard 120 + 18/kg; Express 220 + 30/kg; plus 1.5% of declared value.
     * @param serviceType Standard or Express
     * @param weightKg weight in kg
     * @param declaredValue declared value in MXN
     * @return price in MXN, 2 decimals
     * @throws RuleException when the service type is unknown or an input is missing
     */
    public static Decimal calculatePrice(String serviceType, Decimal weightKg, Decimal declaredValue) {
        if (weightKg == null || declaredValue == null) {
            throw new RuleException('Weight and declared value are required.');
        }
        Decimal base;
        Decimal perKg;
        if (serviceType == SERVICE_STANDARD) {
            base = 120;
            perKg = 18;
        } else if (serviceType == SERVICE_EXPRESS) {
            base = 220;
            perKg = 30;
        } else {
            throw new RuleException('Unknown service type.');
        }
        return (base + perKg * weightKg + declaredValue * 0.015).setScale(2, RoundingMode.HALF_UP);
    }

    /**
     * @param value date to test
     * @return true when the date is Monday to Friday
     */
    public static Boolean isBusinessDay(Date value) {
        Integer dayOfWeek = Math.mod(KNOWN_MONDAY.daysBetween(value), 7);
        if (dayOfWeek < 0) {
            dayOfWeek += 7;
        }
        return dayOfWeek < 5;
    }

    /**
     * AC-006.3: a business day between tomorrow and 15 days from today.
     * @param pickupDate requested pickup date
     * @return true when valid
     */
    public static Boolean isValidPickupDate(Date pickupDate) {
        if (pickupDate == null) {
            return false;
        }
        Date current = today();
        return pickupDate >= current.addDays(1) &&
            pickupDate <= current.addDays(MAX_PICKUP_DAYS_AHEAD) &&
            isBusinessDay(pickupDate);
    }

    /**
     * AC-006.6: pickup date plus 5 business days (Standard) or 2 (Express).
     * @param pickupDate pickup date
     * @param serviceType Standard or Express
     * @return estimated delivery date
     */
    public static Date estimatedDelivery(Date pickupDate, String serviceType) {
        Integer remaining = serviceType == SERVICE_EXPRESS ? 2 : 5;
        Date result = pickupDate;
        while (remaining > 0) {
            result = result.addDays(1);
            if (isBusinessDay(result)) {
                remaining--;
            }
        }
        return result;
    }

    /**
     * AC-006.4: weight above 0 and up to 30 kg; declared value 0 to 50,000 MXN.
     * @param weightKg weight in kg
     * @param declaredValue declared value in MXN
     * @return true when within limits
     */
    public static Boolean isWithinLimits(Decimal weightKg, Decimal declaredValue) {
        return weightKg != null &&
            declaredValue != null &&
            weightKg > 0 &&
            weightKg <= MAX_WEIGHT_KG &&
            declaredValue >= 0 &&
            declaredValue <= MAX_DECLARED_VALUE;
    }

    /**
     * AC-003.2: from tomorrow up to 7 calendar days after the original estimated date.
     * @param newDate proposed date
     * @param originalEstimate estimate at creation
     * @return true when valid
     */
    public static Boolean isValidRescheduleDate(Date newDate, Date originalEstimate) {
        if (newDate == null || originalEstimate == null) {
            return false;
        }
        return newDate >= today().addDays(1) &&
            newDate <= originalEstimate.addDays(MAX_RESCHEDULE_DAYS_AFTER_ORIGINAL);
    }

    /**
     * AC-005.4: at least 10 characters with letters and numbers.
     * @param password candidate password
     * @return true when valid
     */
    public static Boolean isValidPassword(String password) {
        return password != null &&
            password.length() >= 10 &&
            Pattern.compile('.*[A-Za-z].*').matcher(password).matches() &&
            Pattern.compile('.*[0-9].*').matcher(password).matches();
    }

    /**
     * @param postalCode candidate postal code
     * @return true when exactly 5 digits
     */
    public static Boolean isValidPostalCode(String postalCode) {
        return postalCode != null && Pattern.matches('[0-9]{5}', postalCode);
    }
}
