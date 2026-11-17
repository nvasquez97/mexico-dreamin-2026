@IsTest
private class ShipmentRulesTest {
    @IsTest
    static void businessDaysAndEstimates() {
        Date friday = Date.newInstance(2026, 11, 20);
        System.assert(ShipmentRules.isBusinessDay(friday));
        System.assert(!ShipmentRules.isBusinessDay(friday.addDays(1)), 'Saturday');
        System.assert(!ShipmentRules.isBusinessDay(friday.addDays(2)), 'Sunday');
        // AC-006.6: +5 business days Standard, +2 Express
        System.assertEquals(Date.newInstance(2026, 11, 27), ShipmentRules.estimatedDelivery(friday, 'Standard'));
        System.assertEquals(Date.newInstance(2026, 11, 24), ShipmentRules.estimatedDelivery(friday, 'Express'));
    }

    @IsTest
    static void pricingFollowsRate() {
        // BR-08: Standard 120 + 18/kg, Express 220 + 30/kg, plus 1.5% of declared value
        System.assertEquals(120 + 36 + 15, ShipmentPricing.calculate('Standard', 2, 1000));
        System.assertEquals(220 + 60 + 15, ShipmentPricing.calculate('Express', 2, 1000));
        System.assertEquals(120 + 9, ShipmentPricing.calculate('Standard', 0.5, 0));
        try {
            ShipmentPricing.calculate('Teleport', 1, 1);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('service type'));
        }
    }

    @IsTest
    static void validators() {
        System.assert(ShipmentRules.isValidPassword('abcdefgh12')); // AC-005.4
        System.assert(!ShipmentRules.isValidPassword('abcdefg12'), 'too short');
        System.assert(!ShipmentRules.isValidPassword('abcdefghijk'), 'no digits');
        System.assert(!ShipmentRules.isValidPassword('1234567890'), 'no letters');
        System.assert(ShipmentRules.isPostalCode(' 06600 '));
        System.assert(!ShipmentRules.isPostalCode('0660'));
        System.assert(ShipmentRules.isEmail('a@b.mx'));
        System.assert(!ShipmentRules.isEmail('a@b'));
        System.assertNotEquals(null, ShipmentRules.today());
    }
}
