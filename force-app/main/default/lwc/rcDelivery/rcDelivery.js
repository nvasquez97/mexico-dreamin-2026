import { LightningElement, api } from 'lwc';
import getDeliveryDetails from '@salesforce/apex/RutaCargoController.getDeliveryDetails';
import getProofOfDelivery from '@salesforce/apex/RutaCargoController.getProofOfDelivery';
import rescheduleDelivery from '@salesforce/apex/RutaCargoController.rescheduleDelivery';
import { formatDate, errorMessage } from 'c/rcUtil';

export default class RcDelivery extends LightningElement {
    @api trackingNumber;
    postalCode = '';
    details;
    outcome;
    message;
    messageIsError = false;
    isBusy = false;
    newDate;
    instructions = '';

    get showVerify() { return !this.details; }
    get isLocked() { return this.outcome === 'LOCKED'; }
    get showMismatch() { return this.outcome === 'MISMATCH'; }
    get estimatedLabel() { return formatDate(this.details.estimatedDelivery); }
    get earliestLabel() { return formatDate(this.details.earliestRescheduleDate); }
    get latestLabel() { return formatDate(this.details.latestRescheduleDate); }
    get instructionsLabel() { return this.details.deliveryInstructions || 'None'; }
    get isNotReschedulable() { return this.details && !this.details.canReschedule && this.details.status !== 'Delivered'; }
    get messageClass() { return 'rc-msg ' + (this.messageIsError ? 'rc-msg--error' : 'rc-msg--ok'); }

    handlePostal(event) { this.postalCode = event.target.value.trim(); }
    handleNewDate(event) { this.newDate = event.target.value; }
    handleInstructions(event) { this.instructions = event.target.value; }

    show(text, isError) {
        this.message = text;
        this.messageIsError = !!isError;
    }

    applyDetails(result) {
        this.outcome = result.outcome;
        if (result.outcome === 'OK' || result.outcome === 'REJECTED') {
            this.details = { ...result, outcome: 'OK' };
            this.instructions = result.deliveryInstructions || '';
            this.newDate = result.estimatedDelivery;
        }
    }

    async handleVerify(event) {
        event.preventDefault();
        this.isBusy = true;
        this.message = undefined;
        try {
            const result = await getDeliveryDetails({ trackingNumber: this.trackingNumber, postalCode: this.postalCode });
            this.outcome = result.outcome;
            if (result.outcome === 'OK') {
                this.applyDetails(result);
            } else {
                this.show(result.message, true);
            }
        } catch (e) {
            this.show(errorMessage(e), true);
        } finally {
            this.isBusy = false;
        }
    }

    async handleProof() {
        this.isBusy = true;
        this.message = undefined;
        try {
            const proof = await getProofOfDelivery({ trackingNumber: this.trackingNumber, postalCode: this.postalCode });
            if (proof.outcome !== 'OK') {
                this.show(proof.message, true);
                return;
            }
            // The PDF only passes through the browser; it is never stored in Salesforce.
            const bytes = Uint8Array.from(atob(proof.pdfBase64), (c) => c.charCodeAt(0));
            const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
            const link = document.createElement('a');
            link.href = url;
            link.download = proof.fileName;
            link.click();
            URL.revokeObjectURL(url);
        } catch (e) {
            this.show(errorMessage(e, 'We could not get the proof of delivery, please try again later'), true);
        } finally {
            this.isBusy = false;
        }
    }

    async handleReschedule(event) {
        event.preventDefault();
        this.isBusy = true;
        this.message = undefined;
        try {
            const result = await rescheduleDelivery({
                trackingNumber: this.trackingNumber,
                postalCode: this.postalCode,
                newDate: this.newDate,
                instructions: this.instructions
            });
            if (result.outcome === 'OK') {
                this.applyDetails(result);
                this.show('Done. Your new delivery date is ' + formatDate(result.estimatedDelivery) + '.', false);
            } else if (result.outcome === 'REJECTED') {
                this.applyDetails(result);
                this.show(result.message, true);
            } else {
                this.details = undefined;
                this.outcome = result.outcome;
                this.show(result.message, true);
            }
        } catch (e) {
            this.show(errorMessage(e), true);
        } finally {
            this.isBusy = false;
        }
    }
}
