import { LightningElement } from "lwc";
import getQuote from "@salesforce/apex/ShipmentRequestController.getQuote";
import submitRequest from "@salesforce/apex/ShipmentRequestController.submitRequest";
import BASE_PATH from "@salesforce/community/basePath";

// The server's rules (ShipmentRequestController, ShipmentRequestRules and the
// Shipment__c field lengths): the client mirrors them so a customer sees every
// field error at once; the server checks everything again (AC-006.1, AC-006.4).
const MAX_LENGTH = {
  pickupAddress: 1000,
  pickupCity: 80,
  pickupPostalCode: 10,
  recipientName: 120,
  recipientAddress: 1000,
  recipientCity: 80,
  recipientPostalCode: 10,
  recipientPhone: 40,
  recipientEmail: 80,
  packageDescription: 255,
  customerReference: 50,
  deliveryInstructions: 1000
};
const SERVICE_TYPES = ["Standard", "Express"];
const MAX_WEIGHT_KG = 30;
const MAX_DECLARED_VALUE = 50000;
// Digits with at most 2 decimals: no sign, so a negative value is refused.
const AMOUNT_FORMAT = /^\d+(\.\d{1,2})?$/;
const EMAIL_FORMAT =
  /^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/;
const DATE_FORMAT = /^\d{4}-\d{2}-\d{2}$/;

const TEXT_FIELDS = [
  "pickupAddress",
  "pickupCity",
  "pickupPostalCode",
  "recipientName",
  "recipientAddress",
  "recipientCity",
  "recipientPostalCode",
  "recipientPhone",
  "recipientEmail",
  "packageDescription",
  "customerReference",
  "deliveryInstructions"
];
const OPTIONAL_FIELDS = ["customerReference", "deliveryInstructions"];
const QUOTE_FIELDS = ["serviceType", "weightKg", "declaredValue"];
// Every field, in the order of the form and of the server's field names.
const FIELDS = [
  "pickupAddress",
  "pickupCity",
  "pickupPostalCode",
  "pickupDate",
  "recipientName",
  "recipientAddress",
  "recipientCity",
  "recipientPostalCode",
  "recipientPhone",
  "recipientEmail",
  "serviceType",
  "weightKg",
  "packageDescription",
  "declaredValue",
  "customerReference",
  "deliveryInstructions"
];

const MESSAGES = {
  pickupAddress: "Enter the pickup address (up to 1000 characters).",
  pickupCity: "Enter the pickup city (up to 80 characters).",
  pickupPostalCode: "Enter the pickup postal code (up to 10 characters).",
  recipientName: "Enter the recipient's name (up to 120 characters).",
  recipientAddress: "Enter the recipient's address (up to 1000 characters).",
  recipientCity: "Enter the destination city (up to 80 characters).",
  recipientPostalCode:
    "Enter the destination postal code (up to 10 characters).",
  recipientPhone: "Enter the recipient's phone (up to 40 characters).",
  recipientEmail: "Enter a valid recipient email (up to 80 characters).",
  serviceType: "Choose Standard or Express.",
  weightKg:
    "Enter a weight greater than 0 and up to 30 kg, with at most 2 decimals.",
  packageDescription: "Describe the package (up to 255 characters).",
  declaredValue:
    "Enter a declared value from 0 to 50,000 MXN, with at most 2 decimals.",
  customerReference: "The order reference holds up to 50 characters.",
  deliveryInstructions: "The delivery instructions hold up to 1000 characters."
};
const MESSAGE_PICKUP_NO_WINDOW =
  "Choose a business day (Monday to Friday) in the pickup window of the quote.";
const MESSAGE_FIELD_ERRORS = "Check the marked fields.";
const MESSAGE_QUOTE_FIRST = "Get a quote before you confirm.";
const MESSAGE_GENERIC =
  "We could not process your request. Please try again later.";
// The closed list of whole messages ShipmentRequestController returns; any
// other text (platform or exception text) is never shown.
const KNOWN_SERVER_MESSAGES = new Set([
  "This service is available only to signed-in customers.",
  "Your request could not be saved. Check the fields and try again."
]);
// The server names the invalid fields after this prefix, separated by ", ".
const SERVER_FIELDS_PREFIX = "Check these fields: ";

const AMOUNT_FORMATTER = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});

/** The amount as "1,870.00 MXN", or "" when there is none. */
function formatAmount(value) {
  return value === null || value === undefined || value === ""
    ? ""
    : `${AMOUNT_FORMATTER.format(Number(value))} MXN`;
}

