@IsTest
private class RutaCargoDatesTest {
  @IsTest
  static void todayIsEvaluatedInMexicoCity() {
    // BR-06: 2026-11-19 03:00 UTC is still 2026-11-18 21:00 in Mexico City.
    RutaCargoDates.nowOverride = Datetime.newInstanceGmt(2026, 11, 19, 3, 0, 0);
    Assert.areEqual(Date.newInstance(2026, 11, 18), RutaCargoDates.today());
  }

  @IsTest
  static void businessDaysSkipWeekends() {
    Date friday = Date.newInstance(2026, 11, 20);
    Assert.isTrue(RutaCargoDates.isBusinessDay(friday));
    Assert.isFalse(RutaCargoDates.isBusinessDay(friday.addDays(1)));
    Assert.isFalse(RutaCargoDates.isBusinessDay(friday.addDays(2)));
    Assert.areEqual(
      Date.newInstance(2026, 11, 23),
      RutaCargoDates.addBusinessDays(friday, 1)
    );
    Assert.areEqual(
      Date.newInstance(2026, 11, 27),
      RutaCargoDates.addBusinessDays(friday, 5)
    );
  }

  @IsTest
  static void formatsDatesForMessages() {
    Assert.areEqual(
      'Nov 20, 2026',
      RutaCargoDates.format(Date.newInstance(2026, 11, 20))
    );
    Assert.areEqual('', RutaCargoDates.format(null));
    Assert.isNull(RutaCargoDates.toMexicoCityDate(null));
  }
}
