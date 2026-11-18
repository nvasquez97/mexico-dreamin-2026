import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import getShipment from "@salesforce/apex/MyShipmentsController.getShipment";
import BASE_PATH from "@salesforce/community/basePath";

// MyShipmentsController.TRACKING_FORMAT: anything else is "not found" at once.
const TRACKING_FORMAT = /^RC\d{9}$/;
const MESSAGE_NOT_FOUND = "Shipment not found.";
const MESSAGE_GENERIC =
  "We could not load this shipment. Please try again later.";
const NOT_AVAILABLE_YET = "Not available yet";
const NOT_PROVIDED = "Not provided";
// The closed list of messages MyShipmentsController.getShipment returns.
const KNOWN_SERVER_MESSAGES = new Set([
  MESSAGE_NOT_FOUND,
  "This service is available only to signed-in customers."
]);

const DECIMAL_FORMATTER = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});

function formatNumber(value, unit) {
  return value === null || value === undefined
    ? NOT_AVAILABLE_YET
    : `${DECIMAL_FORMATTER.format(Number(value))} ${unit}`;
}

function orElse(value, fallback) {
  return value === null || value === undefined || value === ""
    ? fallback
    : value;
}

/**
 * Detail of one of the logged-in customer's shipments (odd/tasks/
 * req-006-007-customer-shipments.md, S5; REQ-007): reads the tracking number
 * from the page URL (?tracking=RC + 9 digits), asks
 * MyShipmentsController.getShipment for it and shows the AC-007.3 detail:
 * status, price, estimate, last update, the pickup data, the recipient's
 * name, destination city and postal code, and the package. The recipient's
 * address, phone, email and the delivery instructions are not part of it
 * (BR-02, G7). Another customer's, an unknown or a malformed number is the
 * one "not found" answer. Every value is rendered as text.
 */
export default class RcShipmentDetail extends LightningElement {
  detail = null;
  errorMessage = "";
  isLoading = false;
  myShipmentsUrl = `${BASE_PATH}/my-shipments`;
  requestedTracking = null;
  requestCounter = 0;

  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    const state = (pageReference && pageReference.state) || {};
    const tracking =
      typeof state.tracking === "string" ? state.tracking.trim() : "";
    if (pageReference && tracking === this.requestedTracking) {
      return;
    }
    this.requestedTracking = tracking;
    this.load(tracking);
  }

  get title() {
    return this.detail
      ? `Shipment ${this.detail.trackingNumber}`
      : "Shipment detail";
  }

  get fields() {
    const detail = this.detail;
    if (!detail) {
      return null;
    }
    return {
      trackingNumber: detail.trackingNumber,
      requestDate: detail.requestDate,
      status: detail.status,
      serviceType: detail.serviceType,
      price: formatNumber(detail.price, "MXN"),
      estimatedDelivery: orElse(detail.estimatedDelivery, NOT_AVAILABLE_YET),
      lastUpdate: orElse(detail.lastUpdate, NOT_AVAILABLE_YET),
      lastLocation: orElse(detail.lastLocation, NOT_AVAILABLE_YET),
      pickupAddress: detail.pickupAddress,
      pickupCity: detail.pickupCity,
      pickupPostalCode: detail.pickupPostalCode,
      pickupDate: detail.pickupDate,
      recipientName: detail.recipientName,
      destinationCity: detail.destinationCity,
      destinationPostalCode: detail.destinationPostalCode,
      weightKg: formatNumber(detail.weightKg, "kg"),
      packageDescription: detail.packageDescription,
      declaredValue: formatNumber(detail.declaredValue, "MXN"),
      customerReference: orElse(detail.customerReference, NOT_PROVIDED)
    };
  }

  load(tracking) {
    this.requestCounter += 1;
    const request = this.requestCounter;
    this.detail = null;
    this.errorMessage = "";
    if (!TRACKING_FORMAT.test(tracking)) {
      this.isLoading = false;
      this.errorMessage = MESSAGE_NOT_FOUND;
      return;
    }
    this.isLoading = true;
    getShipment({ trackingNumber: tracking })
      .then((detail) => {
        if (request === this.requestCounter) {
          this.detail = detail || null;
          if (!detail) {
            this.errorMessage = MESSAGE_NOT_FOUND;
          }
        }
      })
      .catch((error) => {
        if (request !== this.requestCounter) {
          return;
        }
        const message =
          error && error.body && typeof error.body.message === "string"
            ? error.body.message
            : "";
        this.errorMessage = KNOWN_SERVER_MESSAGES.has(message)
          ? message
          : MESSAGE_GENERIC;
      })
      .finally(() => {
        if (request === this.requestCounter) {
          this.isLoading = false;
        }
      });
  }
}
