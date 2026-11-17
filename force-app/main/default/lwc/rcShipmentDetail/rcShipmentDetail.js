import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import getMyShipment from "@salesforce/apex/CustomerShipmentController.getMyShipment";
import {
  formatCurrency,
  formatDate,
  formatDateTime,
  reduceErrors,
  sitePath,
  statusClass
} from "c/rcUtils";

/** AC-007.3 — detail of one of the customer's shipments (?tracking=RC...). */
export default class RcShipmentDetail extends LightningElement {
  trackingNumber;
  shipment;
  errorMessage;
  isLoading = false;
  myShipmentsUrl = sitePath("/my-shipments");

  @wire(CurrentPageReference)
  handlePageReference(pageRef) {
    const tracking = pageRef?.state?.tracking;
    if (tracking && tracking !== this.trackingNumber) {
      this.trackingNumber = tracking;
      this.load();
    } else if (!tracking && pageRef) {
      this.errorMessage = "Choose a shipment from My shipments.";
    }
  }

  get statusCss() {
    return statusClass(this.shipment?.status);
  }

  get labels() {
    const s = this.shipment || {};
    return {
      requestDate: formatDateTime(s.requestDate),
      price: formatCurrency(s.price),
      estimatedDelivery: formatDate(s.estimatedDelivery),
      lastLocation: s.lastLocation || "—",
      lastUpdate: formatDateTime(s.lastUpdate),
      deliveredAt: formatDateTime(s.deliveredAt),
      reference: s.customerReference || "—",
      pickupCity: [s.pickupCity, s.pickupPostalCode]
        .filter((v) => v)
        .join(" · "),
      pickupDate: formatDate(s.pickupDate),
      destinationCity: [s.destinationCity, s.destinationPostalCode]
        .filter((v) => v)
        .join(" · "),
      instructions: s.deliveryInstructions || "—",
      weight:
        s.weightKg !== undefined && s.weightKg !== null
          ? `${s.weightKg} kg`
          : "—",
      declaredValue: formatCurrency(s.declaredValue)
    };
  }

  async load() {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      this.shipment = await getMyShipment({
        trackingNumber: this.trackingNumber
      });
    } catch (error) {
      this.shipment = undefined;
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isLoading = false;
    }
  }
}
