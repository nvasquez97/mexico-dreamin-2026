// Covers AC-002.8 (odd/tasks/req-002-003-recipient-delivery.md): the delivery
// details component is used by anonymous recipients, so its rendered DOM must
// pass the Sa11y accessibility rules (axe-core, WCAG A and AA base preset)
// empty, with an error, with the details, the proof and the reschedule form,
// and after a reschedule.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcDeliveryDetails from "c/rcDeliveryDetails";
import getDeliveryDetails from "@salesforce/apex/RecipientDeliveryController.getDeliveryDetails";
import rescheduleDelivery from "@salesforce/apex/RecipientDeliveryController.rescheduleDelivery";
import downloadProof from "@salesforce/apex/RecipientDeliveryController.downloadProof";

jest.mock(
  "@salesforce/apex/RecipientDeliveryController.getDeliveryDetails",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RecipientDeliveryController.rescheduleDelivery",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RecipientDeliveryController.downloadProof",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

function details(overrides) {
  return {
    recipientName: "Ana López",
    deliveryAddress: "Av. Juárez 120, 06050 Ciudad de México",
    contactPhone: "+52 55 1234 5678",
    estimatedDelivery: "2026-11-20",
    deliveryInstructions: "Ring twice",
    status: "In transit",
    canReschedule: true,
    reschedulesLeft: 2,
    rescheduleFrom: "2026-11-18",
    rescheduleTo: "2026-11-27",
    proofAvailable: true,
    ...overrides
  };
}

async function change(element, selector, value) {
  const input = element.shadowRoot.querySelector(selector);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await Promise.resolve();
}

async function renderAndVerify(answer) {
  const element = createElement("c-rc-delivery-details", {
    is: RcDeliveryDetails
  });
  element.trackingNumber = "RC000001001";
  document.body.appendChild(element);
  await Promise.resolve();
  if (answer !== undefined) {
    getDeliveryDetails.mockResolvedValue(answer);
    await change(element, '[data-id="postal-code"]', "06050");
    await change(element, '[data-id="access-code"]', "ABCD2345EFGH");
    element.shadowRoot.querySelector('[data-id="verify"]').click();
    await flushPromises();
  }
  return element;
}

describe("c-rc-delivery-details accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    getDeliveryDetails.mockReset();
    rescheduleDelivery.mockReset();
    downloadProof.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-002.8: the empty verification form has no Sa11y (axe WCAG A/AA) violations", async () => {
    const element = await renderAndVerify();

    await expect(element).toBeAccessible();
  });

  it("AC-002.8: the not-matched error has no Sa11y violations", async () => {
    const element = await renderAndVerify({
      outcome: "NOT_MATCHED",
      message: "The details do not match this shipment",
      details: null
    });

    expect(
      element.shadowRoot.querySelector('[data-id="error"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });

  it("AC-002.8: the details, the proof button and the reschedule form have no Sa11y violations", async () => {
    const element = await renderAndVerify({
      outcome: "SUCCESS",
      message: null,
      details: details()
    });

    expect(
      element.shadowRoot.querySelector('[data-id="reschedule-form"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="download-proof"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });

  it("AC-002.8: the saved date and the proof error have no Sa11y violations", async () => {
    downloadProof.mockResolvedValue({
      outcome: "UNAVAILABLE",
      message: "We could not get the proof of delivery, please try again later",
      proofAvailable: true
    });
    rescheduleDelivery.mockResolvedValue({
      outcome: "SUCCESS",
      message: null,
      details: details({ estimatedDelivery: "2026-11-25", reschedulesLeft: 1 })
    });
    const element = await renderAndVerify({
      outcome: "SUCCESS",
      message: null,
      details: details()
    });
    await change(element, '[data-id="new-date"]', "2026-11-25");
    element.shadowRoot.querySelector('[data-id="reschedule"]').click();
    await flushPromises();
    element.shadowRoot.querySelector('[data-id="download-proof"]').click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector('[data-id="reschedule-success"]')
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="proof-error"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });
});
