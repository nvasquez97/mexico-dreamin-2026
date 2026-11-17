import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import search from '@salesforce/apex/PublicTrackingController.search';
import { formatDate, formatDateTime, statusDotClass, errorMessage, STATUS_ORDER } from 'c/rcUtils';

export default class RcTrackingSearch extends NavigationMixin(LightningElement) {
    mode = 'tracking';
    values = '';
    loading = false;
    error;
    result;
    sort = 'status';
    _autoSearched = false;

    // QR code on the label: /track?tn=RC000001042 searches right away
    @wire(CurrentPageReference)
    pageRef(ref) {
        const tn = ref && ref.state && ref.state.tn;
        if (tn && !this._autoSearched) {
            this._autoSearched = true;
            this.values = tn;
            this.runSearch();
        }
    }

    get isTracking() {
        return this.mode === 'tracking';
    }
    get isReference() {
        return this.mode === 'reference';
    }
    get trackingClass() {
        return 'rc-radio' + (this.isTracking ? ' on' : '');
    }
    get referenceClass() {
        return 'rc-radio' + (this.isReference ? ' on' : '');
    }
    get valuesLabel() {
        return this.isTracking ? 'Tracking numbers' : 'Order references';
    }
    get placeholder() {
        return this.isTracking ? 'RC000001042' : 'PO-2026-118';
    }
    get sortIsStatus() {
        return this.sort === 'status';
    }
    get sortIsEta() {
        return this.sort === 'eta';
    }
    get hasFound() {
        return this.result && this.result.found.length > 0;
    }
    get hasNotFound() {
        return this.result && this.result.notFound.length > 0;
    }

    // AC-001.4
    get sortedFound() {
        if (!this.hasFound) {
            return [];
        }
        const rows = this.result.found.map((s) => ({
            ...s,
            dotClass: statusDotClass(s.status),
            lastUpdateText: formatDateTime(s.lastUpdate),
            estimatedText: formatDate(s.estimatedDelivery),
            lastLocation: s.lastLocation || '—'
        }));
        const byStatus = (a, b) => STATUS_ORDER.indexOf(a.status) - STATUS_ORDER.indexOf(b.status);
        const byEta = (a, b) => (a.estimatedDelivery || '9999').localeCompare(b.estimatedDelivery || '9999');
        return rows.sort(this.sort === 'eta' ? byEta : byStatus);
    }

    handleMode(event) {
        this.mode = event.target.value;
    }
    handleValues(event) {
        this.values = event.target.value;
    }
    handleSort(event) {
        this.sort = event.target.value;
    }
    handleSubmit(event) {
        event.preventDefault();
        this.runSearch();
    }

    async runSearch() {
        this.error = undefined;
        this.result = undefined;
        this.loading = true;
        try {
            this.result = await search({ mode: this.mode, values: this.values });
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    handleDetails(event) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'Delivery__c' },
            state: { tn: event.currentTarget.dataset.tn }
        });
    }
}
