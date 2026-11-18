/**
 * @description The one pricing and dates service of customer shipment requests
 *              (odd/tasks/req-006-007-customer-shipments.md, S1), shared by the
 *              quote and the request of ShipmentRequestController and by the
 *              customer-insert guard of ShipmentTriggerHandler, so the quoted
 *              price is the stored price (P5).
 *              - Price (BR-08): Standard 120 + 18 per kg, Express 220 + 30 per
 *                kg, plus 1.5% of the declared value, rounded half-up to 2
 *                decimals (G4).
 *              - Recipient email (AC-006.1): isValidEmail, shared by the
 *                controller and the guard.
 *              - Limits (AC-006.4): weight more than 0 and at most 30 kg with at
 *                most 2 decimals (G6); declared value from 0 to 50,000 with at
 *                most 2 decimals.
 *              - Dates (BR-06): "today" is the current date in
 *                America/Mexico_City; business days are Monday to Friday (no
 *                holiday calendar, G1); the pickup date is a business day from
 *                today + 1 to today + 15 (AC-006.3); the estimated delivery is the
 *                pickup date plus 5 (Standard) or 2 (Express) business days
 *                (AC-006.6).
 *              - The customer account (BR-07): customerAccountId, the running
 *                user's own User.AccountId, read once per user and transaction.
 *              Pure functions except customerAccountId (one query, no DML).
 */
