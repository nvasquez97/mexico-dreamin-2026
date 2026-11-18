import { LightningElement, api } from "lwc";
import getDeliveryDetails from "@salesforce/apex/RecipientDeliveryController.getDeliveryDetails";
import rescheduleDelivery from "@salesforce/apex/RecipientDeliveryController.rescheduleDelivery";
import downloadProof from "@salesforce/apex/RecipientDeliveryController.downloadProof";

const SUCCESS = "SUCCESS";
const NOT_AVAILABLE = "Not available";
const CODE_LENGTH = 12;
const CODE_GROUP = 4;
const MAX_FILE_NAME = 100;
const MAX_INSTRUCTIONS = 1000;
const DEFAULT_FILE_NAME = "proof-of-delivery.pdf";
const PDF_SIGNATURE = "%PDF-";

const GENERIC_ERROR =
  "We could not complete your request. Please try again later.";
const PROOF_UNAVAILABLE =
  "We could not get the proof of delivery, please try again later";
const MISSING_INPUT = "Enter the destination postal code and the access code.";

// The server's texts (RecipientAccess, RecipientDeliveryController) shown as
// sent; any other text, or a thrown error, shows the generic text, so no
// exception detail reaches the recipient (X7).
const KNOWN_MESSAGES = new Set([
  "The details do not match this shipment",
  "Too many attempts. Please try again in 15 minutes.",
  "The new delivery date is outside the allowed rescheduling window.",
  "This delivery cannot be rescheduled in its current status.",
  "This delivery has already been rescheduled the maximum number of times.",
  "This delivery has no estimated date to reschedule from yet.",
  "Delivery instructions must be 1000 characters or fewer.",
  "The proof of delivery is not available for this shipment.",
  PROOF_UNAVAILABLE,
  GENERIC_ERROR
]);

function knownMessage(message, fallback = GENERIC_ERROR) {
  return KNOWN_MESSAGES.has(message) ? message : fallback;
}

function isObject(value) {
  return value !== null && typeof value === "object";
}

function textOf(value) {
  return typeof value === "string" && value !== "" ? value : NOT_AVAILABLE;
}

function isoOrNull(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? value
    : null;
}

/**
 * The typed code without separators, upper case, at most 12 characters,
 * grouped XXXX-XXXX-XXXX (the server ignores spaces and dashes and the case).
 */
function groupCode(typed) {
  const plain = String(typed || "")
    .replace(/[^0-9A-Za-z]/g, "")
    .toUpperCase()
    .slice(0, CODE_LENGTH);
  const groups = [];
  for (let start = 0; start < plain.length; start += CODE_GROUP) {
    groups.push(plain.slice(start, start + CODE_GROUP));
  }
  return groups.join("-");
}

// Keeps only the values the component shows, as text, from the eleven of
// RecipientDeliveryDetails.
function toDetails(source) {
  return {
    recipientName: textOf(source.recipientName),
    deliveryAddress: textOf(source.deliveryAddress),
    contactPhone: textOf(source.contactPhone),
    estimatedDelivery: textOf(source.estimatedDelivery),
    deliveryInstructions: textOf(source.deliveryInstructions),
    instructions:
      typeof source.deliveryInstructions === "string"
        ? source.deliveryInstructions
        : "",
    canReschedule: source.canReschedule === true,
    reschedulesLeft: Number.isInteger(source.reschedulesLeft)
      ? source.reschedulesLeft
      : 0,
    rescheduleFrom: isoOrNull(source.rescheduleFrom),
    rescheduleTo: isoOrNull(source.rescheduleTo),
    proofAvailable: source.proofAvailable === true
  };
}

/**
 * A file name safe to save: the last path segment, only letters, digits,
 * dots, dashes and underscores, no leading dot, at most 100 characters, and
 * ending in .pdf.
 */
