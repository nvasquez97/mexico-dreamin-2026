/**
 * @description Proves ShipmentRequestRules, the one pricing and dates service of
 *              customer shipment requests (odd/tasks/req-006-007-customer-shipments.md,
 *              S1): the BR-08 price (AC-006.2), the BR-06 pickup window of business
 *              days in Mexico City (AC-006.3), the weight and declared value limits
 *              (AC-006.4), the estimated delivery in business days (AC-006.6) and
 *              the recipient email format shared by the controller and the
 *              customer-insert guard (AC-006.1). Pure functions: no records are needed.
 */
@IsTest
private with sharing class ShipmentRequestRulesTest {

    private static final String STANDARD = 'Standard';
    private static final String EXPRESS = 'Express';
    private static final Date THURSDAY = Date.newInstance(2026, 11, 19);
    private static final Date FRIDAY = Date.newInstance(2026, 11, 20);
    private static final Date SATURDAY = Date.newInstance(2026, 11, 21);
    private static final Date SUNDAY = Date.newInstance(2026, 11, 22);
    private static final Date MONDAY = Date.newInstance(2026, 11, 23);

    // ─── AC-006.1: recipient email ───────────────────────────────────────────

    @IsTest
    static void isValidEmail_acceptsAPlainAddress() {
        // AC-006.1: laura.gomez@example.com is a valid recipient email
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidEmail('laura.gomez@example.com');
        Test.stopTest();
        Assert.isTrue(valid, 'laura.gomez@example.com must be a valid email');
    }

    @IsTest
    static void isValidEmail_acceptsASubdomainAddressWithSpaces() {
        // AC-006.1: a padded address with a plus tag and a subdomain is valid once trimmed
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidEmail('  pedro+envios@mail.example.com.mx ');
        Test.stopTest();
        Assert.isTrue(valid, 'A padded address with a subdomain must be a valid email');
    }

    @IsTest
    static void isValidEmail_refusesAnAddressWithoutTheAtSign() {
        // AC-006.1: "laura.gomez at example" is not an email
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidEmail('laura.gomez at example');
        Test.stopTest();
        Assert.isFalse(valid, 'An address without @ must be refused');
    }

    @IsTest
    static void isValidEmail_refusesABlankValue() {
        // AC-006.1: a blank email is not valid
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidEmail('   ');
        Test.stopTest();
        Assert.isFalse(valid, 'A blank email must be refused');
    }

    @IsTest
    static void isValidEmail_refusesNull() {
        // AC-006.1: a missing email is not valid
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidEmail(null);
        Test.stopTest();
        Assert.isFalse(valid, 'A null email must be refused');
    }

    // ─── AC-006.2 (BR-08): price ─────────────────────────────────────────────

    @IsTest
    static void price_isStandardBasePlusPerKgPlusInsurance() {
        // AC-006.2: Standard 2.5 kg, declared 1,000.00 → 120 + 45 + 15 = 180.00
        Test.startTest();
        Decimal price = ShipmentRequestRules.price(STANDARD, 2.5, 1000);
        Test.stopTest();
        Assert.areEqual(180.00, price, 'Standard 2.5 kg declared 1,000.00 must cost 180.00');
    }

    @IsTest
    static void price_isExpressBasePlusPerKgPlusInsurance() {
        // AC-006.2: Express 2.5 kg, declared 1,000.00 → 220 + 75 + 15 = 310.00
        Test.startTest();
        Decimal price = ShipmentRequestRules.price(EXPRESS, 2.5, 1000);
        Test.stopTest();
        Assert.areEqual(310.00, price, 'Express 2.5 kg declared 1,000.00 must cost 310.00');
    }

    @IsTest
    static void price_isExpressAtTheMaximumWeightAndDeclaredValue() {
        // AC-006.2: Express 30 kg, declared 50,000.00 → 220 + 900 + 750 = 1,870.00
        Test.startTest();
        Decimal price = ShipmentRequestRules.price(EXPRESS, 30, 50000);
        Test.stopTest();
        Assert.areEqual(1870.00, price, 'Express 30 kg declared 50,000.00 must cost 1,870.00');
    }

    @IsTest
    static void price_isRoundedHalfUpToTwoDecimals() {
        // AC-006.2 (G4): Standard 1.25 kg, declared 333.33 → 147.49995 → 147.50
        Test.startTest();
        Decimal price = ShipmentRequestRules.price(STANDARD, 1.25, 333.33);
        Test.stopTest();
        Assert.areEqual('147.50', String.valueOf(price), 'The price must be 147.49995 rounded half-up to 147.50');
    }

    @IsTest
    static void price_hasNoInsurance_whenTheDeclaredValueIsZero() {
        // AC-006.2 (G4): declared value 0 → Standard 1 kg = 120 + 18 + 0 = 138.00
        Test.startTest();
        Decimal price = ShipmentRequestRules.price(STANDARD, 1, 0);
        Test.stopTest();
        Assert.areEqual(138.00, price, 'A declared value of 0 adds no insurance');
    }

    @IsTest
    static void price_throws_whenTheWeightHasThreeDecimals() {
        // AC-006.2 (G6): 1.333 kg is rejected (more than 2 decimals)
        Test.startTest();
        try {
            ShipmentRequestRules.price(STANDARD, 1.333, 1000);
            Assert.fail('A weight of 1.333 kg must be rejected');
        } catch (ShipmentRequestRules.InvalidRequestException e) {
            Assert.areEqual(ShipmentRequestRules.INVALID_REQUEST_MESSAGE, e.getMessage(), 'The rejection must be generic');
        }
        Test.stopTest();
    }

    @IsTest
    static void price_throws_whenTheServiceTypeIsUnknown() {
        // AC-006.2: only Standard and Express have a rate
        Test.startTest();
        try {
            ShipmentRequestRules.price('Overnight', 2.5, 1000);
            Assert.fail('An unknown service type must be rejected');
        } catch (ShipmentRequestRules.InvalidRequestException e) {
            Assert.areEqual(ShipmentRequestRules.INVALID_REQUEST_MESSAGE, e.getMessage(), 'The rejection must be generic');
        }
        Test.stopTest();
    }

    // ─── AC-006.4: weight and declared value ─────────────────────────────────

    @IsTest
    static void weight_isAccepted_atThirtyKilograms() {
        // AC-006.4: 30.00 kg is accepted; 0.01 kg (the smallest) too
        Test.startTest();
        String actual = ShipmentRequestRules.isValidWeight(30.00) + ' ' + ShipmentRequestRules.isValidWeight(0.01);
        Test.stopTest();
        Assert.areEqual('true true', actual, 'Weights of 30.00 and 0.01 kg must be accepted');
    }

    @IsTest
    static void weight_isRejected_aboveThirtyKilograms() {
        // AC-006.4: 30.01 kg is rejected
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidWeight(30.01);
        Test.stopTest();
        Assert.isFalse(valid, 'A weight of 30.01 kg must be rejected');
    }

    @IsTest
    static void weight_isRejected_whenZeroOrNegative() {
        // AC-006.4: 0 and a negative weight are rejected
        Test.startTest();
        String actual = ShipmentRequestRules.isValidWeight(0) + ' ' + ShipmentRequestRules.isValidWeight(-1);
        Test.stopTest();
        Assert.areEqual('false false', actual, 'Weights of 0 and -1 kg must be rejected');
    }

    @IsTest
    static void weight_isRejected_withThreeDecimals() {
        // AC-006.4 (G6): a weight with 3 decimals is rejected
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidWeight(1.333);
        Test.stopTest();
        Assert.isFalse(valid, 'A weight of 1.333 kg must be rejected');
    }

    @IsTest
    static void weight_isRejected_whenMissing() {
        // AC-006.4: a missing weight is rejected
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidWeight(null);
        Test.stopTest();
        Assert.isFalse(valid, 'A missing weight must be rejected');
    }

    @IsTest
    static void declaredValue_isAccepted_fromZeroToFiftyThousand() {
        // AC-006.4 (G4): 50,000.00 and 0 are accepted
        Test.startTest();
        String actual = ShipmentRequestRules.isValidDeclaredValue(50000.00) + ' ' + ShipmentRequestRules.isValidDeclaredValue(0);
        Test.stopTest();
        Assert.areEqual('true true', actual, 'Declared values of 50,000.00 and 0 must be accepted');
    }

    @IsTest
    static void declaredValue_isRejected_aboveFiftyThousand() {
        // AC-006.4: 50,000.01 is rejected
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidDeclaredValue(50000.01);
        Test.stopTest();
        Assert.isFalse(valid, 'A declared value of 50,000.01 must be rejected');
    }

    @IsTest
    static void declaredValue_isRejected_whenNegative() {
        // AC-006.4: a negative declared value is rejected
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidDeclaredValue(-0.01);
        Test.stopTest();
        Assert.isFalse(valid, 'A declared value of -0.01 must be rejected');
    }

    // ─── AC-006.3 (BR-06): pickup date ───────────────────────────────────────

    @IsTest
    static void pickupDate_isRejected_whenItIsToday() {
        // AC-006.3: T = Thursday 2026-11-19; pickup 2026-11-19 is rejected
        ShipmentRequestRules.todayOverride = THURSDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(THURSDAY);
        Test.stopTest();
        Assert.isFalse(valid, 'A pickup today must be rejected');
    }

    @IsTest
    static void pickupDate_isRejected_onSaturday() {
        // AC-006.3: T = Thursday 2026-11-19; Saturday 2026-11-21 is rejected
        ShipmentRequestRules.todayOverride = THURSDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(SATURDAY);
        Test.stopTest();
        Assert.isFalse(valid, 'A pickup on Saturday 2026-11-21 must be rejected');
    }

    @IsTest
    static void pickupDate_isRejected_onSunday() {
        // AC-006.3: T = Thursday 2026-11-19; Sunday 2026-11-22 is rejected
        ShipmentRequestRules.todayOverride = THURSDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(SUNDAY);
        Test.stopTest();
        Assert.isFalse(valid, 'A pickup on Sunday 2026-11-22 must be rejected');
    }

    @IsTest
    static void pickupDate_isAccepted_fromTheNextDayToFifteenDaysLater() {
        // AC-006.3: T = Thursday 2026-11-19; Friday 2026-11-20 (T+1) and
        // Friday 2026-12-04 (T+15) are accepted
        ShipmentRequestRules.todayOverride = THURSDAY;
        Test.startTest();
        String actual = ShipmentRequestRules.isValidPickupDate(FRIDAY) + ' '
            + ShipmentRequestRules.isValidPickupDate(Date.newInstance(2026, 12, 4));
        Test.stopTest();
        Assert.areEqual('true true', actual, 'Pickups on 2026-11-20 (T+1) and 2026-12-04 (T+15) must be accepted');
    }

    @IsTest
    static void pickupDate_isRejected_onTheSaturdayAfterAFriday() {
        // AC-006.3: T = Friday 2026-11-20; Saturday 2026-11-21 (T+1) is rejected
        ShipmentRequestRules.todayOverride = FRIDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(SATURDAY);
        Test.stopTest();
        Assert.isFalse(valid, 'A pickup on Saturday T+1 must be rejected');
    }

    @IsTest
    static void pickupDate_isAccepted_onTheMondayAfterAFriday() {
        // AC-006.3: T = Friday 2026-11-20; Monday 2026-11-23 is accepted
        ShipmentRequestRules.todayOverride = FRIDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(MONDAY);
        Test.stopTest();
        Assert.isTrue(valid, 'A pickup on Monday 2026-11-23 must be accepted');
    }

    @IsTest
    static void pickupDate_isAccepted_onTheFifteenthDayFromAMonday() {
        // AC-006.3: T = Monday 2026-11-23; Tuesday 2026-12-08 (T+15) is accepted
        ShipmentRequestRules.todayOverride = MONDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(Date.newInstance(2026, 12, 8));
        Test.stopTest();
        Assert.isTrue(valid, 'A pickup on Tuesday 2026-12-08 (T+15) must be accepted');
    }

    @IsTest
    static void pickupDate_isRejected_onTheSixteenthDayFromAMonday() {
        // AC-006.3: T = Monday 2026-11-23; Wednesday 2026-12-09 (T+16) is rejected
        ShipmentRequestRules.todayOverride = MONDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(Date.newInstance(2026, 12, 9));
        Test.stopTest();
        Assert.isFalse(valid, 'A pickup on Wednesday 2026-12-09 (T+16) must be rejected');
    }

    @IsTest
    static void pickupDate_isRejected_whenMissing() {
        // AC-006.3: a missing pickup date is rejected
        ShipmentRequestRules.todayOverride = THURSDAY;
        Test.startTest();
        Boolean valid = ShipmentRequestRules.isValidPickupDate(null);
        Test.stopTest();
        Assert.isFalse(valid, 'A missing pickup date must be rejected');
    }

    @IsTest
    static void pickupWindow_isTheFirstAndLastBusinessDayOfTheWindow() {
        // AC-006.3: T = Friday 2026-11-20 → earliest Monday 2026-11-23; T+15 is
        // Saturday 2026-12-05 → latest Friday 2026-12-04
        ShipmentRequestRules.todayOverride = FRIDAY;
        Test.startTest();
        List<Date> actual = new List<Date>{ ShipmentRequestRules.earliestPickupDate(), ShipmentRequestRules.latestPickupDate() };
        Test.stopTest();
        Assert.areEqual(new List<Date>{ MONDAY, Date.newInstance(2026, 12, 4) }, actual,
            'The pickup window from Friday 2026-11-20 must be 2026-11-23 to 2026-12-04');
    }

    @IsTest
    static void today_isTheMexicoCityDate_withoutTheSeam() {
        // AC-006.3 (BR-06): "today" is the current date in America/Mexico_City
        Date expected = Date.valueOf(Datetime.now().format('yyyy-MM-dd', 'America/Mexico_City'));
        Test.startTest();
        Date actual = ShipmentRequestRules.today();
        Test.stopTest();
        Assert.areEqual(expected, actual, 'Today must be the Mexico City date');
    }

    // ─── AC-006.6 (BR-06): estimated delivery ────────────────────────────────

    @IsTest
    static void estimate_isTheFollowingThursday_forStandardFromAThursday() {
        // AC-006.6: pickup Thursday 2026-11-19, Standard → Thursday 2026-11-26 (+5)
        Test.startTest();
        Date estimate = ShipmentRequestRules.estimatedDelivery(STANDARD, THURSDAY);
        Test.stopTest();
        Assert.areEqual(Date.newInstance(2026, 11, 26), estimate, 'Standard from Thursday must arrive the next Thursday');
    }

    @IsTest
    static void estimate_isTheMonday_forExpressFromAThursday() {
        // AC-006.6: pickup Thursday 2026-11-19, Express → Monday 2026-11-23 (+2)
        Test.startTest();
        Date estimate = ShipmentRequestRules.estimatedDelivery(EXPRESS, THURSDAY);
        Test.stopTest();
        Assert.areEqual(MONDAY, estimate, 'Express from Thursday must arrive on Monday');
    }

    @IsTest
    static void estimate_isTheNextFriday_forStandardFromAFriday() {
        // AC-006.6: pickup Friday 2026-11-20, Standard → Friday 2026-11-27 (+5)
        Test.startTest();
        Date estimate = ShipmentRequestRules.estimatedDelivery(STANDARD, FRIDAY);
        Test.stopTest();
        Assert.areEqual(Date.newInstance(2026, 11, 27), estimate, 'Standard from Friday must arrive the next Friday');
    }

    @IsTest
    static void estimate_isTheTuesday_forExpressFromAFriday() {
        // AC-006.6: pickup Friday 2026-11-20, Express → Tuesday 2026-11-24 (+2)
        Test.startTest();
        Date estimate = ShipmentRequestRules.estimatedDelivery(EXPRESS, FRIDAY);
        Test.stopTest();
        Assert.areEqual(Date.newInstance(2026, 11, 24), estimate, 'Express from Friday must arrive on Tuesday');
    }
}
