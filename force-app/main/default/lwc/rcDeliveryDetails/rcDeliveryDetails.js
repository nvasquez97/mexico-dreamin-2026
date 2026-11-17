import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getDeliveryDetails from '@salesforce/apex/PublicTrackingController.getDeliveryDetails';
import getProofOfDelivery from '@salesforce/apex/PublicTrackingController.getProofOfDelivery';
import reschedule from '@salesforce/apex/PublicTrackingController.reschedule';
import { formatDate, statusDotClass, errorMessage, downloadBase64 } from 'c/rcUtils';

export default class RcDeliveryDetails extends NavigationMixin(LightningElement) {
    trackingNumber = '';
    postalCode = '';
    details;
    error;
    success;
    loading = false;
    loadingProof = false;
    saving = false;
    newDate = '';
    instructions = '';

    // /delivery?tn=RC000001042 (from a tracking result or the QR code) pre-fills the tracking number
    @wire(CurrentPageReference)
    pageRef(ref) {
        const tn = ref && ref.state && ref.state.tn;
        if (tn && !this.trackingNumber) {
            this.trackingNumber = tn;
        }
    }

    get dotClass() {
        return statusDotClass(this.details.status);
    }
    get estimatedText() {
        return formatDate(this.details.estimatedDelivery);
    }
    get instructionsText() {
        return this.details.deliveryInstructions || '—';
    }
    get minDate() {
        return this.details.minRescheduleDate;
    }
    get maxDate() {
        return this.details.maxRescheduleDate;
    }
    get maxText() {
        return formatDate(this.details.maxRescheduleDate);
    }

    handleTn(event) {
        this.trackingNumber = event.target.value;
    }
    handleCp(event) {
        this.postalCode = event.target.value;
    }
    handleNewDate(event) {
        this.newDate = event.target.value;
    }
    handleInstructions(event) {
        this.instructions = event.target.value;
    }

    async handleVerify(event) {
        event.preventDefault();
        this.error = undefined;
        this.success = undefined;
        this.loading = true;
        try {
            const result = await getDeliveryDetails({ trackingNumber: this.trackingNumber, postalCode: this.postalCode });
            if (result.error) {
                this.error = result.error; // e.g. "The details do not match this shipment" (AC-002.3)
            } else {
                this.show(result);
            }
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    show(result) {
        this.details = result;
        this.instructions = result.deliveryInstructions || '';
        this.newDate = '';
    }

    async handleProof() {
        this.error = undefined;
        this.loadingProof = true;
        try {
            const proof = await getProofOfDelivery({ trackingNumber: this.trackingNumber, postalCode: this.postalCode });
            if (proof.error) {
                this.error = proof.error;
            } else {
                downloadBase64(proof.pdfBase64, proof.fileName);
            }
        } catch (e) {
            // AC-002.5: "We could not get the proof of delivery, please try again later"
            this.error = errorMessage(e);
        } finally {
            this.loadingProof = false;
        }
    }

    async handleReschedule(event) {
        event.preventDefault();
        this.error = undefined;
        this.success = undefined;
        this.saving = true;
        try {
            const result = await reschedule({
                trackingNumber: this.trackingNumber,
                postalCode: this.postalCode,
                newDate: this.newDate,
                instructions: this.instructions
            });
            if (result.error) {
                this.error = result.error;
            } else {
                this.show(result);
                this.success = 'Done! Your new delivery date is ' + formatDate(result.estimatedDelivery) + '.'; // AC-003.5
            }
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.saving = false;
        }
    }

    handleBack() {
        this.details = undefined;
        this.error = undefined;
        this.success = undefined;
        this.postalCode = '';
    }
}
