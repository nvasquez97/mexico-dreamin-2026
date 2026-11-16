/**
 * Tests for PricingService.
 * Covers BR-08 (current rate), AC-006.2 (price before confirming) and AC-006.4 (limits).
 */
@IsTest
private class PricingServiceTest {

    // Covers BR-08: the deployed rate is Standard 120 + 18/kg, Express 220 + 30/kg, 1.5% insurance.
    @IsTest
    static void shouldMatchBusinessRule_WhenReadingDeployedRates() {
        Shipping_Rate__mdt standardRate = Shipping_Rate__mdt.getInstance('Standard');
        Shipping_Rate__mdt expressRate = Shipping_Rate__mdt.getInstance('Express');
        Assert.areEqual(120, standardRate.Base_Price__c, 'Standard base');
        Assert.areEqual(18, standardRate.Price_Per_Kg__c, 'Standard per kg');
        Assert.areEqual(220, expressRate.Base_Price__c, 'Express base');
        Assert.areEqual(30, expressRate.Price_Per_Kg__c, 'Express per kg');
        Assert.areEqual(1.5, standardRate.Insurance_Percent__c, 'Standard insurance');
        Assert.areEqual(1.5, expressRate.Insurance_Percent__c, 'Express insurance');
    }

    // Covers AC-006.2, BR-08: Standard 2 kg, declared 1,000 -> 120 + 36 + 15 = 171.00.
    @IsTest
    static void shouldPriceStandard_WhenValidInput() {
        Assert.areEqual(171.00, PricingService.calculatePrice('Standard', 2, 1000), 'Standard price');
    }

    // Covers AC-006.2, BR-08: Express 10 kg, declared 50,000 -> 220 + 300 + 750 = 1,270.00.
    @IsTest
    static void shouldPriceExpress_WhenAtDeclaredValueLimit() {
        Assert.areEqual(1270.00, PricingService.calculatePrice('Express', 10, 50000), 'Express price');
    }

    // Covers BR-08: decimals are rounded half-up to cents (120 + 45 + 4.99995 = 169.99995 -> 170.00).
    @IsTest
    static void shouldRoundToCents_WhenFractionalInsurance() {
        Assert.areEqual(170.00, PricingService.calculatePrice('Standard', 2.5, 333.33), 'Rounded price');
    }

    // Covers AC-006.4: 30 kg is accepted.
    @IsTest
    static void shouldAcceptWeight_WhenExactlyThirtyKg() {
        Assert.areEqual(660.00, PricingService.calculatePrice('Standard', 30, 0), '120 + 540 + 0');
    }

    // Covers AC-006.4: more than 30 kg is rejected.
    @IsTest
    static void shouldReject_WhenWeightAboveThirtyKg() {
        assertRejected('Standard', 30.01, 100, 'maximum weight');
    }

    // Covers AC-006.4: more than 50,000 MXN declared value is rejected.
    @IsTest
    static void shouldReject_WhenDeclaredValueAboveLimit() {
        assertRejected('Express', 1, 50000.01, 'maximum declared value');
    }

    // Covers AC-006.4: zero or negative weight is rejected.
    @IsTest
    static void shouldReject_WhenWeightNotPositive() {
        assertRejected('Standard', 0, 100, 'weight');
    }

    // Covers AC-006.4: negative declared value is rejected.
    @IsTest
    static void shouldReject_WhenDeclaredValueNegative() {
        assertRejected('Standard', 1, -1, 'declared value');
    }

    // Covers AC-006.1: only Standard or Express are valid service types.
    @IsTest
    static void shouldReject_WhenUnknownServiceType() {
        assertRejected('Overnight', 1, 100, 'service type');
    }

    // Covers AC-006.6: transit days come from the rate (Standard 5, Express 2).
    @IsTest
    static void shouldReturnTransitDays_WhenKnownServiceType() {
        Assert.areEqual(5, PricingService.getTransitBusinessDays('Standard'), 'Standard transit days');
        Assert.areEqual(2, PricingService.getTransitBusinessDays('Express'), 'Express transit days');
    }

    private static void assertRejected(String serviceType, Decimal weightKg, Decimal declaredValue, String expectedText) {
        try {
            PricingService.calculatePrice(serviceType, weightKg, declaredValue);
            Assert.fail('Expected PricingException');
        } catch (PricingService.PricingException e) {
            Assert.isTrue(e.getMessage().toLowerCase().contains(expectedText),
                'Message should mention ' + expectedText + ' but was: ' + e.getMessage());
        }
    }
}
