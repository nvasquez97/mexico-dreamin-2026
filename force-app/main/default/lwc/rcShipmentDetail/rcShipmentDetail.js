import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import isGuestUser from '@salesforce/user/isGuest';
import getShipment from '@salesforce/apex/CustomerPortalController.getShipment';
import { formatDate, formatDateTime, formatMoney, statusDotClass, errorMessage } from 'c/rcUtils';

export default class RcShipmentDetail extends NavigationMixin(LightningElement) {
    isGuest = isGuestUser;
    d;
    error;
    loading = false;
    _tn;

    @wire(CurrentPageReference)
    pageRef(ref) {
        const tn = ref && ref.state && ref.state.tn;
        if (tn && tn !== this._tn && !this.isGuest) {
            this._tn = tn;
            this.load(tn);
        }
    }

    async load(tn) {
        this.loading = true;
        this.error = undefined;
        try {
            this.d = await getShipment({ trackingNumber: tn });
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    get dotClass() {
        return statusDotClass(this.d.summary.status);
    }
    get lastLocation() {
        return this.d.lastLocation || '—';
    }
    get lastUpdate() {
        return formatDateTime(this.d.lastUpdate);
    }
    get estimated() {
        return formatDate(this.d.estimatedDelivery);
    }
    get price() {
        return formatMoney(this.d.summary.price);
    }
    get requested() {
        return formatDateTime(this.d.summary.requestedAt);
    }
    get pickupDate() {
        return formatDate(this.d.input.pickupDate);
    }
    get declared() {
        return formatMoney(this.d.input.declaredValue);
    }
    get reference() {
        return this.d.input.customerReference || '—';
    }
    get instructions() {
        return this.d.input.deliveryInstructions || '—';
    }

    goList() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'My_Shipments__c' } });
    }
    goLogin() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Login' } });
    }
}