public with sharing class ShipmentRequestRules {

    /** @description The generic message of a request that breaks a rule. */
    public static final String INVALID_REQUEST_MESSAGE = 'The shipment request is not valid.';
    /** @description The Mexico City time zone of every date shown to customers (BR-06). */
    public static final String MEXICO_CITY_TIME_ZONE = 'America/Mexico_City';

    private static final Decimal MAX_WEIGHT_KG = 30;
    private static final Decimal MAX_DECLARED_VALUE = 50000;
    private static final Decimal INSURANCE_RATE = 0.015;
    private static final Integer AMOUNT_SCALE = 2;
    private static final Integer FIRST_PICKUP_DAY = 1;
    private static final Integer LAST_PICKUP_DAY = 15;
    private static final Integer DAYS_PER_WEEK = 7;
    private static final Integer BUSINESS_DAYS_PER_WEEK = 5;
    private static final Pattern EMAIL_FORMAT =
        Pattern.compile('^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9\\-]+(\\.[A-Za-z0-9\\-]+)*\\.[A-Za-z]{2,}$');
    // Monday 1 January 1900: the day of the week is counted from it.
    private static final Date KNOWN_MONDAY = Date.newInstance(1900, 1, 1);
    private static final Map<String, Decimal> BASE_PRICE_BY_SERVICE = new Map<String, Decimal>{
        'Standard' => 120,
        'Express' => 220
    };
    private static final Map<String, Decimal> PRICE_PER_KG_BY_SERVICE = new Map<String, Decimal>{
        'Standard' => 18,
        'Express' => 30
    };
    private static final Map<String, Integer> TRANSIT_BUSINESS_DAYS_BY_SERVICE = new Map<String, Integer>{
        'Standard' => 5,
        'Express' => 2
    };

    // Test seam: fixes "today" (AC-006.3 examples). Never set outside tests.
    @TestVisible
    private static Date todayOverride;

    // AccountId of each running user asked for in this transaction.
    private static Map<Id, Id> accountIdByUserId = new Map<Id, Id>();

    /** @description Thrown when a price is asked for a request that breaks a rule. */
    public class InvalidRequestException extends Exception {}

    /**
     * @description The current date in Mexico City (BR-06).
     * @return today in America/Mexico_City
     */
    public static Date today() {
        if (todayOverride != null) {
            return todayOverride;
        }
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', MEXICO_CITY_TIME_ZONE));
    }

    /**
     * @description Whether the value is a service type with a rate (Standard or Express).
     * @param serviceType the Service_Type__c value
     * @return true for Standard or Express
     */
    public static Boolean isServiceType(String serviceType) {
        return serviceType != null && BASE_PRICE_BY_SERVICE.containsKey(serviceType);
    }

    /**
     * @description Whether the weight is more than 0, at most 30 kg and has at most 2 decimals.
     * @param weightKg the weight in kg
     * @return true when valid
     */
    public static Boolean isValidWeight(Decimal weightKg) {
        return weightKg != null && weightKg > 0 && weightKg <= MAX_WEIGHT_KG && hasAtMostTwoDecimals(weightKg);
    }

    /**
     * @description Whether the declared value is from 0 to 50,000 and has at most 2 decimals.
     * @param declaredValue the declared value in MXN
     * @return true when valid
     */
    public static Boolean isValidDeclaredValue(Decimal declaredValue) {
        return declaredValue != null && declaredValue >= 0 && declaredValue <= MAX_DECLARED_VALUE
            && hasAtMostTwoDecimals(declaredValue);
    }

    /**
     * @description Whether the value, trimmed, is a well-formed email address
     *              (AC-006.1): the one check of submitRequest and of the
     *              customer-insert guard of ShipmentTriggerHandler.
     * @param email the recipient email
     * @return true when present and well formed
     */
    public static Boolean isValidEmail(String email) {
        return String.isNotBlank(email) && EMAIL_FORMAT.matcher(email.trim()).matches();
    }

    /**
     * @description Whether the day is Monday to Friday (G1: no holiday calendar).
     * @param day the date
     * @return true for a business day
     */
    public static Boolean isBusinessDay(Date day) {
        if (day == null) {
            return false;
        }
        Integer weekday = Math.mod(KNOWN_MONDAY.daysBetween(day), DAYS_PER_WEEK);
        if (weekday < 0) {
            weekday += DAYS_PER_WEEK;
        }
        return weekday < BUSINESS_DAYS_PER_WEEK;
    }

    /**
     * @description Whether the pickup date is a business day from today + 1 to today + 15 (AC-006.3).
     * @param pickupDate the requested pickup date
     * @return true when valid
     */
    public static Boolean isValidPickupDate(Date pickupDate) {
        Date todayInMexicoCity = today();
        return isBusinessDay(pickupDate)
            && pickupDate >= todayInMexicoCity.addDays(FIRST_PICKUP_DAY)
            && pickupDate <= todayInMexicoCity.addDays(LAST_PICKUP_DAY);
    }

    /**
     * @description The first valid pickup date: the first business day from today + 1.
     * @return the earliest pickup date
     */
    public static Date earliestPickupDate() {
        Date day = today().addDays(FIRST_PICKUP_DAY);
        while (!isBusinessDay(day)) {
            day = day.addDays(1);
        }
        return day;
    }

    /**
     * @description The last valid pickup date: the last business day up to today + 15.
     * @return the latest pickup date
     */
    public static Date latestPickupDate() {
        Date day = today().addDays(LAST_PICKUP_DAY);
        while (!isBusinessDay(day)) {
            day = day.addDays(-1);
        }
        return day;
    }

    /**
     * @description The BR-08 price, rounded half-up to 2 decimals (G4).
     * @param serviceType Standard or Express
     * @param weightKg a valid weight
     * @param declaredValue a valid declared value
     * @return the price in MXN
     * @throws InvalidRequestException when an input breaks a rule
     */
    public static Decimal price(String serviceType, Decimal weightKg, Decimal declaredValue) {
        if (!isServiceType(serviceType) || !isValidWeight(weightKg) || !isValidDeclaredValue(declaredValue)) {
            throw new InvalidRequestException(INVALID_REQUEST_MESSAGE);
        }
        Decimal amount = BASE_PRICE_BY_SERVICE.get(serviceType)
            + PRICE_PER_KG_BY_SERVICE.get(serviceType) * weightKg
            + INSURANCE_RATE * declaredValue;
        return amount.setScale(AMOUNT_SCALE, RoundingMode.HALF_UP);
    }

    /**
     * @description The estimated delivery: the pickup date plus 5 (Standard) or
     *              2 (Express) business days (AC-006.6).
     * @param serviceType Standard or Express
     * @param pickupDate the pickup date
     * @return the estimated delivery date
     * @throws InvalidRequestException when the service type is unknown or the date is missing
     */
    public static Date estimatedDelivery(String serviceType, Date pickupDate) {
        if (!isServiceType(serviceType) || pickupDate == null) {
            throw new InvalidRequestException(INVALID_REQUEST_MESSAGE);
        }
        return addBusinessDays(pickupDate, TRANSIT_BUSINESS_DAYS_BY_SERVICE.get(serviceType));
    }

    /**
     * @description The running user's own customer account (User.AccountId), or
     *              null for an internal or guest user. Read once per user and
     *              transaction. Never sent to the client.
     * @return the AccountId of the running user, or null
     */
    public static Id customerAccountId() {
        Id userId = UserInfo.getUserId();
        if (!accountIdByUserId.containsKey(userId)) {
            // SECURITY-JUSTIFICATION: a customer user has no FLS on User.AccountId
            // (no Account access, G2), so a user-mode read fails with "No such
            // column 'AccountId' on entity 'User'". Scope: the running user's own
            // User row, the AccountId field only; the value never leaves the
            // server. Compensating control: it is used only to restrict the
            // caller to their own account (Account__c filter and the trigger's
            // overwrite), never to widen access. (pending owner approval, 2026-11-18)
            List<User> users = [SELECT AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
            accountIdByUserId.put(userId, users.isEmpty() ? null : users[0].AccountId);
        }
        return accountIdByUserId.get(userId);
    }

    private static Date addBusinessDays(Date start, Integer businessDays) {
        Date day = start;
        Integer added = 0;
        while (added < businessDays) {
            day = day.addDays(1);
            if (isBusinessDay(day)) {
                added++;
            }
        }
        return day;
    }

    private static Boolean hasAtMostTwoDecimals(Decimal value) {
        return value.setScale(AMOUNT_SCALE, RoundingMode.DOWN) == value;
    }
}
