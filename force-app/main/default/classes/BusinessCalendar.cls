/**
 * Date rules for RutaCargo in Mexico City time (BR-06): the current date,
 * business days (Monday to Friday, AC-006.6) and the pickup window
 * (a business day from tomorrow to 15 days later, AC-006.3).
 * Public holidays are not considered (assumption L7 in the feature document).
 */
public inherited sharing class BusinessCalendar {
    public static final String MEXICO_CITY_TIME_ZONE = 'America/Mexico_City';
    public static final Integer MAX_PICKUP_DAYS_AHEAD = 15;

    @TestVisible
    private static Datetime nowOverride;

    /**
     * @return the current calendar date in Mexico City.
     */
    public static Date todayInMexicoCity() {
        Datetime now = nowOverride ?? Datetime.now();
        return Date.valueOf(now.format('yyyy-MM-dd', MEXICO_CITY_TIME_ZONE));
    }

    /**
     * @param day the date to check
     * @return true when the date is Monday to Friday; false for weekends and null.
     */
    public static Boolean isBusinessDay(Date day) {
        if (day == null) {
            return false;
        }
        // ISO day of week: 1 = Monday ... 7 = Sunday. Noon GMT avoids any date shift.
        Integer isoDayOfWeek = Integer.valueOf(
            Datetime.newInstanceGmt(day, Time.newInstance(12, 0, 0, 0)).formatGmt('u')
        );
        return isoDayOfWeek <= 5;
    }

    /**
     * @param startDate the first date (not counted)
     * @param businessDays number of business days to add, zero or more
     * @return the date that is the given number of business days after startDate.
     */
    public static Date addBusinessDays(Date startDate, Integer businessDays) {
        if (startDate == null || businessDays == null || businessDays < 0) {
            throw new IllegalArgumentException('A start date and a non-negative number of days are required.');
        }
        Date current = startDate;
        Integer remaining = businessDays;
        while (remaining > 0) {
            current = current.addDays(1);
            if (isBusinessDay(current)) {
                remaining--;
            }
        }
        return current;
    }

    /**
     * @param pickupDate the requested pickup date
     * @return true when it is a business day between tomorrow and 15 days later (Mexico City).
     */
    public static Boolean isValidPickupDate(Date pickupDate) {
        if (pickupDate == null) {
            return false;
        }
        Date today = todayInMexicoCity();
        return pickupDate > today &&
            pickupDate <= today.addDays(MAX_PICKUP_DAYS_AHEAD) &&
            isBusinessDay(pickupDate);
    }
}
