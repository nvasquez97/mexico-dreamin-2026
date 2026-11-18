// Covers AC-007.4 (odd/tasks/req-006-007-customer-shipments.md): the request
// form passes the Sa11y rules (axe-core, WCAG A and AA base preset) empty,
// with an error under every field, with a quote shown, with a server error,
// and on the confirmation with the access code.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcRequestShipment from "c/rcRequestShipment";
import getQuote from "@salesforce/apex/ShipmentRequestController.getQuote";
import submitRequest from "@salesforce/apex/ShipmentRequestController.submitRequest";

jest.mock(
  "@salesforce/apex/ShipmentRequestController.getQuote",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ShipmentRequestController.submitRequest",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rutacargo" }),
  { virtual: true }
);

const VALID = {
  pickupAddress: "Av. Insurgentes Sur 1602",
  pickupCity: "Ciudad de México",
  pickupPostalCode: "03940",
  pickupDate: "2026-11-24",
  recipientName: "Laura Méndez",
  recipientAddress: "Calle Hidalgo 45",
  recipientCity: "Puebla",
  recipientPostalCode: "72000",
  recipientPhone: "222-555-0134",
  recipientEmail: "laura.mendez@example.com",
  serviceType: "Standard",
  weightKg: "2.5",
  packageDescription: "Box of documents",
  declaredValue: "1000"
};
const QUOTE = {
  price: 180,
  earliestPickupDate: "2026-11-20",
  latestPickupDate: "2026-12-04"
};

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function render(values) {
  const element = createElement("c-rc-request-shipment", {
    is: RcRequestShipment
  });
  document.body.appendChild(element);
  await flushPromises();
  if (values) {
    Object.entries(values).forEach(([name, value]) => {
      const input = element.shadowRoot.querySelector(`[data-field="${name}"]`);
      input.value = value;
      input.dispatchEvent(new CustomEvent("input"));
    });
    await flushPromises();
  }
  return element;
}

async function clickQuote(element) {
  element.shadowRoot.querySelector('button[data-id="quote"]').click();
  await flushPromises();
}

async function submit(element) {
  element.shadowRoot
    .querySelector('form[data-id="form"]')
    .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
  await flushPromises();
}

describe("c-rc-request-shipment accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    getQuote.mockReset();
    submitRequest.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-007.4: the empty form has no Sa11y violations", async () => {
    const element = await render();

    await expect(element).toBeAccessible();
  });

  it("AC-007.4: the form with an error under every required field has no Sa11y violations", async () => {
    getQuote.mockResolvedValue(QUOTE);
    const element = await render({
      serviceType: "Standard",
      weightKg: "2",
      declaredValue: "10"
    });
    await clickQuote(element);
    await submit(element);

    expect(
      element.shadowRoot.querySelectorAll('[aria-invalid="true"]').length
    ).toBe(11);
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: the quote fields in error have no Sa11y violations", async () => {
    const element = await render({ weightKg: "31", declaredValue: "-1" });
    await clickQuote(element);

    expect(
      element.shadowRoot.querySelectorAll('[aria-invalid="true"]').length
    ).toBe(3);
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: the form with a quote shown has no Sa11y violations", async () => {
    getQuote.mockResolvedValue(QUOTE);
    const element = await render(VALID);
    await clickQuote(element);

    expect(
      element.shadowRoot.querySelector('[data-id="quote-price"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: a server error has no Sa11y violations", async () => {
    getQuote.mockResolvedValue(QUOTE);
    submitRequest.mockRejectedValue({
      body: {
        message:
          "Your request could not be saved. Check the fields and try again."
      }
    });
    const element = await render(VALID);
    await clickQuote(element);
    await submit(element);

    expect(
      element.shadowRoot.querySelector('[data-id="form-error"]').textContent
    ).toContain("could not be saved");
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: the confirmation with the access code has no Sa11y violations", async () => {
    getQuote.mockResolvedValue(QUOTE);
    submitRequest.mockResolvedValue({
      trackingNumber: "RC000001234",
      price: 180,
      estimatedDelivery: "2026-12-01",
      accessCode: "K7M2Q9X4B6TP"
    });
    const element = await render(VALID);
    await clickQuote(element);
    await submit(element);

    expect(
      element.shadowRoot.querySelector('[data-id="confirmation"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });
});
