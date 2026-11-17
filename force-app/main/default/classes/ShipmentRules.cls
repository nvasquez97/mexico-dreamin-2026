/**
 * Shared business rules: Mexico City dates (BR-06), business days, validation helpers.
 */
public with sharing class ShipmentRules {
    public static final String MEXICO_TZ = 'America/Mexico_City';
    public static final Integer MAX_RESCHEDULES = 2;
    public static final Integer MAX_WEIGHT_KG = 30;
    public static final Decimal MAX_DECLARED_VALUE = 50000;
    public static final Set<String> RESCHEDULABLE = new Set<String>{ 'Picked up', 'In transit' };

    /** Today's date in Mexico City, regardless of the running user's time zone. */
    public static Date today() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', MEXICO_TZ));
    }

    /** Monday-Friday. Official holidays are not modelled. */
    public static Boolean isBusinessDay(Date d) {
        // 1900-01-07 was a Sunday: 0 = Sunday ... 6 = Saturday
        Integer dow = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(d), 7);
        return dow >= 1 && dow <= 5;
    }

    public static Date addBusinessDays(Date start, Integer days) {
        Date d = start;
        Integer left = days;
        while (left > 0) {
            d = d.addDays(1);
            if (isBusinessDay(d)) {
                left--;
            }
        }
        return d;
    }

    /** AC-006.6: pickup + 5 business days (Standard) or + 2 (Express). */
    public static Date estimatedDelivery(Date pickup, String serviceType) {
        return addBusinessDays(pickup, serviceType == 'Express' ? 2 : 5);
    }

    public static String normalizePostalCode(String value) {
        return value == null ? '' : value.trim();
    }

    public static Boolean isPostalCode(String value) {
        return value != null && Pattern.matches('^\\d{5}$', value.trim());
    }

    public static Boolean isEmail(String value) {
        return value != null && Pattern.matches('^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$', value.trim());
    }

    /** AC-005.4: at least 10 characters with letters and numbers. */
    public static Boolean isValidPassword(String pwd) {
        return pwd != null && pwd.length() >= 10 && Pattern.compile('.*[A-Za-z].*').matcher(pwd).matches()
            && Pattern.compile('.*[0-9].*').matcher(pwd).matches();
    }

    public static AuraHandledException userError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
