import { LightningElement, api } from 'lwc';
import getDeliveryDetails from '@salesforce/apex/DeliveryController.getDeliveryDetails';
import downloadProof from '@salesforce/apex/DeliveryController.downloadProof';
import reschedule from '@salesforce/apex/DeliveryController.reschedule';
import { formatDate, errorMessage } from 'c/rcFormat';

/**
 * Recipient panel inside a tracking result: postal code check (AC-002.1),
 * delivery details (AC-002.2), proof of delivery download (AC-002.4) and
 * rescheduling (REQ-003). Every server call re-sends tracking number and
 * postal code; the server verifies them each time.
 */
export default class RcDeliveryPanel extends LightningElement {
    @api trackingNumber;
    postalCode = '';
    details;
    newDate;
    instructions = '';
    errorText;
    successText;
    proofHref;
    proofFileName;
    loading = false;

    get showVerify() { return !this.details; }
    get estimatedText() { return formatDate(this.details?.estimatedDelivery); }
    get instructionsText() { return this.details?.deliveryInstructions || 'None'; }
    get minText() { return formatDate(this.details?.minRescheduleDate); }
    get maxText() { return formatDate(this.details?.maxRescheduleDate); }

    handlePostal(event) { this.postalCode = event.target.value; }
    handleNewDate(event) { this.newDate = event.target.value; }
    handleInstructions(event) { this.instructions = event.target.value; }

    async handleVerify(event) {
        event.preventDefault();
        await this.call(async () => {
            const response = await getDeliveryDetails({ trackingNumber: this.trackingNumber, postalCode: this.postalCode });
            if (response.success) {
                this.applyDetails(response.details);
            } else {
                this.errorText = response.message;
            }
        });
    }

    async handleDownload() {
        await this.call(async () => {
            const response = await downloadProof({ trackingNumber: this.trackingNumber, postalCode: this.postalCode });
            if (!response.success) {
                this.errorText = response.message;
                return;
            }
            // The PDF stays in the browser only; it is not stored in Salesforce (AC-002.4).
            const bytes = Uint8Array.from(atob(response.pdfBase64), (c) => c.charCodeAt(0));
            if (this.proofHref) {
                URL.revokeObjectURL(this.proofHref);
            }
            this.proofFileName = response.fileName;
            this.proofHref = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
            await Promise.resolve();
            this.template.querySelector('.rc-proof-link')?.click();
            this.successText = 'Your proof of delivery was downloaded.';
        });
    }

    async handleReschedule(event) {
        event.preventDefault();
        if (!this.newDate) {
            this.errorText = 'Choose a new delivery date.';
            return;
        }
        await this.call(async () => {
            const response = await reschedule({
                trackingNumber: this.trackingNumber,
                postalCode: this.postalCode,
                newDate: this.newDate,
                instructions: this.instructions
            });
            if (response.success) {
                this.applyDetails(response.details);
                this.successText = `Done. Your delivery is now scheduled for ${formatDate(response.details.estimatedDelivery)}.`;
            } else {
                this.errorText = response.message;
            }
        });
    }

    disconnectedCallback() {
        if (this.proofHref) {
            URL.revokeObjectURL(this.proofHref);
        }
    }

    applyDetails(details) {
        this.details = details;
        this.instructions = details.deliveryInstructions || '';
        this.newDate = undefined;
    }

    async call(action) {
        this.errorText = undefined;
        this.successText = undefined;
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
