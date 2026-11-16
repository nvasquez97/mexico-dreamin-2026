import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import getMyShipments from '@salesforce/apex/RutaCargoController.getMyShipments';
import { errorMessage, formatDate, formatMoney } from 'c/rcUtil';

export default class RcMyShipments extends LightningElement {
    statuses = ['Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'];
    status = '';
    term = '';
    data = [];
    loaded = false;
    isBusy = false;
    error;

    get requestUrl() { return `${basePath}/request-shipment`; }
    get isEmpty() { return this.loaded && this.data.length === 0 && !this.error; }
    get rows() {
        return this.data.map((r) => ({
            ...r,
            detailUrl: `${basePath}/shipment?tn=${encodeURIComponent(r.trackingNumber)}`,
            requestedLabel: formatDate(r.requestedOn),
            priceLabel: formatMoney(r.price),
            pillClass: 'rc-pill' + (r.status === 'Delivered' ? ' rc-pill--delivered' : '')
        }));
    }

    connectedCallback() { this.load(); }
    handleStatus(event) { this.status = event.target.value; this.load(); }
    handleTerm(event) { this.term = event.target.value; }
    handleSubmit(event) { event.preventDefault(); this.load(); }

    async load() {
        this.isBusy = true;
        this.error = undefined;
        try {
            this.data = await getMyShipments({ status: this.status, term: this.term });
        } catch (e) {
            this.data = [];
            this.error = errorMessage(e, 'Please log in to see your shipments.');
        } finally {
            this.loaded = true;
            this.isBusy = false;
        }
    }
}
