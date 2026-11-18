// Covers odd/tasks/req-006-007-customer-shipments.md, AC-007.4 (UI, detail
// part): the detail page reads the tracking number from its URL
// (?tracking=RC + 9 digits), asks MyShipmentsController.getShipment for it,
// and shows the AC-007.3 detail as text: the entered data except the
// recipient's address, phone, email and the delivery instructions (BR-02,
// G7), plus the price, the status, the estimate and the last update; any
// other or malformed number is the one "not found" answer; one column below
// 768 px.
import { createElement } from "lwc";
import RcShipmentDetail from "c/rcShipmentDetail";
import getShipment from "@salesforce/apex/MyShipmentsController.getShipment";
import { CurrentPageReference } from "lightning/navigation";

const fs = require("fs");
const path = require("path");

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

// The server's messages (MyShipmentsController, T2 8a322bd).
const NOT_FOUND_MESSAGE = "Shipment not found.";
const NOT_AVAILABLE_MESSAGE =
  "This service is available only to signed-in customers.";
const GENERIC_MESSAGE =
  "We could not load this shipment. Please try again later.";

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
  customerReference: "PO-7781"
};

const OTHER = {
  ...DETAIL,
  trackingNumber: "RC000001061",
  status: "Requested",
  serviceType: "Express",
  price: 1870,
  estimatedDelivery: "2026-11-24",
  lastUpdate: null,
  lastLocation: null,
  weightKg: 30,
  declaredValue: 50000,
  customerReference: null
};

const EXPECTED = {
  trackingNumber: "RC000001001",
  requestDate: "2026-11-18 09:15",
  status: "In transit",
  serviceType: "Standard",
  price: "180.00 MXN",
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
  weightKg: "2.50 kg",
  packageDescription: "Box of documents",
  declaredValue: "1,000.00 MXN",
  customerReference: "PO-7781"
};

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function render(state) {
  const element = createElement("c-rc-shipment-detail", {
    is: RcShipmentDetail
  });
  document.body.appendChild(element);
  CurrentPageReference.emit({
    type: "comm__namedPage",
    attributes: { name: "Shipment_Detail" },
    state
  });
  await flushPromises();
  return element;
}

