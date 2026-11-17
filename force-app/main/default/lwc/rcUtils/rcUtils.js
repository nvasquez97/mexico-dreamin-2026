// Shared helpers for the RutaCargo site. Dates follow BR-06: Mexico City time.
const TZ = 'America/Mexico_City';

export const STATUS_ORDER = ['Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'];

/** 'YYYY-MM-DD' (a date without time) -> 'Nov 20, 2026'. No time zone shifting. */
export function formatDate(iso) {
    if (!iso) {
        return '—';
    }
    const [y, m, d] = iso.split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        timeZone: 'UTC'
    });
}

/** Date/time value -> Mexico City local time. */
export function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    return (
        new Date(value).toLocaleString('en-US', {
            timeZone: TZ,
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
        }) + ' (Mexico City)'
    );
}

export function formatMoney(value) {
    if (value === null || value === undefined) {
        return '—';
    }
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'MXN' }).format(value);
}

export function statusDotClass(status) {
    const map = {
        Requested: 'rc-dot-requested',
        'Picked up': 'rc-dot-transit',
        'In transit': 'rc-dot-transit',
        'Out for delivery': 'rc-dot-out',
        Delivered: 'rc-dot-delivered',
        Exception: 'rc-dot-exception'
    };
    return 'rc-dot ' + (map[status] || '');
}

/** Message from an Apex / Aura / JS error. */
export function errorMessage(e) {
    if (e && e.body) {
        if (typeof e.body.message === 'string') {
            return e.body.message;
        }
        if (Array.isArray(e.body) && e.body.length) {
            return e.body.map((x) => x.message).join(' ');
        }
        if (e.body.pageErrors && e.body.pageErrors.length) {
            return e.body.pageErrors[0].message;
        }
    }
    return (e && e.message) || 'Something went wrong. Please try again.';
}

/** Date input value (YYYY-MM-DD) of "today" in Mexico City + n days. */
export function mexicoDatePlus(days) {
    const parts = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' })
        .format(new Date())
        .split('-')
        .map(Number);
    const d = new Date(Date.UTC(parts[0], parts[1] - 1, parts[2] + days));
    return d.toISOString().slice(0, 10);
}

/** Saves a base64 PDF to the user's device. */
export function downloadBase64(base64, fileName, mime = 'application/pdf') {
    const bytes = atob(base64);
    const buf = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
        buf[i] = bytes.charCodeAt(i);
    }
    const url = URL.createObjectURL(new Blob([buf], { type: mime }));
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
}
