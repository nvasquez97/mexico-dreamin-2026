// Covers AC-007.4 (odd/tasks/req-006-007-customer-shipments.md): "My
// shipments" passes the Sa11y rules (axe-core, WCAG A and AA base preset)
// with cards, empty, with a search error and with a server error.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcMyShipments from "c/rcMyShipments";
import listShipments from "@salesforce/apex/MyShipmentsController.listShipments";

jest.mock(
  "@salesforce/apex/MyShipmentsController.listShipments",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rutacargo" }),
  { virtual: true }
);

const ROWS = [
  {
    trackingNumber: "RC000001060",
    requestDate: "2026-11-18 09:15",
    recipientName: "Laura Méndez",
    destinationCity: "Puebla",
    status: "Requested",
    serviceType: "Express",
    price: 310
  },
  {
    trackingNumber: "RC000001059",
    requestDate: "2026-11-17 16:40",
    recipientName: "Jorge Ruiz",
    destinationCity: "Monterrey",
    status: "In transit",
    serviceType: "Standard",
    price: 1870
  }
];

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function render() {
  const element = createElement("c-rc-my-shipments", { is: RcMyShipments });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

describe("c-rc-my-shipments accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    listShipments.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-007.4: the list with cards has no Sa11y violations", async () => {
    listShipments.mockResolvedValue(ROWS);
    const element = await render();

    expect(
      element.shadowRoot.querySelectorAll('li[data-id="card"]').length
    ).toBe(2);
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: the empty list has no Sa11y violations", async () => {
    listShipments.mockResolvedValue([]);
    const element = await render();

    expect(
      element.shadowRoot.querySelector('[data-id="empty"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: a search error has no Sa11y violations", async () => {
    listShipments.mockResolvedValue(ROWS);
    const element = await render();
    element.shadowRoot.querySelector('input[data-id="search"]').value =
      "a".repeat(51);
    element.shadowRoot
      .querySelector('form[data-id="filters"]')
      .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
    await flushPromises();

    expect(
      element.shadowRoot
        .querySelector('input[data-id="search"]')
        .getAttribute("aria-invalid")
    ).toBe("true");
    await expect(element).toBeAccessible();
  });

  it("AC-007.4: a server error has no Sa11y violations", async () => {
    listShipments.mockRejectedValue({
      body: { message: "Check the status filter and the search text." }
    });
    const element = await render();

    expect(
      element.shadowRoot.querySelector('[data-id="error"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });
});
