import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import getQuote from '@salesforce/apex/ShipmentRequestController.getQuote';
import createShipment from '@salesforce/apex/ShipmentRequestController.createShipment';
import { addDays, errorMessage, formatDate, formatMoney, todayInMexicoCity } from 'c/rcFormat';

const EMPTY = {
    pickupAddress: '', pickupCity: '', pickupPostalCode: '', pickupDate: '',
    recipientName: '', recipientAddress: '', recipientCity: '', recipientPostalCode: '',
    recipientPhone: '', recipientEmail: '', deliveryInstructions: '',
    weightKg: '', declaredValue: '', packageDescription: '', customerReference: ''
};

/**
 * Door-to-door shipment request (REQ-006). The customer sees the price before
 * confirming (AC-006.2); any change to the form clears the price so the
 * confirmed request always matches the quote. The server validates and prices again.
 */
export default class RcShipmentRequest extends LightningElement {
    pickupAddress = '';
    pickupCity = '';
    pickupPostalCode = '';
    pickupDate = '';
    recipientName = '';
    recipientAddress = '';
    recipientCity = '';
    recipientPostalCode = '';
    recipientPhone = '';
    recipientEmail = '';
    deliveryInstructions = '';
    weightKg = '';
    declaredValue = '';
    packageDescription = '';
    customerReference = '';
    serviceType = 'Standard';
    quote;
    created;
    errorText;
    loading = false;
    myShipmentsUrl = `${basePath}/my-shipments`;

    get isStandard() { return this.serviceType === 'Standard'; }
    get isExpress() { return this.serviceType === 'Express'; }
    get minPickupDate() { return addDays(todayInMexicoCity(), 1); }
    get maxPickupDate() { return addDays(todayInMexicoCity(), 15); }
    get confirmDisabled() { return this.loading || !this.quote; }
    get quotePrice() { return formatMoney(this.quote?.price); }
    get quoteEstimate() { return formatDate(this.quote?.estimatedDelivery); }
    get createdPrice() { return formatMoney(this.created?.price); }
    get createdEstimate() { return formatDate(this.created?.estimatedDelivery); }

    handleField(event) {
        this[event.target.dataset.field] = event.target.value;
        this.quote = undefined;
    }

    handleService(event) {
        this.serviceType = event.target.value;
        this.quote = undefined;
    }

    clearQuote() {
        this.quote = undefined;
    }

    toNumber(value) {
        return value === '' || value === null ? null : Number(value);
    }

    async handleQuote() {
        if (!this.reportValidity()) {
            return;
        }
        await this.call(async () => {
            this.quote = await getQuote({
                serviceType: this.serviceType,
                weightKg: this.toNumber(this.weightKg),
                declaredValue: this.toNumber(this.declaredValue),
                pickupDate: this.pickupDate || null
            });
        });
    }

    async handleConfirm(event) {
        event.preventDefault();
        if (!this.quote || !this.reportValidity()) {
            return;
        }
        await this.call(async () => {
            this.created = await createShipment({
                pickupAddress: this.pickupAddress,
                pickupCity: this.pickupCity,
                pickupPostalCode: this.pickupPostalCode,
                pickupDate: this.pickupDate,
                recipientName: this.recipientName,
                recipientAddress: this.recipientAddress,
                recipientCity: this.recipientCity,
                recipientPostalCode: this.recipientPostalCode,
                recipientPhone: this.recipientPhone,
                recipientEmail: this.recipientEmail,
                serviceType: this.serviceType,
                weightKg: this.toNumber(this.weightKg),
                packageDescription: this.packageDescription,
                declaredValue: this.toNumber(this.declaredValue),
                customerReference: this.customerReference,
                deliveryInstructions: this.deliveryInstructions
            });
        });
    }

    reportValidity() {
        const controls = [...this.template.querySelectorAll('input, textarea')];
        const valid = controls.every((control) => control.checkValidity());
        if (!valid) {
            controls.find((control) => !control.checkValidity())?.reportValidity();
            this.errorText = 'Check the highlighted field.';
        }
        return valid;
    }

    startOver() {
        Object.assign(this, EMPTY);
        this.serviceType = 'Standard';
        this.quote = undefined;
        this.created = undefined;
    }

    async call(action) {
        this.errorText = undefined;
        this.loading = true;
        try {
            await action();
        } catch (error) {
            this.errorText = errorMessage(error);
        } finally {
            this.loading = false;
        }
    }
}
