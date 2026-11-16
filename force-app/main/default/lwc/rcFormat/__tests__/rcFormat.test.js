// Covers BR-06: dates are shown in Mexico City time; date-only values are not shifted.
import { formatDate, formatDateTime, formatMoney, addDays, errorMessage, statusBadgeClass } from 'c/rcFormat';

describe('c-rc-format', () => {
    it('shows a UTC timestamp in Mexico City time (BR-06)', () => {
        // 2026-11-20 16:00 UTC = 10:00 in Mexico City (UTC-6)
        expect(formatDateTime('2026-11-20T16:00:00.000Z')).toBe('Nov 20, 2026, 10:00 AM (Mexico City)');
    });

    it('keeps the Mexico City date when UTC is already the next day (BR-06)', () => {
        // 2026-11-21 03:30 UTC is still Nov 20, 21:30 in Mexico City
        expect(formatDateTime('2026-11-21T03:30:00.000Z')).toBe('Nov 20, 2026, 9:30 PM (Mexico City)');
    });

    it('does not shift a date-only value by the time zone', () => {
        expect(formatDate('2026-11-23')).toBe('Mon, Nov 23, 2026');
    });

    it('shows a dash for missing values', () => {
        expect(formatDate(null)).toBe('—');
        expect(formatDateTime(undefined)).toBe('—');
        expect(formatMoney(null)).toBe('—');
    });

    it('formats prices in MXN', () => {
        expect(formatMoney(1270)).toBe('$1,270.00 MXN');
    });

    it('adds calendar days to an ISO date', () => {
        expect(addDays('2026-11-30', 1)).toBe('2026-12-01');
    });

    it('never shows internal exception text', () => {
        expect(errorMessage({ body: { message: 'System.NullPointerException: x' } })).toBe('Something went wrong. Please try again.');
        expect(errorMessage({ body: { message: 'Choose a valid status.' } })).toBe('Choose a valid status.');
    });

    it('maps statuses to badge styles', () => {
        expect(statusBadgeClass('Delivered')).toBe('rc-badge rc-badge_delivered');
        expect(statusBadgeClass('In transit')).toBe('rc-badge');
    });
});
