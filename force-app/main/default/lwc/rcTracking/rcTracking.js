import { LightningElement } from 'lwc';
import trackShipments from '@salesforce/apex/RutaCargoController.trackShipments';
import { formatDate, formatDateTime, errorMessage } from 'c/rcUtil';

export default class RcTracking extends LightningElement {
    searchBy = 'trackingNumber';
    rawValues = '';
    sortBy = 'estimatedDelivery';
    isLoading = false;
    error;
    found = [];
    notFound = [];
    openTracking;
    searched = false;

    get isByTracking() { return this.searchBy === 'trackingNumber'; }
    get isByReference() { return this.searchBy === 'reference'; }
    get isSortDate() { return this.sortBy === 'estimatedDelivery'; }
    get isSortStatus() { return this.sortBy === 'status'; }
    get placeholder() { return this.isByTracking ? 'RC000001001, RC000001002' : 'ORD-1001, ORD-1002'; }
    get buttonLabel() { return this.isLoading ? 'Searching...' : 'Track'; }
    get hasResults() { return this.found.length > 0; }

    get rows() {
        return this.found.map((item) => {
            const isOpen = this.openTracking === item.trackingNumber;
            return {
                ...item,
                lastUpdateLabel: formatDateTime(item.lastUpdate),
                estimatedLabel: formatDate(item.estimatedDelivery),
                pillClass: 'rc-pill' + (item.status === 'Delivered' ? ' rc-pill--delivered' : ' rc-pill--active'),
                isOpen,
                toggleLabel: isOpen ? 'Hide delivery details' : 'Delivery details'
            };
        });
    }

    handleSearchBy(event) { this.searchBy = event.target.value; }
    handleValues(event) { this.rawValues = event.target.value; }

    handleSort(event) {
        this.sortBy = event.target.value;
        if (this.searched) this.search();
    }

    handleSubmit(event) {
        event.preventDefault();
        this.search();
    }

    handleOpenDelivery(event) {
        const tn = event.currentTarget.dataset.tn;
        this.openTracking = this.openTracking === tn ? undefined : tn;
    }

    async search() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const response = await trackShipments({ searchBy: this.searchBy, rawValues: this.rawValues, sortBy: this.sortBy });
            this.found = response.found;
            this.notFound = response.notFound;
            this.openTracking = undefined;
            this.searched = true;
        } catch (e) {
            this.found = [];
            this.notFound = [];
            this.error = errorMessage(e, 'We could not search right now. Please try again.');
        } finally {
            this.isLoading = false;
        }
    }
}