function safeFileName(name) {
  const lastSegment = String(name || "")
    .split(/[\\/]/)
    .pop();
  let safe = lastSegment
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .replace(/^\.+/, "")
    .slice(0, MAX_FILE_NAME);
  if (!safe) {
    return DEFAULT_FILE_NAME;
  }
  if (!/\.pdf$/i.test(safe)) {
    safe = `${safe}.pdf`;
  }
  return safe;
}

// The decoded bytes of a base64 PDF, or null when it is not base64 or not a PDF.
function pdfBytes(base64) {
  if (typeof base64 !== "string" || base64 === "") {
    return null;
  }
  let binary;
  try {
    binary = atob(base64);
  } catch {
    return null;
  }
  if (!binary.startsWith(PDF_SIGNATURE)) {
    return null;
  }
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

/**
 * Delivery details for a recipient, opened from a tracking result card
 * (req-002-003 S4). The recipient enters the destination postal code and the
 * access code; every call to RecipientDeliveryController (imperative: none is
 * cacheable) re-sends the tracking number and both values, which live only in
 * this component's memory. Details render only after a SUCCESS outcome, and
 * every value is rendered as text only.
 */
export default class RcDeliveryDetails extends LightningElement {
  @api trackingNumber;

  postalCode = "";
  accessCode = "";
  details;
  errorMessage;
  isVerifying = false;

  proofError;
  signedBy;
  isDownloading = false;
  proofUrl;

  newDate = "";
  instructions = "";
  rescheduleError;
  savedDate;
  isRescheduling = false;

  disconnectedCallback() {
    this.releaseProofUrl();
    // Nothing of the recipient outlives the component.
    this.postalCode = "";
    this.accessCode = "";
    this.details = undefined;
  }

  get hasDetails() {
    return this.details !== undefined;
  }

  get showReschedule() {
    return this.hasDetails && this.details.canReschedule;
  }

  get showProof() {
    return this.hasDetails && this.details.proofAvailable;
  }

  get verifyLabel() {
    return this.isVerifying ? "Checking..." : "View details";
  }

  get instructionsMaxLength() {
    return MAX_INSTRUCTIONS;
  }

  get proofLabel() {
    return "Download proof of delivery";
  }

  get rescheduleLabel() {
    return this.isRescheduling ? "Saving..." : "Reschedule delivery";
  }

  get reschedulesLeftText() {
    return `Reschedules left: ${this.details.reschedulesLeft}`;
  }

  get signedByText() {
    return `Signed by: ${this.signedBy}`;
  }

  get savedDateText() {
    return `Your delivery is rescheduled for ${this.savedDate}.`;
  }

  get headingText() {
    return `Delivery details for ${this.trackingNumber}`;
  }

  handlePostalCodeChange(event) {
    this.postalCode = event.detail.value;
  }

  handleAccessCodeChange(event) {
    this.accessCode = groupCode(event.detail.value);
    // The input shows the grouped value even when the bound value is unchanged
    // (typing a separator after a full group); the input is this template's.
    this.refs.accessCode.value = this.accessCode;
  }

  handleNewDateChange(event) {
    this.newDate = event.detail.value || "";
  }

  handleInstructionsChange(event) {
    this.instructions = event.detail.value || "";
  }

  credentials() {
    return {
      trackingNumber: this.trackingNumber,
      postalCode: (this.postalCode || "").trim(),
      accessCode: this.accessCode
    };
  }

  handleVerify() {
    this.clearDetails();
    const request = this.credentials();
    if (!request.postalCode || !request.accessCode) {
      this.errorMessage = MISSING_INPUT;
      return;
    }
    this.isVerifying = true;
    getDeliveryDetails(request)
      .then((response) => this.applyVerification(response))
      .catch(() => {
        this.errorMessage = GENERIC_ERROR;
      })
      .finally(() => {
        this.isVerifying = false;
      });
  }

  applyVerification(response) {
    if (!isObject(response)) {
      this.errorMessage = GENERIC_ERROR;
      return;
    }
    if (response.outcome !== SUCCESS || !isObject(response.details)) {
      this.errorMessage = knownMessage(response.message);
      return;
    }
    this.showDetails(response.details);
  }

  showDetails(source) {
    this.details = toDetails(source);
    this.instructions = this.details.instructions;
    this.newDate = "";
  }

  clearDetails() {
    this.releaseProofUrl();
    this.details = undefined;
    this.errorMessage = undefined;
    this.proofError = undefined;
    this.signedBy = undefined;
    this.rescheduleError = undefined;
    this.savedDate = undefined;
    this.newDate = "";
    this.instructions = "";
  }

  handleDownloadProof() {
    this.proofError = undefined;
    this.signedBy = undefined;
    this.isDownloading = true;
    downloadProof(this.credentials())
      .then((response) => this.applyProof(response))
      .catch(() => {
        this.proofError = PROOF_UNAVAILABLE;
      })
      .finally(() => {
        this.isDownloading = false;
      });
  }

  applyProof(response) {
    if (!isObject(response)) {
      this.proofError = PROOF_UNAVAILABLE;
      return;
    }
    if (response.outcome !== SUCCESS) {
      this.applyFailedProof(response);
      return;
    }
    const bytes = pdfBytes(response.pdfBase64);
    if (!bytes) {
      this.proofError = PROOF_UNAVAILABLE;
      return;
    }
    this.saveProof(bytes, safeFileName(response.fileName));
    this.signedBy = textOf(response.signedBy);
  }

  applyFailedProof(response) {
    if (response.outcome === "NOT_MATCHED" || response.outcome === "LOCKED") {
      this.clearDetails();
      this.errorMessage = knownMessage(response.message);
      return;
    }
    this.proofError = knownMessage(response.message, PROOF_UNAVAILABLE);
  }

  // Saves the PDF through a Blob URL (never a data URL and never a page
  // navigation); the URL is released on the next download or on disconnect.
  saveProof(bytes, fileName) {
    this.releaseProofUrl();
    const blob = new Blob([bytes], { type: "application/pdf" });
    this.proofUrl = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = this.proofUrl;
    anchor.download = fileName;
    anchor.rel = "noopener";
    anchor.click();
  }

  releaseProofUrl() {
    if (this.proofUrl) {
      URL.revokeObjectURL(this.proofUrl);
      this.proofUrl = undefined;
    }
  }

  handleReschedule() {
    this.rescheduleError = undefined;
    this.savedDate = undefined;
    const { rescheduleFrom, rescheduleTo } = this.details;
    const date = this.newDate;
    if (!date || date < rescheduleFrom || date > rescheduleTo) {
      this.rescheduleError = `Choose a date between ${rescheduleFrom} and ${rescheduleTo}.`;
      return;
    }
    this.isRescheduling = true;
    rescheduleDelivery({
      ...this.credentials(),
      newDate: date,
      instructions: this.instructions
    })
      .then((response) => this.applyReschedule(response))
      .catch(() => {
        this.rescheduleError = GENERIC_ERROR;
      })
      .finally(() => {
        this.isRescheduling = false;
      });
  }

  applyReschedule(response) {
    if (!isObject(response)) {
      this.rescheduleError = GENERIC_ERROR;
      return;
    }
    if (response.outcome === SUCCESS && isObject(response.details)) {
      this.showDetails(response.details);
      this.savedDate = this.details.estimatedDelivery;
      return;
    }
    if (response.outcome === "NOT_MATCHED" || response.outcome === "LOCKED") {
      this.clearDetails();
      this.errorMessage = knownMessage(response.message);
      return;
    }
    if (isObject(response.details)) {
      // The refreshed details, keeping what the recipient typed.
      const { newDate, instructions } = this;
      this.showDetails(response.details);
      this.newDate = newDate;
      this.instructions = instructions;
    }
    this.rescheduleError = knownMessage(response.message);
  }
}
