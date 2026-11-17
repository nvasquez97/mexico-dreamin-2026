/** BR-08 — current rate. */
@IsTest
private class ShipmentPricingTest {
  @IsTest
  static void standardRate() {
    // 120 + 18 * 2.5 + 1.5% of 1,000 = 120 + 45 + 15
    ShipmentPricing.Quote q = ShipmentPricing.quote('Standard', 2.5, 1000);
    Assert.areEqual(120, q.basePrice);
    Assert.areEqual(45, q.weightCharge);
    Assert.areEqual(15, q.insurance);
    Assert.areEqual(180, q.total);
  }

  @IsTest
  static void expressRate() {
    // 220 + 30 * 10 + 1.5% of 50,000 = 220 + 300 + 750
    Assert.areEqual(1270, ShipmentPricing.calculate('Express', 10, 50000));
  }

  @IsTest
  static void insuranceIsRoundedToCents() {
    // 1.5% of 333.33 = 4.99995 -> 5.00
    Assert.areEqual(
      120 + 18 + 5.00,
      ShipmentPricing.calculate('Standard', 1, 333.33)
    );
  }

  @IsTest
  static void rejectsUnknownServiceOrMissingData() {
    try {
      ShipmentPricing.calculate('Overnight', 1, 1);
      Assert.fail('Expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('Overnight'));
    }
    try {
      ShipmentPricing.calculate('Standard', null, 1);
      Assert.fail('Expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isNotNull(e.getMessage());
    }
  }
}
