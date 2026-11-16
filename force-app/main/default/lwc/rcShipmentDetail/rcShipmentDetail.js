import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import getMyShipment from '@salesforce/apex/RutaCargoController.getMyShipment';
import { errorMessage, formatDate, formatMoney } from 'c/rcUtil';

export default class RcShipmentDetail extends LightningElement {
    detail;
    error;
    trackingNumber;

    get listUrl() { return `${basePath}/my-shipments`; }
    get pillClass() { return 'rc-pill' + (this.detail.summary.status === 'Delivered' ? ' rc-pill--delivered' : ' rc-pill--active'); }
    get priceLabel() { return formatMoney(this.detail.summary.price); }
    get declaredLabel() { return formatMoney(this.detail.declaredValue); }
    get requestedLabel() { return formatDate(this.detail.summary.requestedOn); }
    get estimatedLabel() { return formatDate(this.detail.estimatedDelivery); }
    get pickupLabel() { return formatDate(this.detail.pickupDate); }

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const tn = ref && ref.state && ref.state.tn;
        if (tn && tn !== this.trackingNumber) {
            this.trackingNumber = tn;
            this.load();
        }
    }

    async load() {
        this.error = undefined;
        try {
            const result = await getMyShipment({ trackingNumber: this.trackingNumber });
            if (result) {
                this.detail = result;
            } else {
                this.detail = undefined;
                this.error = 'We could not find that shipment in your account.';
            }
        } catch (e) {
            this.detail = undefined;
            this.error = errorMessage(e, 'Please log in to see this shipment.');
        }
    }
}
