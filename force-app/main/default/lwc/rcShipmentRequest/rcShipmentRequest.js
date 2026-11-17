import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuestUser from '@salesforce/user/isGuest';
import quote from '@salesforce/apex/CustomerPortalController.quote';
import createShipment from '@salesforce/apex/CustomerPortalController.createShipment';
import { formatDate, formatMoney, errorMessage, mexicoDatePlus } from 'c/rcUtils';

const FIELDS = ['pickupAddress', 'pickupCity', 'pickupPostalCode', 'pickupDate', 'recipientName', 'recipientAddress',
    'destinationCity', 'destinationPostalCode', 'recipientPhone', 'recipientEmail', 'deliveryInstructions', 'serviceType',
    'weightKg', 'declaredValue', 'packageDescription', 'customerReference'];
// Every key starts as '' so a bound input never receives undefined (which renders as the text "undefined")
const emptyForm = () => Object.fromEntries(FIELDS.map((f) => [f, '']));

export default class RcShipmentRequest extends NavigationMixin(LightningElement) {
    isGuest = isGuestUser;
    step = 'form';
    form = emptyForm();
    price;
    created;
    error;
    busy = false;

    get minDate() {
        return mexicoDatePlus(1);
    }
    get maxDate() {
        return mexicoDatePlus(15);
    }
    get stepForm() {
        return this.step === 'form';
    }
    get stepReview() {
        return this.step === 'review';
    }
    get stepDone() {
        return this.step === 'done';
    }
    get noService() {
        return !this.form.serviceType;
    }
    get isStandard() {
        return this.form.serviceType === 'Standard';
    }
    get isExpress() {
        return this.form.serviceType === 'Express';
    }
    get priceText() {
        return formatMoney(this.price);
    }
    get pickupDateText() {
        return formatDate(this.form.pickupDate);
    }
    get createdPrice() {
        return formatMoney(this.created.price);
    }
    get createdEta() {
        return formatDate(this.created.estimatedDelivery);
    }

    handleChange(event) {
        const { name, value } = event.target;
        this.form = { ...this.form, [name]: value };
    }

    /** Monday-Friday (AC-006.3). The server checks it again. */
    isBusinessDay(iso) {
        const [y, m, d] = iso.split('-').map(Number);
        const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
        return dow >= 1 && dow <= 5;
    }

    async handleReview(event) {
        event.preventDefault();
        this.error = undefined;
        if (!this.isBusinessDay(this.form.pickupDate)) {
            this.error = 'The pickup date must be a business day (Monday to Friday).';
            return;
        }
        this.busy = true;
        try {
            this.price = await quote({
                serviceType: this.form.serviceType,
                weightKg: Number(this.form.weightKg),
                declaredValue: Number(this.form.declaredValue)
            });
            this.step = 'review';
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    handleEdit() {
        this.step = 'form';
        this.error = undefined;
    }

    async handleConfirm() {
        this.error = undefined;
        this.busy = true;
        try {
            this.created = await createShipment({ form: this.form });
            this.step = 'done';
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }

    handleAnother() {
        this.form = emptyForm();
        this.price = undefined;
        this.created = undefined;
        this.step = 'form';
    }
    goMyShipments() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'My_Shipments__c' } });
    }
    goLogin() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Login' } });
    }
    goSignup() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Register' } });
    }
}
