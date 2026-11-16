/**
 * Tests for BusinessCalendar.
 * Covers AC-006.3 (pickup window), AC-006.6 (business days) and BR-06 (Mexico City time).
 */
@IsTest
private class BusinessCalendarTest {
    // 2026-11-18 04:30 UTC is still 2026-11-17 22:30 in Mexico City (UTC-6).
    private static final Datetime LATE_EVENING_MX = Datetime.newInstanceGmt(2026, 11, 18, 4, 30, 0);
    // Tuesday 2026-11-17 18:00 UTC = 12:00 Mexico City.
    private static final Datetime TUESDAY_NOON_MX = Datetime.newInstanceGmt(2026, 11, 17, 18, 0, 0);

    // Covers BR-06: "today" is the Mexico City date, not the UTC date.
    @IsTest
    static void shouldReturnMexicoCityDate_WhenUtcIsAlreadyNextDay() {
        BusinessCalendar.nowOverride = LATE_EVENING_MX;
        Assert.areEqual(Date.newInstance(2026, 11, 17), BusinessCalendar.todayInMexicoCity(),
            'Today must be computed in America/Mexico_City');
    }

    // Covers AC-006.3: Monday to Friday are business days.
    @IsTest
    static void shouldTreatWeekdayAsBusinessDay_WhenFriday() {
        Assert.isTrue(BusinessCalendar.isBusinessDay(Date.newInstance(2026, 11, 20)), 'Friday is a business day');
    }

    // Covers AC-006.3: Saturday and Sunday are not business days.
    @IsTest
    static void shouldRejectWeekend_WhenSaturdayOrSunday() {
        Assert.isFalse(BusinessCalendar.isBusinessDay(Date.newInstance(2026, 11, 21)), 'Saturday is not a business day');
        Assert.isFalse(BusinessCalendar.isBusinessDay(Date.newInstance(2026, 11, 22)), 'Sunday is not a business day');
    }

    // Covers AC-006.6: Standard = pickup + 5 business days, skipping the weekend.
    @IsTest
    static void shouldSkipWeekend_WhenAddingFiveBusinessDaysFromFriday() {
        Assert.areEqual(Date.newInstance(2026, 11, 27),
            BusinessCalendar.addBusinessDays(Date.newInstance(2026, 11, 20), 5),
            'Friday + 5 business days is the next Friday');
    }

    // Covers AC-006.6: Express = pickup + 2 business days.
    @IsTest
    static void shouldReturnTuesday_WhenAddingTwoBusinessDaysFromFriday() {
        Assert.areEqual(Date.newInstance(2026, 11, 24),
            BusinessCalendar.addBusinessDays(Date.newInstance(2026, 11, 20), 2),
            'Friday + 2 business days is Tuesday');
    }

    // Covers AC-006.3: tomorrow (a business day) is the earliest valid pickup date.
    @IsTest
    static void shouldAcceptPickup_WhenTomorrowIsBusinessDay() {
        BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
        Assert.isTrue(BusinessCalendar.isValidPickupDate(Date.newInstance(2026, 11, 18)), 'Wednesday tomorrow is valid');
    }

    // Covers AC-006.3: today is not a valid pickup date.
    @IsTest
    static void shouldRejectPickup_WhenToday() {
        BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
        Assert.isFalse(BusinessCalendar.isValidPickupDate(Date.newInstance(2026, 11, 17)), 'Today is not valid');
    }

    // Covers AC-006.3: day 15 is the last valid day; day 16 is rejected.
    @IsTest
    static void shouldRejectPickup_WhenMoreThanFifteenDaysAhead() {
        BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
        // 2026-12-02 = today + 15 (Wednesday), 2026-12-03 = today + 16 (Thursday)
        Assert.isTrue(BusinessCalendar.isValidPickupDate(Date.newInstance(2026, 12, 2)), 'Day 15 is valid');
        Assert.isFalse(BusinessCalendar.isValidPickupDate(Date.newInstance(2026, 12, 3)), 'Day 16 is not valid');
    }

    // Covers AC-006.3: a weekend date inside the window is rejected.
    @IsTest
    static void shouldRejectPickup_WhenWeekendInsideWindow() {
        BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
        Assert.isFalse(BusinessCalendar.isValidPickupDate(Date.newInstance(2026, 11, 21)), 'Saturday is not valid');
    }

    // Covers AC-006.3: a missing pickup date is rejected.
    @IsTest
    static void shouldRejectPickup_WhenNull() {
        Assert.isFalse(BusinessCalendar.isValidPickupDate(null), 'Null pickup date is not valid');
    }
}
