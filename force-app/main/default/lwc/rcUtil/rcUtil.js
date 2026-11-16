// Shared helpers. All dates are shown in Mexico City time (BR-06).
const TZ = 'America/Mexico_City';

/** Date-only values arrive as YYYY-MM-DD; format them without any timezone shift. */
export function formatDate(value) {
    if (!value) return '';
    const [y, m, d] = String(value).split('-').map(Number);
    return new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', year: 'numeric', month: 'short', day: 'numeric' }).format(new Date(Date.UTC(y, m - 1, d)));
}

export function formatDateTime(value) {
    if (!value) return '';
    return new Intl.DateTimeFormat('en-US', { timeZone: TZ, year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(value)) + ' (Mexico City)';
}

export function formatMoney(value) {
    if (value === null || value === undefined) return '';
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'MXN' }).format(value);
}

export function errorMessage(error, fallback) {
    const body = error && error.body;
    if (body && body.message && body.message !== 'Script-thrown exception') return body.message;
    return fallback || 'Something went wrong. Please try again.';
}

/** Today in Mexico City as YYYY-MM-DD, used for date input limits. */
export function todayInMexico() {
    return new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
}

export function addDays(isoDate, days) {
    const [y, m, d] = isoDate.split('-').map(Number);
    const date = new Date(Date.UTC(y, m - 1, d + days));
    return date.toISOString().slice(0, 10);
}

export function isBusinessDay(isoDate) {
    const [y, m, d] = isoDate.split('-').map(Number);
    const day = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
    return day !== 0 && day !== 6;
}
