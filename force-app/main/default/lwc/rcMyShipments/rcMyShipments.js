import { LightningElement } from "lwc";
import listShipments from "@salesforce/apex/MyShipmentsController.listShipments";
import BASE_PATH from "@salesforce/community/basePath";

// The closed list of the Status__c picklist (the server refuses any other,
// P8); the Jest test compares it with the field's metadata.
const STATUSES = [
  "Requested",
  "Picked up",
  "In transit",
  "Out for delivery",
  "Delivered",
  "Exception"
];
// MyShipmentsController.MAX_SEARCH_LENGTH.
const MAX_SEARCH_LENGTH = 50;

const MESSAGE_SEARCH = "Search with up to 50 characters.";
const MESSAGE_GENERIC =
  "We could not load your shipments. Please try again later.";
const MESSAGE_EMPTY = "You have no shipments yet.";
const MESSAGE_NO_MATCH = "No shipments match your filter.";
const MESSAGE_LOADING = "Loading your shipments...";
// The closed list of messages MyShipmentsController returns; any other text
// (platform or exception text) is never shown.
const KNOWN_SERVER_MESSAGES = new Set([
  "This service is available only to signed-in customers.",
  "Check the status filter and the search text."
]);

const AMOUNT_FORMATTER = new Intl.NumberFormat("en-US", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
});

function formatAmount(value) {
  return value === null || value === undefined
    ? ""
    : `${AMOUNT_FORMATTER.format(Number(value))} MXN`;
}

/**
 * "My shipments" of a logged-in customer (odd/tasks/
 * req-006-007-customer-shipments.md, S5; REQ-007): the shipments
 * MyShipmentsController.listShipments returns (the customer's own, most
 * recent first, at most 200), as cards with the tracking number (a link to
 * its detail), request date, recipient, destination city, status, service
 * type and price; a status filter from the closed picklist and a search by
 * tracking number, recipient or reference. Imperative calls (the controller
 * is not cacheable: a customer must see a shipment they just requested).
 * Every value is rendered as text, and only the server's known messages are
 * shown.
 */
export default class RcMyShipments extends LightningElement {
  rows = [];
  status = "";
  searchTerm = "";
  searchError = "";
  errorMessage = "";
  isLoading = false;
  hasLoaded = false;
  requestUrl = `${BASE_PATH}/request-shipment`;
  requestCounter = 0;

  statusOptions = STATUSES.map((value) => ({ value, label: value }));

  connectedCallback() {
    this.load();
  }

  get cards() {
    return this.rows.map((row) => ({
      key: row.trackingNumber,
      trackingNumber: row.trackingNumber,
      requestDate: row.requestDate,
      recipientName: row.recipientName,
      destinationCity: row.destinationCity,
      status: row.status,
      serviceType: row.serviceType,
      price: formatAmount(row.price),
      detailUrl: `${BASE_PATH}/shipment-detail?tracking=${encodeURIComponent(
        row.trackingNumber
      )}`
    }));
  }

  get hasCards() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return this.hasLoaded && !this.errorMessage && this.rows.length === 0;
  }

  get emptyMessage() {
    return this.status || this.searchTerm ? MESSAGE_NO_MATCH : MESSAGE_EMPTY;
  }

  get summary() {
    if (this.isLoading) {
      return MESSAGE_LOADING;
    }
    if (!this.hasLoaded || this.errorMessage) {
      return "";
    }
    const count = this.rows.length;
    return `${count} ${count === 1 ? "shipment" : "shipments"}`;
  }

  get searchInvalid() {
    return String(Boolean(this.searchError));
  }

  handleStatusChange(event) {
    this.status = event.target.value || "";
    this.load();
  }

  handleSearch(event) {
    event.preventDefault();
    const input = this.template.querySelector('[data-id="search"]');
    const term = input && input.value ? String(input.value).trim() : "";
    if (term.length > MAX_SEARCH_LENGTH) {
      this.searchError = MESSAGE_SEARCH;
      return;
    }
    this.searchError = "";
    this.searchTerm = term;
    this.load();
  }

  load() {
    this.requestCounter += 1;
    const request = this.requestCounter;
    this.isLoading = true;
    this.errorMessage = "";
    listShipments({ status: this.status, searchTerm: this.searchTerm })
      .then((rows) => {
        if (request !== this.requestCounter) {
          return;
        }
        this.rows = Array.isArray(rows) ? rows : [];
        this.hasLoaded = true;
      })
      .catch((error) => {
        if (request !== this.requestCounter) {
          return;
        }
        const message =
          error && error.body && typeof error.body.message === "string"
            ? error.body.message
            : "";
        this.rows = [];
        this.hasLoaded = true;
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
