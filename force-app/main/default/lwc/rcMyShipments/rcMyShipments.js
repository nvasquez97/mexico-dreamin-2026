import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import getMyShipments from '@salesforce/apex/MyShipmentsController.getMyShipments';
import { errorMessage, formatDateTime, formatMoney, statusBadgeClass } from 'c/rcFormat';

const STATUSES = ['Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'];

/** The customer's shipments, most recent first, with status filter and search (REQ-007). */
export default class RcMyShipments extends LightningElement {
    status = '';
    searchTerm = '';
    shipments = [];
    errorText;
    loading = false;
    loaded = false;

    connectedCallback() {
        this.load();
    }

    get statusOptions() {
        return [{ value: '', label: 'All statuses' }, ...STATUSES.map((s) => ({ value: s, label: s }))]
            .map((option) => ({ ...option, selected: option.value === this.status }));
    }

    get isEmpty() { return this.loaded && !this.loading && !this.errorText && this.shipments.length === 0; }

    get rows() {
        return this.shipments.map((s) => ({
            ...s,
            requestDate: formatDateTime(s.requestDate),
            price: formatMoney(s.price),
            badgeClass: statusBadgeClass(s.status),
            detailUrl: `${basePath}/shipment?shipmentId=${encodeURIComponent(s.id)}`
        }));
    }

    handleStatus(event) {
        this.status = event.target.value;
        this.load();
    }

    handleSearchTerm(event) { this.searchTerm = event.target.value; }

    handleSearch(event) {
        event.preventDefault();
        this.load();
    }

    async load() {
        this.errorText = undefined;
        this.loading = true;
        try {
            this.shipments = await getMyShipments({ status: this.status, searchTerm: this.searchTerm });
        } catch (error) {
            this.shipments = [];
            this.errorText = errorMessage(error);
        } finally {
            this.loading = false;
            this.loaded = true;
        }
    }
}