function fits(value, maxLength, required) {
  const trimmed = value.trim();
  if (trimmed === "") {
    return !required;
  }
  return trimmed.length <= maxLength;
}

function isAmount(value, min, max, minIsExclusive) {
  const trimmed = value.trim();
  if (!AMOUNT_FORMAT.test(trimmed)) {
    return false;
  }
  const amount = Number(trimmed);
  return (minIsExclusive ? amount > min : amount >= min) && amount <= max;
}

/** A real calendar date "YYYY-MM-DD" that falls Monday to Friday. */
function isBusinessDay(value) {
  if (!DATE_FORMAT.test(value)) {
    return false;
  }
  const day = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(day.getTime()) || day.toISOString().slice(0, 10) !== value) {
    return false;
  }
  const weekday = day.getUTCDay();
  return weekday >= 1 && weekday <= 5;
}

/** The errors of the three quote fields (AC-006.2, AC-006.4). */
function validateQuoteFields(values) {
  const errors = {};
  if (!SERVICE_TYPES.includes(values.serviceType)) {
    errors.serviceType = MESSAGES.serviceType;
  }
  if (!isAmount(values.weightKg, 0, MAX_WEIGHT_KG, true)) {
    errors.weightKg = MESSAGES.weightKg;
  }
  if (!isAmount(values.declaredValue, 0, MAX_DECLARED_VALUE, false)) {
    errors.declaredValue = MESSAGES.declaredValue;
  }
  return errors;
}

/**
 * Shipment request of a logged-in customer (odd/tasks/
 * req-006-007-customer-shipments.md, S5; REQ-006): the AC-006.1 fields, a
 * live quote from ShipmentRequestController.getQuote (the price and the
 * pickup window) shown before the confirm button is enabled, and, after
 * ShipmentRequestController.submitRequest, the confirmation with the tracking
 * number, the price, the estimate and the access code. The access code lives
 * only in this component while the confirmation is shown (A1, G5): it is
 * never stored, logged or put in a URL, and a new request removes it. Every
 * value is rendered as text, and only the server's known messages are shown.
 */
export default class RcRequestShipment extends LightningElement {
  errors = {};
  formError = "";
  quote = null;
  confirmation = null;
  isQuoting = false;
  isSubmitting = false;
  focusConfirmation = false;
  myShipmentsUrl = `${BASE_PATH}/my-shipments`;

  get invalid() {
    return Object.fromEntries(
      FIELDS.map((name) => [name, String(Boolean(this.errors[name]))])
    );
  }

  get hasQuote() {
    return this.quote !== null;
  }

  get quotePrice() {
    return this.quote ? formatAmount(this.quote.price) : "";
  }

  get pickupWindowText() {
    return this.quote
      ? `Pickup dates: business days from ${this.quote.earliestPickupDate} to ${this.quote.latestPickupDate}.`
      : "";
  }

  get pickupMin() {
    return this.quote ? this.quote.earliestPickupDate : null;
  }

  get pickupMax() {
    return this.quote ? this.quote.latestPickupDate : null;
  }

  get pickupDateMessage() {
    return this.quote
      ? `Choose a business day (Monday to Friday) from ${this.quote.earliestPickupDate} to ${this.quote.latestPickupDate}.`
      : MESSAGE_PICKUP_NO_WINDOW;
  }

  // AC-006.2: confirm only after a quote is shown, and never twice.
  get isConfirmDisabled() {
    return !this.hasQuote || this.isSubmitting;
  }

  get quoteLabel() {
    return this.isQuoting ? "Getting the quote..." : "Get quote";
  }

  get submitLabel() {
    return this.isSubmitting ? "Sending your request..." : "Confirm request";
  }

  get confirmedPrice() {
    return this.confirmation ? formatAmount(this.confirmation.price) : "";
  }

  get detailUrl() {
    return this.confirmation
      ? `${BASE_PATH}/shipment-detail?tracking=${encodeURIComponent(
          this.confirmation.trackingNumber
        )}`
      : "";
  }

  // WCAG 2.4.3: the confirmation replaces the form, so focus moves to its
  // heading once, where reading continues.
  renderedCallback() {
    if (!this.focusConfirmation) {
      return;
    }
    const heading = this.template.querySelector(
      '[data-id="confirmation-title"]'
    );
    if (heading) {
      this.focusConfirmation = false;
      heading.focus();
    }
  }

  disconnectedCallback() {
    // A1: the access code leaves with the confirmation.
    this.confirmation = null;
  }

