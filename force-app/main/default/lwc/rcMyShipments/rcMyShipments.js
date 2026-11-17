import { LightningElement } from "lwc";
import getMyShipments from "@salesforce/apex/CustomerShipmentController.getMyShipments";
import {
  STATUSES,
  formatCurrency,
  formatDateTime,
  reduceErrors,
  sitePath,
  statusClass
} from "c/rcUtils";

const SEARCH_DELAY_MS = 350;

/** REQ-007 — the customer's shipments, most recent first, with status filter and search. */
export default class RcMyShipments extends LightningElement {
  status = "";
  searchTerm = "";
  rows = [];
  totalCount = 0;
  hasMore = false;
  isLoading = false;
  loaded = false;
  errorMessage;
  searchTimer;
  requestSequence = 0;

  requestUrl = sitePath("/request-shipment");

  statusOptions = [
    { label: "All statuses", value: "" },
    ...STATUSES.map((s) => ({ label: s, value: s }))
  ];

  connectedCallback() {
    this.load(true);
  }

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return (
      this.loaded &&
      !this.isLoading &&
      !this.errorMessage &&
      this.rows.length === 0
    );
  }

  get countLabel() {
    if (!this.loaded) {
      return "";
    }
    return `Showing ${this.rows.length} of ${this.totalCount} shipment${this.totalCount === 1 ? "" : "s"}`;
  }

  handleStatusChange(event) {
    this.status = event.detail.value;
    this.load(true);
  }

  handleSearchChange(event) {
    this.searchTerm = event.detail.value;
    clearTimeout(this.searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.load(true), SEARCH_DELAY_MS);
  }

  loadMore() {
    this.load(false);
  }

  async load(reset) {
    const sequence = ++this.requestSequence;
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      const page = await getMyShipments({
        status: this.status,
        searchTerm: this.searchTerm,
        offsetRows: reset ? 0 : this.rows.length
      });
      if (sequence !== this.requestSequence) {
        return; // a newer search is in flight
      }
      const mapped = page.rows.map((row) => ({
        ...row,
        statusClass: statusClass(row.status),
        requestDateLabel: formatDateTime(row.requestDate),
        priceLabel: formatCurrency(row.price),
        detailUrl: sitePath(
          `/shipment?tracking=${encodeURIComponent(row.trackingNumber)}`
        )
      }));
      this.rows = reset ? mapped : [...this.rows, ...mapped];
      this.hasMore = page.hasMore;
      this.totalCount = page.totalCount;
      this.loaded = true;
    } catch (error) {
      if (sequence === this.requestSequence) {
        this.errorMessage = reduceErrors(error);
      }
    } finally {
      if (sequence === this.requestSequence) {
        this.isLoading = false;
      }
    }
  }
}
