import { LightningElement, api } from "lwc";
import getDeliveryDetails from "@salesforce/apex/RecipientDeliveryController.getDeliveryDetails";
import downloadProofOfDelivery from "@salesforce/apex/RecipientDeliveryController.downloadProofOfDelivery";
import rescheduleDelivery from "@salesforce/apex/RecipientDeliveryController.rescheduleDelivery";
import {
  formatDate,
  formatDateTime,
  reduceErrors,
  statusClass
} from "c/rcUtils";

const PROOF_ERROR =
  "We could not get the proof of delivery, please try again later";

/**
 * REQ-002 / REQ-003 — recipient view. The postal code is kept only in memory and sent with
 * every call; the server re-verifies it each time (BR-02).
 */
export default class RcDeliveryDetails extends LightningElement {
  @api trackingNumber;

  postalPattern = "[0-9]{5}";
  postalCode = "";
  details;
  errorMessage;
  successMessage;
  isBusy = false;
  showRescheduleForm = false;
  newDate;
  instructions;

  get showVerification() {
    return !this.details;
  }

  get statusCss() {
    return statusClass(this.details?.status);
  }

  get deliveryAddressLabel() {
    const d = this.details;
    return [
      d.deliveryAddress,
      [d.destinationCity, d.destinationPostalCode].filter((v) => v).join(" ")
    ]
      .filter((v) => v)
      .join("\n");
  }

  get estimatedDeliveryLabel() {
    return formatDate(this.details?.estimatedDelivery);
  }

  get deliveredAtLabel() {
    return formatDateTime(this.details?.deliveredAt);
  }

  get instructionsLabel() {
    return this.details?.deliveryInstructions || "No instructions";
  }

  get minDateLabel() {
    return formatDate(this.details?.rescheduleMinDate);
  }

  get maxDateLabel() {
    return formatDate(this.details?.rescheduleMaxDate);
  }

  get reschedulesLeftLabel() {
    const left = this.details?.reschedulesLeft ?? 0;
    return left === 1 ? "1 more time" : `${left} more times`;
  }

  handlePostalCodeChange(event) {
    this.postalCode = (event.detail.value || "").trim();
  }

  handleDateChange(event) {
    this.newDate = event.detail.value;
  }

  handleInstructionsChange(event) {
    this.instructions = event.detail.value;
  }

  toggleReschedule() {
    this.showRescheduleForm = !this.showRescheduleForm;
    this.successMessage = undefined;
    this.errorMessage = undefined;
    if (this.showRescheduleForm) {
      this.newDate = undefined;
      this.instructions = this.details.deliveryInstructions;
    }
  }

  async handleVerify(event) {
    event.preventDefault();
    const input = this.template.querySelector(".postal-code");
    if (!input.reportValidity()) {
      return;
    }
    await this.call(async () => {
      const result = await getDeliveryDetails({
        trackingNumber: this.trackingNumber,
        postalCode: this.postalCode
      });
      this.applyResult(result);
    });
  }

  async handleDownload() {
    await this.call(async () => {
      const result = await downloadProofOfDelivery({
        trackingNumber: this.trackingNumber,
        postalCode: this.postalCode
      });
      if (!result.success) {
        this.errorMessage = result.message || PROOF_ERROR;
        return;
      }
      this.saveFile(result.pdfBase64, result.fileName);
      this.successMessage = result.signedBy
        ? `Proof of delivery downloaded. Received by ${result.signedBy}.`
        : "Proof of delivery downloaded.";
    }, PROOF_ERROR);
  }

  async handleReschedule(event) {
    event.preventDefault();
    const dateInput = this.template.querySelector(".new-date");
    if (!dateInput.reportValidity()) {
      return;
    }
    await this.call(async () => {
      const result = await rescheduleDelivery({
        trackingNumber: this.trackingNumber,
        postalCode: this.postalCode,
        newDate: this.newDate,
        deliveryInstructions: this.instructions
      });
      this.applyResult(result);
      if (result.success) {
        this.showRescheduleForm = false;
        this.successMessage = result.message;
      }
    });
  }

  applyResult(result) {
    if (result && result.success) {
      this.details = result.details;
      this.errorMessage = undefined;
    } else {
      this.errorMessage =
        result?.message || "Something went wrong. Please try again.";
    }
  }

  async call(action, fallbackMessage) {
    this.isBusy = true;
    this.errorMessage = undefined;
    this.successMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = fallbackMessage || reduceErrors(error);
    } finally {
      this.isBusy = false;
    }
  }

  /** AC-002.4 — the PDF goes straight from EntregaYa to the browser; it is not stored in Salesforce. */
  saveFile(base64, fileName) {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: "application/pdf" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName || `${this.trackingNumber}-proof-of-delivery.pdf`;
    link.style.display = "none";
    this.template.querySelector(".details").appendChild(link);
    link.click();
    link.remove();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }
}
