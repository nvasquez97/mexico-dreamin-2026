/**
 * Unit tests for ShipmentRules. Each test names the acceptance criterion it covers.
 */
@IsTest
private class ShipmentRulesTest {
    // 2026-11-16 is a Monday.
    private static final Date MONDAY = Date.newInstance(2026, 11, 16);

    @IsTest
    static void priceStandard_AC_006_2_BR_08() {
        // 120 + 18*2 + 1.5% of 1000 = 171.00
        Assert.areEqual(171.00, ShipmentRules.calculatePrice('Standard', 2, 1000));
    }

    @IsTest
    static void priceExpress_AC_006_2_BR_08() {
        // 220 + 30*10 + 1.5% of 5000 = 595.00
        Assert.areEqual(595.00, ShipmentRules.calculatePrice('Express', 10, 5000));
    }

    @IsTest
    static void priceRejectsUnknownService_AC_006_2() {
        try {
            ShipmentRules.calculatePrice('Overnight', 1, 100);
            Assert.fail('expected exception');
        } catch (ShipmentRules.RuleException e) {
            Assert.isTrue(e.getMessage().contains('service'), 'message names the service');
        }
    }

    @IsTest
    static void pickupMustBeBusinessDayInWindow_AC_006_3() {
        ShipmentRules.todayOverride = MONDAY;
        Assert.areEqual(true, ShipmentRules.isValidPickupDate(MONDAY.addDays(1)), 'tomorrow (Tue)');
        Assert.areEqual(false, ShipmentRules.isValidPickupDate(MONDAY), 'today');
        Assert.areEqual(false, ShipmentRules.isValidPickupDate(MONDAY.addDays(5)), 'Saturday');
        Assert.areEqual(false, ShipmentRules.isValidPickupDate(MONDAY.addDays(6)), 'Sunday');
        Assert.areEqual(true, ShipmentRules.isValidPickupDate(MONDAY.addDays(15)), 'day 15 is Tue');
        Assert.areEqual(false, ShipmentRules.isValidPickupDate(MONDAY.addDays(16)), 'day 16');
        Assert.areEqual(false, ShipmentRules.isValidPickupDate(null));
    }

    @IsTest
    static void estimatedDeliveryAddsBusinessDays_AC_006_6() {
        Date friday = Date.newInstance(2026, 11, 20);
        Assert.areEqual(Date.newInstance(2026, 11, 24), ShipmentRules.estimatedDelivery(friday, 'Express'), 'Fri+2 = Tue');
        Assert.areEqual(Date.newInstance(2026, 11, 27), ShipmentRules.estimatedDelivery(friday, 'Standard'), 'Fri+5 = Fri');
    }

    @IsTest
    static void limitsWeightAndValue_AC_006_4() {
        Assert.areEqual(true, ShipmentRules.isWithinLimits(30, 50000));
        Assert.areEqual(false, ShipmentRules.isWithinLimits(30.01, 100));
        Assert.areEqual(false, ShipmentRules.isWithinLimits(1, 50000.01));
        Assert.areEqual(false, ShipmentRules.isWithinLimits(0, 100));
        Assert.areEqual(false, ShipmentRules.isWithinLimits(1, -1));
        Assert.areEqual(false, ShipmentRules.isWithinLimits(null, 1));
    }

    @IsTest
    static void rescheduleWindow_AC_003_2() {
        ShipmentRules.todayOverride = MONDAY;
        Date original = MONDAY.addDays(3);
        Assert.areEqual(true, ShipmentRules.isValidRescheduleDate(MONDAY.addDays(1), original));
        Assert.areEqual(true, ShipmentRules.isValidRescheduleDate(original.addDays(7), original));
        Assert.areEqual(false, ShipmentRules.isValidRescheduleDate(MONDAY, original), 'today');
        Assert.areEqual(false, ShipmentRules.isValidRescheduleDate(original.addDays(8), original));
        Assert.areEqual(false, ShipmentRules.isValidRescheduleDate(null, original));
    }

    @IsTest
    static void passwordRules_AC_005_4() {
        Assert.areEqual(true, ShipmentRules.isValidPassword('abcdefghi1'));
        Assert.areEqual(false, ShipmentRules.isValidPassword('abcdefgh1'), '9 chars');
        Assert.areEqual(false, ShipmentRules.isValidPassword('abcdefghijk'), 'no digit');
        Assert.areEqual(false, ShipmentRules.isValidPassword('12345678901'), 'no letter');
        Assert.areEqual(false, ShipmentRules.isValidPassword(null));
    }

    @IsTest
    static void postalCodeFormat_BR_02() {
        Assert.areEqual(true, ShipmentRules.isValidPostalCode('64000'));
        Assert.areEqual(false, ShipmentRules.isValidPostalCode('6400'));
        Assert.areEqual(false, ShipmentRules.isValidPostalCode('64A00'));
        Assert.areEqual(false, ShipmentRules.isValidPostalCode(null));
    }
}
