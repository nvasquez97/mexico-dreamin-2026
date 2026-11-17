import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuestUser from '@salesforce/user/isGuest';
import listShipments from '@salesforce/apex/CustomerPortalController.listShipments';
import { formatDateTime, formatMoney, statusDotClass, errorMessage, STATUS_ORDER } from 'c/rcUtils';

const SEARCH_DELAY_MS = 350;

export default class RcMyShipments extends NavigationMixin(LightningElement) {
    isGuest = isGuestUser;
    statusOptions = STATUS_ORDER;
    status = '';
    searchTerm = '';
    shipments = [];
    hasMore = false;
    loading = false;
    error;
    _timer;
    _requestId = 0;

    connectedCallback() {
        if (!this.isGuest) {
            this.load(true);
        }
    }

    get rows() {
        return this.shipments.map((s) => ({
            ...s,
            dotClass: statusDotClass(s.status),
            requestedText: formatDateTime(s.requestedAt).replace(' (Mexico City)', ''),
            priceText: formatMoney(s.price)
        }));
    }
    get isEmpty() {
        return !this.loading && !this.error && this.shipments.length === 0;
    }

    handleStatus(event) {
        this.status = event.target.value;
        this.load(true);
    }
    handleSearch(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._timer);
        this._timer = setTimeout(() => this.load(true), SEARCH_DELAY_MS);
    }
    handleMore() {
        this.load(false);
    }

    async load(reset) {
        const id = ++this._requestId; // ignore stale answers while the user keeps typing
        this.loading = true;
        this.error = undefined;
        try {
            const page = await listShipments({
                status: this.status,
                searchTerm: this.searchTerm,
                offset: reset ? 0 : this.shipments.length
            });
            if (id !== this._requestId) {
                return;
            }
            this.shipments = reset ? page.shipments : [...this.shipments, ...page.shipments];
            this.hasMore = page.hasMore;
        } catch (e) {
            if (id === this._requestId) {
                this.error = errorMessage(e);
            }
        } finally {
            if (id === this._requestId) {
                this.loading = false;
            }
        }
    }

    handleOpen(event) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'Shipment_Detail__c' },
            state: { tn: event.currentTarget.dataset.tn }
        });
    }
    goRequest() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Request__c' } });
    }
    goLogin() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Login' } });
    }
    goSignup() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Register' } });
    }
}
