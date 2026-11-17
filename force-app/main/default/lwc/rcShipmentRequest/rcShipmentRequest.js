import { LightningElement } from "lwc";
import getPickupWindow from "@salesforce/apex/CustomerShipmentController.getPickupWindow";
import getQuote from "@salesforce/apex/CustomerShipmentController.getQuote";
import createShipment from "@salesforce/apex/CustomerShipmentController.createShipment";
import {
  formatCurrency,
  formatDate,
  reduceErrors,
  sitePath,
  validateInputs
} from "c/rcUtils";

const EMPTY_FORM = {
  pickupAddress: "",
  pickupCity: "",
  pickupPostalCode: "",
  pickupDate: undefined,
  recipientName: "",
  recipientAddress: "",
  destinationCity: "",
  destinationPostalCode: "",
  recipientPhone: "",
  recipientEmail: "",
  deliveryInstructions: "",
  serviceType: "Standard",
  weightKg: undefined,
  declaredValue: undefined,
  packageDescription: "",
  customerReference: ""
};

/**
 * REQ-006 — the price shown before confirming comes from the server (BR-08) and is
 * recalculated again when the shipment is created.
 */
export default class RcShipmentRequest extends LightningElement {
  form = { ...EMPTY_FORM };
  pickupWindow = {};
  quote;
  created;
  errorMessage;
  isBusy = false;

  postalPattern = "[0-9]{5}";
  phonePattern = "\\+?[0-9 ()\\-]{10,20}";
  myShipmentsUrl = sitePath("/my-shipments");

  serviceOptions = [
    { label: "Standard · 5 business days", value: "Standard" },
    { label: "Express · 2 business days", value: "Express" }
  ];

  async connectedCallback() {
    try {
      this.pickupWindow = await getPickupWindow();
    } catch (error) {
      this.errorMessage = reduceErrors(error);
    }
  }

  get serviceLabel() {
    return this.form.serviceType;
  }
  get quoteBaseLabel() {
    return formatCurrency(this.quote?.price?.basePrice);
  }
  get quoteWeightLabel() {
    return formatCurrency(this.quote?.price?.weightCharge);
  }
  get quoteInsuranceLabel() {
    return formatCurrency(this.quote?.price?.insurance);
  }
  get quoteTotalLabel() {
    return formatCurrency(this.quote?.price?.total);
  }
  get quoteEstimatedLabel() {
    return formatDate(this.quote?.estimatedDelivery);
  }
  get createdPriceLabel() {
    return formatCurrency(this.created?.price);
  }
  get createdEstimatedLabel() {
    return formatDate(this.created?.estimatedDelivery);
  }
  get pickupDateLabel() {
    return formatDate(this.form.pickupDate);
  }
  get createdDetailUrl() {
    return sitePath(
      `/shipment?tracking=${encodeURIComponent(this.created?.trackingNumber || "")}`
    );
  }

  handleChange(event) {
    this.form = { ...this.form, [event.target.name]: event.detail.value };
    // Any change invalidates the price shown.
    this.quote = undefined;
  }

  clearQuote() {
    this.quote = undefined;
  }

  handleNew() {
    this.form = { ...EMPTY_FORM };
    this.created = undefined;
    this.quote = undefined;
  }

  buildRequest() {
    const f = this.form;
    return {
      ...f,
      weightKg:
        f.weightKg === undefined || f.weightKg === ""
          ? null
          : Number(f.weightKg),
      declaredValue:
        f.declaredValue === undefined || f.declaredValue === ""
          ? null
          : Number(f.declaredValue)
    };
  }

  validatePickupDate() {
    const input = this.template.querySelector(".pickup-date");
    const value = this.form.pickupDate;
    let message = "";
    if (value) {
      const day = new Date(`${value}T12:00:00Z`).getUTCDay();
      if (day === 0 || day === 6) {
        message = "Choose a business day (Monday to Friday).";
      }
    }
    input.setCustomValidity(message);
  }

  async handleQuote(event) {
    event.preventDefault();
    this.validatePickupDate();
    if (!validateInputs(this.template)) {
      return;
    }
    await this.run(async () => {
      this.quote = await getQuote({ request: this.buildRequest() });
    });
  }

  async handleConfirm() {
    await this.run(async () => {
      this.created = await createShipment({ request: this.buildRequest() });
      this.quote = undefined;
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }

  async run(action) {
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isBusy = false;
    }
  }
}
