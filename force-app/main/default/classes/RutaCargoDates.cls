/**
 * Date helpers. BR-06: every business date is evaluated and shown in Mexico City time,
 * regardless of the running user's time zone (guest, customer, integration user).
 */
public inherited sharing class RutaCargoDates {
  public static final String MEXICO_CITY_TZ = 'America/Mexico_City';

  @TestVisible
  private static Datetime nowOverride;

  public static Datetime now() {
    return nowOverride != null ? nowOverride : Datetime.now();
  }

  /** Today's calendar date in Mexico City. */
  public static Date today() {
    return toMexicoCityDate(now());
  }

  public static Date toMexicoCityDate(Datetime value) {
    return value == null
      ? null
      : Date.valueOf(value.format('yyyy-MM-dd', MEXICO_CITY_TZ));
  }

  /** ISO day of week: 1 = Monday ... 7 = Sunday. */
  public static Integer dayOfWeek(Date value) {
    return Integer.valueOf(
      Datetime.newInstanceGmt(value, Time.newInstance(12, 0, 0, 0))
        .formatGmt('u')
    );
  }

  /** Business days are Monday to Friday. */
  public static Boolean isBusinessDay(Date value) {
    return value != null && dayOfWeek(value) <= 5;
  }

  public static Date addBusinessDays(Date start, Integer businessDays) {
    Date result = start;
    Integer added = 0;
    while (added < businessDays) {
      result = result.addDays(1);
      if (isBusinessDay(result)) {
        added++;
      }
    }
    return result;
  }

  /** "Nov 20, 2026", used in user-facing messages. */
  public static String format(Date value) {
    return value == null
      ? ''
      : Datetime.newInstanceGmt(value, Time.newInstance(12, 0, 0, 0))
          .formatGmt('MMM d, yyyy');
  }
}
