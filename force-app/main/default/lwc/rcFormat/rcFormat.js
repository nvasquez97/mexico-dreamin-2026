/**
 * Formatting helpers for the RutaCargo site. Dates and times are shown in
 * Mexico City time (BR-06). Date-only values (YYYY-MM-DD) carry no time zone,
 * so they are formatted in UTC to avoid shifting them by a day.
 */
const MEXICO_CITY = 'America/Mexico_City';
const DATE_TIME = new Intl.DateTimeFormat('en-US', { timeZone: MEXICO_CITY, dateStyle: 'medium', timeStyle: 'short' });
const DATE_ONLY = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' });
const MONEY = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'MXN' });

export function formatDateTime(value) {
    return value ? `${DATE_TIME.format(new Date(value))} (Mexico City)` : '—';
}

export function formatDate(value) {
    return value ? DATE_ONLY.format(new Date(`${value}T00:00:00Z`)) : '—';
}

export function formatMoney(value) {
    return value === null || value === undefined ? '—' : `${MONEY.format(value)} MXN`.replace('MX$', '$');
}

/** Today in Mexico City as YYYY-MM-DD, for date input limits (the server validates again). */
export function todayInMexicoCity() {
    return new Intl.DateTimeFormat('en-CA', { timeZone: MEXICO_CITY }).format(new Date());
}

export function addDays(isoDate, days) {
    const date = new Date(`${isoDate}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() + days);
    return date.toISOString().slice(0, 10);
}

/** User-facing message from an Apex error; never shows stack traces. */
export function errorMessage(error) {
    const message = error?.body?.message;
    return message && !message.includes('Exception') ? message : 'Something went wrong. Please try again.';
}

export function statusBadgeClass(status) {
    const modifier = { Delivered: 'delivered', Requested: 'requested', Exception: 'exception' }[status];
    return modifier ? `rc-badge rc-badge_${modifier}` : 'rc-badge';
}
