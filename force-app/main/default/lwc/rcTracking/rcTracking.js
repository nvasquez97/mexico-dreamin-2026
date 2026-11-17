import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import track from "@salesforce/apex/PublicTrackingController.track";
import LOGO from "@salesforce/resourceUrl/RutaCargo_Logo_Color";
import {
  formatDate,
  formatDateTime,
  reduceErrors,
  statusClass
} from "c/rcUtils";

const MAX_VALUES = 10;

/**
 * REQ-001 — public tracking. A QR code on the label can open the page with
 * ?tracking=RC000001042 (or ?reference=...) to search right away.
 */
export default class RcTracking extends LightningElement {
  logoUrl = LOGO;
  searchBy = "TRACKING";
  searchText = "";
  sortBy = "status";
  results = [];
  expandedKey;
  errorMessage;
  isLoading = false;
  searched = false;
  initialisedFromUrl = false;

  searchByOptions = [
    { label: "Tracking number", value: "TRACKING" },
    { label: "Order reference", value: "REFERENCE" }
  ];

  sortOptions = [
    { label: "Status", value: "status" },
    { label: "Estimated delivery date", value: "estimatedDelivery" }
  ];

  @wire(CurrentPageReference)
  handlePageReference(pageRef) {
    if (this.initialisedFromUrl || !pageRef || !pageRef.state) {
      return;
    }
    const { tracking, reference } = pageRef.state;
    if (tracking || reference) {
      this.initialisedFromUrl = true;
      this.searchBy = reference ? "REFERENCE" : "TRACKING";
      this.searchText = reference || tracking;
      this.runSearch();
    }
  }

  get searchLabel() {
    return this.searchBy === "TRACKING"
      ? "Tracking numbers"
      : "Order references";
  }

  get searchPlaceholder() {
    return this.searchBy === "TRACKING"
      ? "RC000001042, RC000001043"
      : "PO-2026-001";
  }

  get searchValueLabel() {
    return this.searchBy === "TRACKING" ? "Tracking number" : "Order reference";
  }

  get hasResults() {
    return this.searched && this.results.length > 0;
  }

  get resultsTitle() {
    const found = this.results.filter((r) => r.found).length;
    return `${found} of ${this.results.length} result${this.results.length === 1 ? "" : "s"} found`;
  }

  /** AC-001.4 — sort by lifecycle status or by estimated delivery (not found last). */
  get sortedResults() {
    const rows = [...this.results];
    if (this.sortBy === "estimatedDelivery") {
      rows.sort((a, b) => {
        const av = a.estimatedDelivery || "9999-12-31";
        const bv = b.estimatedDelivery || "9999-12-31";
        if (a.found !== b.found) {
          return a.found ? -1 : 1;
        }
        return av.localeCompare(bv) || a.statusOrder - b.statusOrder;
      });
    } else {
      rows.sort(
        (a, b) =>
          a.statusOrder - b.statusOrder ||
          (a.estimatedDelivery || "9999-12-31").localeCompare(
            b.estimatedDelivery || "9999-12-31"
          )
      );
    }
    return rows.map((row) => {
      const expanded = row.key === this.expandedKey;
      return {
        ...row,
        expanded,
        ariaExpanded: expanded ? "true" : "false",
        detailsButtonLabel: expanded
          ? "Hide delivery details"
          : "I am the recipient: delivery details"
      };
    });
  }

  handleSearchByChange(event) {
    this.searchBy = event.detail.value;
  }

  handleTextChange(event) {
    this.searchText = event.detail.value;
  }

  handleSortChange(event) {
    this.sortBy = event.detail.value;
  }

  toggleDetails(event) {
    const key = event.currentTarget.dataset.key;
    this.expandedKey = this.expandedKey === key ? undefined : key;
  }

  handleSearch(event) {
    event.preventDefault();
    const input = this.template.querySelector(".search-input");
    const values = (this.searchText || "")
      .split(/[,\r\n]+/)
      .map((v) => v.trim())
      .filter((v) => v);
    if (values.length === 0) {
      input.setCustomValidity("Enter at least one value.");
    } else if (values.length > MAX_VALUES) {
      input.setCustomValidity(
        `You can search up to ${MAX_VALUES} values at a time.`
      );
    } else {
      input.setCustomValidity("");
    }
    if (!input.reportValidity()) {
      return;
    }
    this.runSearch();
  }

  async runSearch() {
    this.isLoading = true;
    this.errorMessage = undefined;
    this.expandedKey = undefined;
    try {
      const data = await track({
        searchBy: this.searchBy,
        searchText: this.searchText
      });
      this.results = data.map((row) => ({
        ...row,
        statusClass: statusClass(row.status),
        lastLocationLabel: row.lastLocation || "—",
        lastUpdateLabel: formatDateTime(row.lastUpdate),
        estimatedDeliveryLabel: formatDate(row.estimatedDelivery),
        showReference: this.searchBy === "REFERENCE"
      }));
      this.searched = true;
    } catch (error) {
      this.results = [];
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isLoading = false;
    }
  }
}
