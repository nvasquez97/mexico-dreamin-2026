import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import getShipmentDetail from '@salesforce/apex/MyShipmentsController.getShipmentDetail';
import { errorMessage, formatDate, formatDateTime, formatMoney, statusBadgeClass } from 'c/rcFormat';

/** Detail of one of the customer's shipments (AC-007.3). The server checks ownership. */
export default class RcShipmentDetail extends LightningElement {
    detail;
    errorText;
    shipmentId;
    myShipmentsUrl = `${basePath}/my-shipments`;

    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        const id = pageReference?.state?.shipmentId;
        if (id && id !== this.shipmentId) {
            this.shipmentId = id;
            this.load();
        } else if (!id) {
            this.errorText = 'Shipment not found.';
        }
    }

    get badgeClass() { return statusBadgeClass(this.detail?.status); }
    get price() { return formatMoney(this.detail?.price); }
    get requestDate() { return formatDateTime(this.detail?.requestDate); }
    get estimated() { return formatDate(this.detail?.estimatedDelivery); }
    get pickupDate() { return formatDate(this.detail?.pickupDate); }
    get lastLocation() { return this.detail?.lastLocation || '—'; }
    get lastUpdate() { return formatDateTime(this.detail?.lastUpdate); }
    get instructions() { return this.detail?.deliveryInstructions || 'None'; }
    get reference() { return this.detail?.customerReference || '—'; }
    get weight() { return `${this.detail?.weightKg} kg`; }
    get declaredValue() { return formatMoney(this.detail?.declaredValue); }

    async load() {
        this.errorText = undefined;
        try {
            this.detail = await getShipmentDetail({ shipmentId: this.shipmentId });
        } catch (error) {
            this.detail = undefined;
            this.errorText = errorMessage(error);
        }
    }
}
