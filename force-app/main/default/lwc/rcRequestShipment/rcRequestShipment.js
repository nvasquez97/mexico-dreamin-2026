import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import quoteShipment from '@salesforce/apex/RutaCargoController.quoteShipment';
import requestShipment from '@salesforce/apex/RutaCargoController.requestShipment';
import { errorMessage, formatMoney, formatDate, todayInMexico, addDays } from 'c/rcUtil';

const EMPTY = {
    pickupAddress: '', pickupCity: '', pickupPostalCode: '', pickupDate: null, recipientName: '', recipientAddress: '',
    recipientCity: '', recipientPostalCode: '', recipientPhone: '', recipientEmail: '', serviceType: 'Standard', weightKg: null,
    packageDescription: '', declaredValue: null, customerReference: '', deliveryInstructions: ''
};

export default class RcRequestShipment extends LightningElement {
    form = { ...EMPTY };
    message;
    isBusy = false;
    created;
    quote;
    quoteTimer;

    get minPickup() { return addDays(todayInMexico(), 1); }
    get maxPickup() { return addDays(todayInMexico(), 15); }
    get mineUrl() { return `${basePath}/my-shipments`; }
    get quoteLabel() { return this.quote === undefined ? '' : formatMoney(this.quote); }
    get createdPrice() { return formatMoney(this.created.price); }
    get createdEstimate() { return formatDate(this.created.estimatedDelivery); }

    handleField(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'weightKg' || field === 'declaredValue') value = value === '' ? null : Number(value);
        this.form = { ...this.form, [field]: value };
        if (field === 'serviceType' || field === 'weightKg' || field === 'declaredValue') this.refreshQuote();
    }

    refreshQuote() {
        const { serviceType, weightKg, declaredValue } = this.form;
        this.quote = undefined;
        if (weightKg === null || declaredValue === null) return;
        // The price always comes from the server (BR-08); the page never computes it.
        quoteShipment({ serviceType, weightKg, declaredValue })
            .then((result) => {
                this.quote = result.success ? result.price : undefined;
                if (!result.success) this.message = result.message;
            })
            .catch((e) => { this.message = errorMessage(e); });
    }

    async handleSubmit(event) {
        event.preventDefault();
        this.isBusy = true;
        this.message = undefined;
        try {
            const result = await requestShipment({ ...this.form });
            if (result.success) {
                this.created = result;
            } else {
                this.message = result.message;
            }
        } catch (e) {
            this.message = errorMessage(e);
        } finally {
            this.isBusy = false;
        }
    }

    handleAnother() {
        this.form = { ...EMPTY };
        this.created = undefined;
        this.quote = undefined;
    }
}
