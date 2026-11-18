// Covers AC-007.4 (odd/tasks/req-006-007-customer-shipments.md): the shipment
// detail passes the Sa11y rules (axe-core, WCAG A and AA base preset) loaded
// and when the shipment is not found.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcShipmentDetail from "c/rcShipmentDetail";
import getShipment from "@salesforce/apex/MyShipmentsController.getShipment";
import { CurrentPageReference } from "lightning/navigation";

jest.mock(
  "@salesforce/apex/MyShipmentsController.getShipment",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rutacargo" }),
  { virtual: true }
);

const DETAIL = {
  trackingNumber: "RC000001001",
  requestDate: "2026-11-18 09:15",
  status: "In transit",
  serviceType: "Standard",
  price: 180,
  estimatedDelivery: "2026-11-27",
  lastUpdate: "2026-11-19 12:30",
  lastLocation: "Querétaro hub",
  pickupAddress: "Av. Insurgentes Sur 1602",
  pickupCity: "Ciudad de México",
  pickupPostalCode: "03940",
  pickupDate: "2026-11-20",
  recipientName: "Laura Méndez",
  destinationCity: "Puebla",
  destinationPostalCode: "72000",
  weightKg: 2.5,
  packageDescription: "Box of documents",
  declaredValue: 1000,
  customerReference: null
};

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function render(tracking) {
  const element = createElement("c-rc-shipment-detail", {
    is: RcShipmentDetail
  });
  document.body.appendChild(element);
  CurrentPageReference.emit({
    type: "comm__namedPage",
    attributes: { name: "Shipment_Detail" },
    state: { tracking }
  });
  await flushPromises();
  return element;
}

describe("c-rc-shipment-detail accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    getShipment.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-007.4: the loaded detail has no Sa11y violations", async () => {
    getShipment.mockResolvedValue(DETAIL);
    const element = await render("RC000001001");

    expect(element.shadowRoot.querySelectorAll("dl").length).toBe(4);
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: the not-found answer has no Sa11y violations", async () => {
    getShipment.mockRejectedValue({ body: { message: "Shipment not found." } });
    const element = await render("RC000001061");

    expect(
      element.shadowRoot.querySelector('[data-id="error"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });
});
