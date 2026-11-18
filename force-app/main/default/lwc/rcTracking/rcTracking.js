import { LightningElement } from "lwc";
import search from "@salesforce/apex/PublicTrackingController.search";

// The server's rule (PublicTrackingController, AC-001.1): at most 10 values
// after trim, dropping empties and case-insensitive de-duplication.
const MAX_VALUES = 10;
// The server lists a value longer than 50 characters as not found without
// querying it, but answers its generic error for an entry over 520 characters:
// the client lists such values as not found itself and never sends them.
const MAX_VALUE_LENGTH = 50;
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
    // A card without a tracking number offers no delivery details (S4).
    hasDetails:
      typeof source.trackingNumber === "string" && source.trackingNumber !== ""
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

function isTooLong(value) {
  return value.length > MAX_VALUE_LENGTH;
}

/**
 * The values to list under "Not found", in input order: the typed values the
 * server did not find and, as the server would, the values longer than 50
 * characters, except when the answer is truncated (a truncated answer lists
 * no value as missing). A server value that matches no typed value is kept,
 * after them.
 */
function mergeNotFound(values, serverNotFound, truncated) {
  const missing = new Set(serverNotFound.map((value) => value.toUpperCase()));
  const typed = new Set(values.map((value) => value.toUpperCase()));
  const merged = values.filter((value) => {
    if (isTooLong(value)) {
      return !truncated;
    }
    return missing.has(value.toUpperCase());
  });
  serverNotFound
    .filter((value) => !typed.has(value.toUpperCase()))
    .forEach((value) => merged.push(value));
  return merged;
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
  // The key of the card whose delivery details are open (one at a time).
  openCardKey;

  get sortedCards() {
    const comparator =
      this.sortBy === SORT_ESTIMATED_DELIVERY
        ? compareEstimatedDelivery
        : compareStatus;
    return [...this.cards].sort(comparator).map((card) => {
      const isOpen = card.key === this.openCardKey;
      return {
        ...card,
        isOpen,
        detailsExpanded: String(isOpen),
        detailsLabel: `Delivery details for ${card.trackingNumber}`
      };
    });
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

  // Opens rcDeliveryDetails inside the chosen card, on the same page (the
  // access code never goes to a URL); choosing it again closes it, and opening
  // another card closes the first, so its component and code are discarded.
  handleToggleDetails(event) {
    const key = event.currentTarget.dataset.key;
    this.openCardKey = this.openCardKey === key ? undefined : key;
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
    const sendable = values.filter((value) => !isTooLong(value));
    if (sendable.length === 0) {
      this.showResponse(values, {
        results: [],
        notFound: [],
        truncated: false
      });
      return;
    }
    this.isLoading = true;
    search({ mode: this.mode, values: sendable })
      .then((response) => {
        if (!isValidResponse(response)) {
          this.errorMessage = GENERIC_ERROR;
          return;
        }
        this.showResponse(values, response);
      })
      .catch((error) => {
        this.errorMessage = messageFor(error);
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  showResponse(values, response) {
    this.cards = response.results.map(toCard);
    this.truncated = response.truncated === true;
    this.notFound = mergeNotFound(
      values,
      response.notFound.map((value) => String(value)),
      this.truncated
    );
    this.hasSearched = true;
  }

  clearResults() {
    this.cards = [];
    this.notFound = [];
    this.truncated = false;
    this.errorMessage = undefined;
    this.hasSearched = false;
    this.openCardKey = undefined;
  }
}
