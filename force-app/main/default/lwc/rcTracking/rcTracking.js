import { LightningElement } from 'lwc';
import track from '@salesforce/apex/PublicTrackingController.track';
import { formatDate, formatDateTime, errorMessage, statusBadgeClass } from 'c/rcFormat';

/**
 * Public tracking (REQ-001): search by tracking number or order reference,
 * up to 10 values, sorted by status or estimated delivery. From each result
 * the recipient can open the delivery details (REQ-002, REQ-003).
 */
export default class RcTracking extends LightningElement {
    searchBy = 'trackingNumber';
    sortBy = 'status';
    rawValues = '';
    shipments = [];
    notFound = [];
    openTracking;
    errorText;
    loading = false;
    searched = false;

    get isByTracking() { return this.searchBy === 'trackingNumber'; }
    get isByReference() { return this.searchBy === 'reference'; }
    get isSortStatus() { return this.sortBy === 'status'; }
    get isSortEstimated() { return this.sortBy === 'estimatedDelivery'; }
    get valuesLabel() { return this.isByTracking ? 'Tracking numbers' : 'Order references'; }
    get placeholder() { return this.isByTracking ? 'RC000001042, RC000001043' : 'PO-1234'; }
    get hasResults() { return this.shipments.length > 0; }
    get hasNotFound() { return this.notFound.length > 0; }

    get rows() {
        return this.shipments.map((s) => {
            const isOpen = s.trackingNumber === this.openTracking;
            return {
                ...s,
                lastLocation: s.lastLocation || '—',
                lastUpdate: formatDateTime(s.lastUpdate),
                estimatedDelivery: formatDate(s.estimatedDelivery),
                badgeClass: statusBadgeClass(s.status),
                isOpen,
                expanded: String(isOpen),
                toggleLabel: isOpen ? 'Hide delivery details' : 'I am the recipient: delivery details'
            };
        });
    }

    handleSearchBy(event) { this.searchBy = event.target.value; }
    handleValues(event) { this.rawValues = event.target.value; }

    handleSort(event) {
        this.sortBy = event.target.value;
        if (this.searched) {
            this.runSearch();
        }
    }

    handleSearch(event) {
        event.preventDefault();
        this.runSearch();
    }

    async runSearch() {
        this.errorText = undefined;
        if (!this.rawValues.trim()) {
            this.errorText = 'Enter at least one tracking number or order reference.';
            return;
        }
        this.loading = true;
        try {
            const result = await track({ searchBy: this.searchBy, rawValues: this.rawValues, sortBy: this.sortBy });
            this.shipments = result.shipments;
            this.notFound = result.notFound;
            this.searched = true;
            this.openTracking = undefined;
        } catch (error) {
            this.shipments = [];
            this.notFound = [];
            this.errorText = errorMessage(error);
        } finally {
            this.loading = false;
        }
    }

    toggleDelivery(event) {
        const tracking = event.currentTarget.dataset.tracking;
        this.openTracking = this.openTracking === tracking ? undefined : tracking;
    }
}