function query(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

function text(node) {
  return node ? node.textContent.replace(/\s+/g, " ").trim() : null;
}

function values(element) {
  return Object.fromEntries(
    Array.from(element.shadowRoot.querySelectorAll("dd[data-field]")).map(
      (dd) => [dd.dataset.field, text(dd)]
    )
  );
}

function serverError(message) {
  return { body: { message }, status: 500 };
}

describe("c-rc-shipment-detail", () => {
  beforeEach(() => {
    getShipment.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-007.4: asks the server for the tracking number of the URL", async () => {
    getShipment.mockResolvedValue(DETAIL);

    await render({ tracking: "RC000001001" });

    expect(getShipment).toHaveBeenCalledTimes(1);
    expect(getShipment).toHaveBeenCalledWith({ trackingNumber: "RC000001001" });
  });

  it("AC-007.4: shows every AC-007.3 field as text", async () => {
    getShipment.mockResolvedValue(DETAIL);

    const element = await render({ tracking: "RC000001001" });

    expect(values(element)).toEqual(EXPECTED);
    expect(text(query(element, "h2"))).toBe("Shipment RC000001001");
  });

  it("AC-007.4: a second shipment shows its own values, and missing ones as not available or not provided", async () => {
    getShipment.mockResolvedValue(OTHER);

    const element = await render({ tracking: "RC000001061" });

    expect(getShipment).toHaveBeenCalledWith({ trackingNumber: "RC000001061" });
    const shown = values(element);
    expect(shown.trackingNumber).toBe("RC000001061");
    expect(shown.status).toBe("Requested");
    expect(shown.serviceType).toBe("Express");
    expect(shown.price).toBe("1,870.00 MXN");
    expect(shown.weightKg).toBe("30.00 kg");
    expect(shown.declaredValue).toBe("50,000.00 MXN");
    expect(shown.lastUpdate).toBe("Not available yet");
    expect(shown.lastLocation).toBe("Not available yet");
    expect(shown.customerReference).toBe("Not provided");
  });

  it("AC-007.4 (G7): shows no recipient address, phone, email or delivery instructions", async () => {
    getShipment.mockResolvedValue({
      ...DETAIL,
      recipientAddress: "Calle Hidalgo 45",
      recipientPhone: "222-555-0134",
      recipientEmail: "laura.mendez@example.com",
      deliveryInstructions: "Ring twice"
    });

    const element = await render({ tracking: "RC000001001" });

    const page = element.shadowRoot.textContent;
    [
      "Calle Hidalgo 45",
      "222-555-0134",
      "laura.mendez@example.com",
      "Ring twice"
    ].forEach((value) => expect(page).not.toContain(value));
    expect(Object.keys(values(element))).toEqual(Object.keys(EXPECTED));
  });

  it.each([
    [{ tracking: "abc" }],
    [{ tracking: "RC00000100" }],
    [{ tracking: "RC0000010011" }],
    [{}],
    [undefined]
  ])(
    "AC-007.4: a missing or malformed tracking number (%p) is not found, without asking the server",
    async (state) => {
      const element = await render(state);

      expect(getShipment).not.toHaveBeenCalled();
      expect(text(query(element, '[data-id="error"]'))).toBe(NOT_FOUND_MESSAGE);
      expect(query(element, "dl")).toBeNull();
    }
  );

  it("AC-007.4: the server's not found (another customer's or an unknown number) is shown as such", async () => {
    getShipment.mockRejectedValue(serverError(NOT_FOUND_MESSAGE));

    const element = await render({ tracking: "RC000001061" });

    expect(text(query(element, '[data-id="error"]'))).toBe(NOT_FOUND_MESSAGE);
    expect(query(element, "dl")).toBeNull();
  });

  it("AC-007.4: the server's sign-in message is shown as text", async () => {
    getShipment.mockRejectedValue(serverError(NOT_AVAILABLE_MESSAGE));

    const element = await render({ tracking: "RC000001001" });

    expect(text(query(element, '[data-id="error"]'))).toBe(
      NOT_AVAILABLE_MESSAGE
    );
  });

  it("AC-007.4: an unknown server text is never shown", async () => {
    getShipment.mockRejectedValue(
      serverError("System.QueryException: Internal_Notes__c")
    );

    const element = await render({ tracking: "RC000001001" });

    expect(text(query(element, '[data-id="error"]'))).toBe(GENERIC_MESSAGE);
    expect(element.shadowRoot.textContent).not.toContain("QueryException");
  });

  it("AC-007.4: links back to My shipments", async () => {
    getShipment.mockResolvedValue(DETAIL);

    const element = await render({ tracking: "RC000001001" });

    expect(query(element, 'a[data-id="back-link"]').getAttribute("href")).toBe(
      "/rutacargo/my-shipments"
    );
  });

  it("AC-007.4: server values are rendered as text, never as markup", async () => {
    getShipment.mockResolvedValue({
      ...DETAIL,
      packageDescription: '<img src="x" onerror="alert(1)">'
    });

    const element = await render({ tracking: "RC000001001" });

    expect(element.shadowRoot.querySelector("img")).toBeNull();
    expect(values(element).packageDescription).toBe(
      '<img src="x" onerror="alert(1)">'
    );
  });

  describe("AC-007.4: source rules", () => {
    const dir = path.join(__dirname, "..");

    it('AC-007.4: the bundle has no lwc:inner-html, innerHTML or lwc:dom="manual", and never logs or stores a value', () => {
      const sources = fs
        .readdirSync(dir)
        .filter((name) => /\.(js|html)$/.test(name))
        .map((name) => fs.readFileSync(path.join(dir, name), "utf8"));

      expect(sources.length).toBe(2);
      sources.forEach((source) => {
        expect(source).not.toMatch(
          /lwc:inner-html|innerHTML|outerHTML|lwc:dom/
        );
        expect(source).not.toMatch(
          /console\.|localStorage|sessionStorage|document\.cookie|indexedDB/
        );
      });
    });

    it("AC-007.4: the detail is one column below 768 px (no multi-column grid outside a min-width: 48em query)", () => {
      const css = fs.readFileSync(
        path.join(dir, "rcShipmentDetail.css"),
        "utf8"
      );
      const outsideWideQuery = css.replace(
        /@media \(min-width: 48em\) \{[\s\S]*?\n\}/g,
        ""
      );

      expect(css).toMatch(/@media \(min-width: 48em\)/);
      expect(outsideWideQuery).not.toMatch(
        /grid-template-columns:\s*(repeat\(\s*[2-9]|[^;]*fr[^;]*fr)/
      );
      expect(outsideWideQuery).not.toMatch(/flex-direction:\s*row/);
    });

    it("AC-007.4: brand: labels are Montserrat Medium (500) and links are underlined through the DXP hook", () => {
      const css = fs.readFileSync(
        path.join(dir, "rcShipmentDetail.css"),
        "utf8"
      );

      expect(css).toMatch(/\.rc-detail__label\s*\{[^}]*font-weight:\s*500/);
      expect(css).toMatch(
        /\.rc-detail\s*\{[^}]*--dxp-c-link-text-decoration:\s*underline/
      );
      expect(css).not.toMatch(/#ff3636|#ffc91d/i);
    });
  });
});
