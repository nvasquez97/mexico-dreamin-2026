import { LightningElement } from "lwc";
import search from "@salesforce/apex/PublicTrackingController.search";

// The server's rule (PublicTrackingController, AC-001.1): at most 10 values
// after trim, dropping empties and case-insensitive de-duplication.
const MAX_VALUES = 10;
const CAP_ERROR = "Enter up to 10 values.";
const EMPTY_ERROR = "Enter at least one value.";
const GENERIC_ERROR = "We could not complete the search. Please try again.";
// Only these two server messages are shown as sent; any other failure shape
// shows the generic text, so no exception detail reaches the visitor (X7).
const KNOWN_SERVER_MESSAGES = new Set([CAP_ERROR, GENERIC_ERROR]);
const NOT_AVAILABLE = "Not available";

const MODE_OPTIONS = [
  { label: "Tracking number", value: "TRACKING_NUMBER" },
  { label: "Order reference", value: "REFERENCE" }
];
const SORT_STATUS = "STATUS";
const SORT_ESTIMATED_DELIVERY = "ESTIMATED_DELIVERY";
const SORT_OPTIONS = [
  { label: "Status", value: SORT_STATUS },
  { label: "Estimated delivery", value: SORT_ESTIMATED_DELIVERY }
];
// Status__c picklist order: the shipment lifecycle (C3), not the alphabet.
const STATUS_ORDER = [
  "Requested",
  "Picked up",
  "In transit",
  "Out for delivery",
  "Delivered",
  "Exception"
];

/**
 * Splits the typed text on commas and line breaks, trims every entry, drops
 * empties and keeps the first spelling of values equal ignoring case.
 */
function normalize(rawText) {
  const seen = new Set();
  const values = [];
  (rawText || "").split(/[,\r\n]+/).forEach((entry) => {
    const value = entry.trim();
    const key = value.toUpperCase();
    if (value && !seen.has(key)) {
      seen.add(key);
      values.push(value);
    }
  });
  return values;
}

function statusRank(status) {
  const rank = STATUS_ORDER.indexOf(status);
  return rank === -1 ? STATUS_ORDER.length : rank;
}

function compareStatus(a, b) {
  return statusRank(a.status) - statusRank(b.status);
}

// ISO yyyy-MM-dd strings sort as dates; an empty date goes last.
function compareEstimatedDelivery(a, b) {
  if (!a.estimatedDelivery || !b.estimatedDelivery) {
    return (a.estimatedDelivery ? 0 : 1) - (b.estimatedDelivery ? 0 : 1);
  }
  if (a.estimatedDelivery === b.estimatedDelivery) {
    return 0;
  }
  return a.estimatedDelivery < b.estimatedDelivery ? -1 : 1;
}

function textOf(value) {
  return typeof value === "string" && value !== "" ? value : NOT_AVAILABLE;
}

// Keeps only the seven public fields (BR-01), as text, with a unique key.
function toCard(result, index) {
  const source = result && typeof result === "object" ? result : {};
  const estimatedDelivery =
    typeof source.estimatedDelivery === "string"
      ? source.estimatedDelivery
      : "";
  return {
    key: `card-${index}`,
    trackingNumber: textOf(source.trackingNumber),
    status: textOf(source.status),
    originCity: textOf(source.originCity),
    destinationCity: textOf(source.destinationCity),
    lastLocation: textOf(source.lastLocation),
    lastUpdate: textOf(source.lastUpdate),
    estimatedDelivery,
    estimatedDeliveryText: textOf(estimatedDelivery),
    titleId: `rc-tracking-card-${index}`
  };
}

function isValidResponse(response) {
  return (
    response !== null &&
    typeof response === "object" &&
    Array.isArray(response.results) &&
    Array.isArray(response.notFound)
  );
}

function messageFor(error) {
  const message = error && error.body ? error.body.message : undefined;
  return KNOWN_SERVER_MESSAGES.has(message) ? message : GENERIC_ERROR;
}

/**
 * Public shipment tracking for visitors without login: up to 10 tracking
 * numbers or order references, searched through
 * PublicTrackingController.search (imperative: the method is not cacheable).
 * Every value, typed or returned, is rendered as text only.
 */
export default class RcTracking extends LightningElement {
  modeOptions = MODE_OPTIONS;
  sortOptions = SORT_OPTIONS;
  mode = MODE_OPTIONS[0].value;
  sortBy = SORT_STATUS;
  rawValues = "";
  cards = [];
  notFound = [];
  truncated = false;
  errorMessage;
  isLoading = false;
  hasSearched = false;

  get sortedCards() {
    const comparator =
      this.sortBy === SORT_ESTIMATED_DELIVERY
        ? compareEstimatedDelivery
        : compareStatus;
    return [...this.cards].sort(comparator);
  }

  get hasCards() {
    return this.cards.length > 0;
  }

  get hasNotFound() {
    return this.notFound.length > 0;
  }

  get notFoundItems() {
    return this.notFound.map((value, index) => ({
      key: `not-found-${index}`,
      value
    }));
  }

  get summary() {
    if (!this.hasSearched || this.errorMessage || this.isLoading) {
      return "";
    }
    const count = this.cards.length;
    return count === 1 ? "1 shipment found." : `${count} shipments found.`;
  }

  get searchLabel() {
    return this.isLoading ? "Searching..." : "Search";
  }

  handleModeChange(event) {
    this.mode = event.detail.value;
  }

  handleValuesChange(event) {
    this.rawValues = event.detail.value;
  }

  handleSortChange(event) {
    this.sortBy = event.detail.value;
  }

  handleSearch() {
    const values = normalize(this.rawValues);
    this.clearResults();
    if (values.length === 0) {
      this.errorMessage = EMPTY_ERROR;
      return;
    }
    if (values.length > MAX_VALUES) {
      this.errorMessage = CAP_ERROR;
      return;
    }
    this.isLoading = true;
    search({ mode: this.mode, values })
      .then((response) => {
        if (!isValidResponse(response)) {
          this.errorMessage = GENERIC_ERROR;
          return;
        }
        this.cards = response.results.map(toCard);
        this.notFound = response.notFound.map((value) => String(value));
        this.truncated = response.truncated === true;
        this.hasSearched = true;
      })
      .catch((error) => {
        this.errorMessage = messageFor(error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  clearResults() {
    this.cards = [];
    this.notFound = [];
    this.truncated = false;
    this.errorMessage = undefined;
    this.hasSearched = false;
  }
}