  readValues() {
    const values = {};
    FIELDS.forEach((name) => {
      const input = this.template.querySelector(`[data-field="${name}"]`);
      values[name] = input && input.value ? String(input.value) : "";
    });
    return values;
  }

  // AC-006.2: a quote holds only for the values it was computed from.
  handleQuoteFieldChange() {
    if (this.quote !== null) {
      this.quote = null;
    }
  }

  handleQuote() {
    if (this.isQuoting) {
      return;
    }
    const values = this.readValues();
    this.formError = "";
    this.quote = null;
    const quoteErrors = validateQuoteFields(values);
    this.errors = { ...this.withoutQuoteErrors(), ...quoteErrors };
    if (Object.keys(quoteErrors).length > 0) {
      return;
    }
    this.isQuoting = true;
    getQuote({
      serviceType: values.serviceType,
      weightKg: Number(values.weightKg.trim()),
      declaredValue: Number(values.declaredValue.trim())
    })
      .then((result) => {
        this.quote = {
          price: result.price,
          earliestPickupDate: result.earliestPickupDate,
          latestPickupDate: result.latestPickupDate
        };
      })
      .catch((error) => this.showServerError(error))
      .finally(() => {
        this.isQuoting = false;
      });
  }

  withoutQuoteErrors() {
    const rest = { ...this.errors };
    QUOTE_FIELDS.forEach((name) => delete rest[name]);
    return rest;
  }

  validate(values) {
    const errors = validateQuoteFields(values);
    TEXT_FIELDS.forEach((name) => {
      const required = !OPTIONAL_FIELDS.includes(name);
      if (!fits(values[name], MAX_LENGTH[name], required)) {
        errors[name] = MESSAGES[name];
      }
    });
    if (
      !errors.recipientEmail &&
      !EMAIL_FORMAT.test(values.recipientEmail.trim())
    ) {
      errors.recipientEmail = MESSAGES.recipientEmail;
    }
    const pickupDate = values.pickupDate.trim();
    if (
      !this.quote ||
      !isBusinessDay(pickupDate) ||
      pickupDate < this.quote.earliestPickupDate ||
      pickupDate > this.quote.latestPickupDate
    ) {
      errors.pickupDate = this.pickupDateMessage;
    }
    return errors;
  }

  handleSubmit(event) {
    event.preventDefault();
    if (this.isSubmitting) {
      return;
    }
    this.formError = "";
    if (!this.hasQuote) {
      this.formError = MESSAGE_QUOTE_FIRST;
      return;
    }
    const values = this.readValues();
    this.errors = this.validate(values);
    if (Object.keys(this.errors).length > 0) {
      this.formError = MESSAGE_FIELD_ERRORS;
      return;
    }
    this.isSubmitting = true;
    submitRequest({ request: this.toRequest(values) })
      .then((result) => {
        this.confirmation = {
          trackingNumber: result.trackingNumber,
          price: result.price,
          estimatedDelivery: result.estimatedDelivery,
          accessCode: result.accessCode
        };
        this.focusConfirmation = true;
      })
      .catch((error) => this.showServerError(error))
      .finally(() => {
        this.isSubmitting = false;
      });
  }

  toRequest(values) {
    const request = {};
    FIELDS.forEach((name) => {
      const trimmed = values[name].trim();
      request[name] = trimmed === "" ? null : trimmed;
    });
    request.weightKg = Number(request.weightKg);
    request.declaredValue = Number(request.declaredValue);
    return request;
  }

  // Marks the fields the server names with the client's messages; shows a
  // known whole message as is; anything else becomes the generic text.
  showServerError(error) {
    const message =
      error && error.body && typeof error.body.message === "string"
        ? error.body.message
        : "";
    if (message.startsWith(SERVER_FIELDS_PREFIX)) {
      const named = message
        .slice(SERVER_FIELDS_PREFIX.length)
        .split(",")
        .map((name) => name.trim())
        .filter((name) => FIELDS.includes(name));
      if (named.length > 0) {
        const errors = {};
        named.forEach((name) => {
          errors[name] =
            name === "pickupDate" ? this.pickupDateMessage : MESSAGES[name];
        });
        this.errors = errors;
        this.formError = MESSAGE_FIELD_ERRORS;
        return;
      }
    }
    this.formError = KNOWN_SERVER_MESSAGES.has(message)
      ? message
      : MESSAGE_GENERIC;
  }

  handleNewRequest() {
    this.confirmation = null;
    this.quote = null;
    this.errors = {};
    this.formError = "";
  }
}
