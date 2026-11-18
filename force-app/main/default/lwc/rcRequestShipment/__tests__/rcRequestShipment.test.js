// Covers odd/tasks/req-006-007-customer-shipments.md, the client parts of
// AC-006.1 (the form marks every required AC-006.1 field, shows a generic
// error per missing or too long field, sends nothing then, and shows the
// same errors when the server names invalid fields), AC-006.2 (the quote is
// shown before the confirm button is enabled; a change of service, weight or
// declared value withdraws it), AC-006.4 (weight in (0, 30] with at most 2
// decimals, declared value in [0, 50,000], rejected on the client) and
// AC-007.4 (the request states: quote, confirmation with the tracking number,
// price, estimate and the access code shown once and never stored; text-only
// rendering; one column below 768 px).
import { createElement } from "lwc";
import RcRequestShipment from "c/rcRequestShipment";
import getQuote from "@salesforce/apex/ShipmentRequestController.getQuote";
import submitRequest from "@salesforce/apex/ShipmentRequestController.submitRequest";

const fs = require("fs");
const path = require("path");

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

// The server's messages (ShipmentRequestController, T2 8a322bd / b8d954d).
const NOT_AVAILABLE_MESSAGE =
  "This service is available only to signed-in customers.";
const SAVE_FAILED_MESSAGE =
  "Your request could not be saved. Check the fields and try again.";

const MESSAGES = {
  pickupAddress: "Enter the pickup address (up to 1000 characters).",
  pickupCity: "Enter the pickup city (up to 80 characters).",
  pickupPostalCode: "Enter the pickup postal code (up to 10 characters).",
  recipientName: "Enter the recipient's name (up to 120 characters).",
  recipientAddress: "Enter the recipient's address (up to 1000 characters).",
  recipientCity: "Enter the destination city (up to 80 characters).",
  recipientPostalCode:
    "Enter the destination postal code (up to 10 characters).",
  recipientPhone: "Enter the recipient's phone (up to 40 characters).",
  recipientEmail: "Enter a valid recipient email (up to 80 characters).",
  serviceType: "Choose Standard or Express.",
  weightKg:
    "Enter a weight greater than 0 and up to 30 kg, with at most 2 decimals.",
  packageDescription: "Describe the package (up to 255 characters).",
  declaredValue:
    "Enter a declared value from 0 to 50,000 MXN, with at most 2 decimals.",
  customerReference: "The order reference holds up to 50 characters.",
  deliveryInstructions: "The delivery instructions hold up to 1000 characters."
};
const PICKUP_DATE_MESSAGE =
  "Choose a business day (Monday to Friday) from 2026-11-20 to 2026-12-04.";
const FIELD_ERRORS_MESSAGE = "Check the marked fields.";
const GENERIC_MESSAGE =
  "We could not process your request. Please try again later.";
const QUOTE_FIRST_MESSAGE = "Get a quote before you confirm.";

const REQUIRED_FIELDS = [
  "pickupAddress",
  "pickupCity",
  "pickupPostalCode",
  "pickupDate",
  "recipientName",
  "recipientAddress",
  "recipientCity",
  "recipientPostalCode",
  "recipientPhone",
  "recipientEmail",
  "serviceType",
  "weightKg",
  "packageDescription",
  "declaredValue"
];
const OPTIONAL_FIELDS = ["customerReference", "deliveryInstructions"];
const ALL_FIELDS = [...REQUIRED_FIELDS, ...OPTIONAL_FIELDS];

const VALID = {
  pickupAddress: "Av. Insurgentes Sur 1602, Col. Crédito Constructor",
  pickupCity: "Ciudad de México",
  pickupPostalCode: "03940",
  pickupDate: "2026-11-24",
  recipientName: "Laura Méndez",
  recipientAddress: "Calle Hidalgo 45, Centro",
  recipientCity: "Puebla",
  recipientPostalCode: "72000",
  recipientPhone: "222-555-0134",
  recipientEmail: "laura.mendez@example.com",
  serviceType: "Standard",
  weightKg: "2.5",
  packageDescription: "Box of documents",
  declaredValue: "1000",
  customerReference: "PO-7781",
  deliveryInstructions: "Ring twice"
};

const EXPRESS = {
  ...VALID,
  pickupDate: "2026-12-04",
  recipientName: "  Jorge Ruiz  ",
  recipientEmail: "jorge.ruiz@example.org",
  serviceType: "Express",
  weightKg: "30.00",
  declaredValue: "50000",
  customerReference: "",
  deliveryInstructions: "   "
};

const QUOTE = {
  price: 180,
  earliestPickupDate: "2026-11-20",
  latestPickupDate: "2026-12-04"
};
const CONFIRMATION = {
  trackingNumber: "RC000001234",
  price: 180,
  estimatedDelivery: "2026-12-01",
  accessCode: "K7M2Q9X4B6TP"
};

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

function render() {
  const element = createElement("c-rc-request-shipment", {
    is: RcRequestShipment
  });
  document.body.appendChild(element);
  return element;
}

function query(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

function text(node) {
  return node ? node.textContent.replace(/\s+/g, " ").trim() : null;
}

function field(element, name) {
  return query(element, `[data-field="${name}"]`);
}

function setValue(element, name, value) {
  const input = field(element, name);
  input.value = value;
  input.dispatchEvent(new CustomEvent("input"));
  input.dispatchEvent(new CustomEvent("change"));
}

async function fill(element, values) {
  Object.entries(values).forEach(([name, value]) =>
    setValue(element, name, value)
  );
  await flushPromises();
}

function errorOf(element, name) {
  return text(query(element, `[data-error="${name}"]`));
}

function confirmButton(element) {
  return query(element, 'button[data-id="submit"]');
}

async function clickQuote(element) {
  query(element, 'button[data-id="quote"]').click();
  await flushPromises();
}

async function submit(element) {
  query(element, 'form[data-id="form"]').dispatchEvent(
    new CustomEvent("submit", { cancelable: true })
  );
  await flushPromises();
}

async function quoted(values = VALID, quote = QUOTE) {
  getQuote.mockResolvedValue(quote);
  const element = render();
  await fill(element, values);
  await clickQuote(element);
  return element;
}

function serverError(message) {
  return { body: { message }, status: 500 };
}

describe("c-rc-request-shipment", () => {
  beforeEach(() => {
    getQuote.mockReset();
    submitRequest.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
  });

  describe("AC-006.1: the form's fields and required marks", () => {
    it("AC-006.1: renders every AC-006.1 field with a label", () => {
      const element = render();

      ALL_FIELDS.forEach((name) => {
        const input = field(element, name);
        expect(input).not.toBeNull();
        const label = query(element, `label[for="${input.id}"]`);
        expect(label).not.toBeNull();
        expect(text(label).length).toBeGreaterThan(0);
      });
    });

    it("AC-006.1: marks the 14 required fields as required, the order reference and the instructions as optional", () => {
      const element = render();

      REQUIRED_FIELDS.forEach((name) => {
        expect([name, field(element, name).required]).toEqual([name, true]);
        const label = query(element, `label[for="${field(element, name).id}"]`);
        expect([name, text(label)]).toEqual([
          name,
          expect.stringMatching(/\*$/)
        ]);
      });
      OPTIONAL_FIELDS.forEach((name) => {
        expect([name, field(element, name).required]).toEqual([name, false]);
        const label = query(element, `label[for="${field(element, name).id}"]`);
        expect([name, text(label)]).toEqual([
          name,
          expect.stringMatching(/\(optional\)$/)
        ]);
      });
    });

    it("AC-006.1: the recipient email is required and marked", () => {
      const element = render();

      const email = field(element, "recipientEmail");
      expect(email.required).toBe(true);
      expect(email.getAttribute("type")).toBe("email");
      expect(text(query(element, `label[for="${email.id}"]`))).toBe(
        "Recipient email*"
      );
      expect(
        query(
          element,
          `label[for="${email.id}"] .rc-request__required`
        ).getAttribute("aria-hidden")
      ).toBe("true");
    });

    it("AC-006.1: offers exactly the service types Standard and Express", () => {
      const element = render();

      const values = Array.from(
        field(element, "serviceType").querySelectorAll("option")
      ).map((option) => option.value);
      expect(values).toEqual(["", "Standard", "Express"]);
    });
  });

  describe("AC-006.1: client errors", () => {
    it("AC-006.1: submitting the empty form shows a generic error under every required field and sends nothing", async () => {
      // A quote needs only the service, weight and declared value; every
      // other field stays empty.
      const element = await quoted({
        serviceType: "Standard",
        weightKg: "2.5",
        declaredValue: "1000"
      });

      await submit(element);

      REQUIRED_FIELDS.filter(
        (name) => !["serviceType", "weightKg", "declaredValue"].includes(name)
      ).forEach((name) => {
        const expected =
          name === "pickupDate" ? PICKUP_DATE_MESSAGE : MESSAGES[name];
        expect([name, errorOf(element, name)]).toEqual([name, expected]);
        expect([
          name,
          field(element, name).getAttribute("aria-invalid")
        ]).toEqual([name, "true"]);
      });
      expect(submitRequest).not.toHaveBeenCalled();
      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        FIELD_ERRORS_MESSAGE
      );
    });

    it("AC-006.1: a missing recipient email alone is refused on the client", async () => {
      const element = await quoted({ ...VALID, recipientEmail: "" });

      await submit(element);

      expect(errorOf(element, "recipientEmail")).toBe(MESSAGES.recipientEmail);
      expect(
        field(element, "recipientEmail").getAttribute("aria-invalid")
      ).toBe("true");
      expect(errorOf(element, "recipientName")).toBe("");
      expect(submitRequest).not.toHaveBeenCalled();
    });

    it("AC-006.1: a malformed recipient email is refused on the client", async () => {
      const element = await quoted({ ...VALID, recipientEmail: "laura@" });

      await submit(element);

      expect(errorOf(element, "recipientEmail")).toBe(MESSAGES.recipientEmail);
      expect(submitRequest).not.toHaveBeenCalled();
    });

    it.each([
      ["pickupPostalCode", "0".repeat(11)],
      ["recipientName", "N".repeat(121)],
      ["recipientPhone", "5".repeat(41)],
      ["pickupCity", "C".repeat(81)],
      ["packageDescription", "D".repeat(256)],
      ["customerReference", "R".repeat(51)],
      ["deliveryInstructions", "I".repeat(1001)]
    ])(
      "AC-006.1: %s longer than its field is refused on the client",
      async (name, value) => {
        const element = await quoted({ ...VALID, [name]: value });

        await submit(element);

        expect(errorOf(element, name)).toBe(MESSAGES[name]);
        expect(submitRequest).not.toHaveBeenCalled();
      }
    );

    it("AC-006.1: values at their field lengths are accepted", async () => {
      submitRequest.mockResolvedValue(CONFIRMATION);
      const element = await quoted({
        ...VALID,
        pickupPostalCode: "0".repeat(10),
        recipientName: "N".repeat(120),
        customerReference: "R".repeat(50)
      });

      await submit(element);

      expect(submitRequest).toHaveBeenCalledTimes(1);
      const { request } = submitRequest.mock.calls[0][0];
      expect(request.pickupPostalCode).toBe("0".repeat(10));
      expect(request.recipientName).toBe("N".repeat(120));
      expect(request.customerReference).toBe("R".repeat(50));
    });

    it("AC-006.1: errors are linked to their field (aria-describedby)", async () => {
      const element = await quoted({ ...VALID, pickupCity: "" });

      await submit(element);

      const input = field(element, "pickupCity");
      const ids = input.getAttribute("aria-describedby").split(" ");
      const described = ids.map((id) => text(query(element, `[id="${id}"]`)));
      expect(described).toContain(MESSAGES.pickupCity);
    });
  });

  describe("AC-006.1: server errors", () => {
    it("AC-006.1: the fields the server names are marked with the same messages as on the client", async () => {
      submitRequest.mockRejectedValue(
        serverError("Check these fields: recipientEmail, pickupDate")
      );
      const element = await quoted();

      await submit(element);

      expect(errorOf(element, "recipientEmail")).toBe(MESSAGES.recipientEmail);
      expect(errorOf(element, "pickupDate")).toBe(PICKUP_DATE_MESSAGE);
      expect(
        field(element, "recipientEmail").getAttribute("aria-invalid")
      ).toBe("true");
      expect(errorOf(element, "recipientName")).toBe("");
      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        FIELD_ERRORS_MESSAGE
      );
      expect(query(element, '[data-id="confirmation"]')).toBeNull();
    });

    it("AC-006.1: another named field (recipientPhone) is marked too", async () => {
      submitRequest.mockRejectedValue(
        serverError("Check these fields: recipientPhone")
      );
      const element = await quoted();

      await submit(element);

      expect(errorOf(element, "recipientPhone")).toBe(MESSAGES.recipientPhone);
      expect(errorOf(element, "recipientEmail")).toBe("");
    });

    it("AC-006.1: field names the form does not know are ignored and a generic text is shown", async () => {
      submitRequest.mockRejectedValue(
        serverError("Check these fields: Carrier_Cost__c")
      );
      const element = await quoted();

      await submit(element);

      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        GENERIC_MESSAGE
      );
      expect(element.shadowRoot.textContent).not.toContain("Carrier_Cost__c");
    });

    it.each([[NOT_AVAILABLE_MESSAGE], [SAVE_FAILED_MESSAGE]])(
      "AC-006.1: the server's known message is shown as text: %s",
      async (message) => {
        submitRequest.mockRejectedValue(serverError(message));
        const element = await quoted();

        await submit(element);

        expect(text(query(element, '[data-id="form-error"]'))).toBe(message);
      }
    );

    it("AC-006.1: an unknown server text is never shown", async () => {
      submitRequest.mockRejectedValue(
        serverError(
          "System.DmlException: Insert failed. FIELD_CUSTOM_VALIDATION_EXCEPTION Internal_Notes__c"
        )
      );
      const element = await quoted();

      await submit(element);

      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        GENERIC_MESSAGE
      );
      expect(element.shadowRoot.textContent).not.toContain("DmlException");
    });
  });

  describe("AC-006.2: the quote before the confirm button", () => {
    it("AC-006.2: the confirm button is disabled before a quote", async () => {
      const element = render();
      await fill(element, VALID);

      expect(confirmButton(element).disabled).toBe(true);
      expect(query(element, '[data-id="quote-price"]')).toBeNull();
    });

    it("AC-006.2: submitting before a quote sends nothing", async () => {
      const element = render();
      await fill(element, VALID);

      await submit(element);

      expect(submitRequest).not.toHaveBeenCalled();
      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        QUOTE_FIRST_MESSAGE
      );
    });

    it("AC-006.2: Standard 2.5 kg, declared 1,000.00: asks the server and shows 180.00 MXN, then enables confirm", async () => {
      const element = await quoted();

      expect(getQuote).toHaveBeenCalledWith({
        serviceType: "Standard",
        weightKg: 2.5,
        declaredValue: 1000
      });
      expect(text(query(element, '[data-id="quote-price"]'))).toBe(
        "180.00 MXN"
      );
      expect(confirmButton(element).disabled).toBe(false);
    });

    it("AC-006.2: Express 30 kg, declared 50,000.00: shows 1,870.00 MXN", async () => {
      const element = await quoted(EXPRESS, { ...QUOTE, price: 1870 });

      expect(getQuote).toHaveBeenCalledWith({
        serviceType: "Express",
        weightKg: 30,
        declaredValue: 50000
      });
      expect(text(query(element, '[data-id="quote-price"]'))).toBe(
        "1,870.00 MXN"
      );
    });

    it("AC-006.2: Standard 1.25 kg, declared 333.33: shows the server's 147.50 MXN", async () => {
      const element = await quoted(
        { ...VALID, weightKg: "1.25", declaredValue: "333.33" },
        { ...QUOTE, price: 147.5 }
      );

      expect(getQuote).toHaveBeenCalledWith({
        serviceType: "Standard",
        weightKg: 1.25,
        declaredValue: 333.33
      });
      expect(text(query(element, '[data-id="quote-price"]'))).toBe(
        "147.50 MXN"
      );
    });

    it("AC-006.2: shows the pickup window of the quote and limits the date input to it", async () => {
      const element = await quoted();

      expect(text(query(element, '[data-id="pickup-window"]'))).toBe(
        "Pickup dates: business days from 2026-11-20 to 2026-12-04."
      );
      expect(field(element, "pickupDate").min).toBe("2026-11-20");
      expect(field(element, "pickupDate").max).toBe("2026-12-04");
    });

    it.each([
      ["serviceType", "Express"],
      ["weightKg", "3"],
      ["declaredValue", "10"]
    ])(
      "AC-006.2: changing %s withdraws the quote and disables confirm",
      async (name, value) => {
        const element = await quoted();

        await fill(element, { [name]: value });

        expect(query(element, '[data-id="quote-price"]')).toBeNull();
        expect(confirmButton(element).disabled).toBe(true);
      }
    );

    it("AC-006.2: a refused quote shows the field error and keeps confirm disabled", async () => {
      getQuote.mockRejectedValue(serverError("Check these fields: weightKg"));
      const element = render();
      await fill(element, VALID);

      await clickQuote(element);

      expect(errorOf(element, "weightKg")).toBe(MESSAGES.weightKg);
      expect(confirmButton(element).disabled).toBe(true);
    });

    it("AC-006.2: the quote needs only the service, weight and declared value", async () => {
      getQuote.mockResolvedValue(QUOTE);
      const element = render();
      await fill(element, {
        serviceType: "Express",
        weightKg: "1",
        declaredValue: "0"
      });

      await clickQuote(element);

      expect(getQuote).toHaveBeenCalledWith({
        serviceType: "Express",
        weightKg: 1,
        declaredValue: 0
      });
      expect(errorOf(element, "pickupAddress")).toBe("");
    });
  });

  describe("AC-006.4: weight and declared value limits", () => {
    it("AC-006.4: 30.00 kg and 50,000 declared are accepted", async () => {
      getQuote.mockResolvedValue(QUOTE);
      const element = render();
      await fill(element, {
        serviceType: "Standard",
        weightKg: "30.00",
        declaredValue: "50000.00"
      });

      await clickQuote(element);

      expect(getQuote).toHaveBeenCalledWith({
        serviceType: "Standard",
        weightKg: 30,
        declaredValue: 50000
      });
      expect(errorOf(element, "weightKg")).toBe("");
      expect(errorOf(element, "declaredValue")).toBe("");
    });

    it.each([["30.01"], ["0"], ["-1"], ["1.333"], ["abc"], [""]])(
      "AC-006.4: weight %p is rejected on the client",
      async (weight) => {
        // A quote is available, so only the client check can stop the call.
        getQuote.mockResolvedValue(QUOTE);
        const element = render();
        await fill(element, {
          serviceType: "Standard",
          weightKg: weight,
          declaredValue: "1000"
        });

        await clickQuote(element);

        expect(errorOf(element, "weightKg")).toBe(MESSAGES.weightKg);
        expect(getQuote).not.toHaveBeenCalled();
      }
    );

    it.each([["50000.01"], ["-1"], ["10.001"], [""]])(
      "AC-006.4: declared value %p is rejected on the client",
      async (declared) => {
        // A quote is available, so only the client check can stop the call.
        getQuote.mockResolvedValue(QUOTE);
        const element = render();
        await fill(element, {
          serviceType: "Standard",
          weightKg: "2",
          declaredValue: declared
        });

        await clickQuote(element);

        expect(errorOf(element, "declaredValue")).toBe(MESSAGES.declaredValue);
        expect(getQuote).not.toHaveBeenCalled();
      }
    );

    it("AC-006.4: a missing service type is rejected on the client", async () => {
      getQuote.mockResolvedValue(QUOTE);
      const element = render();
      await fill(element, {
        serviceType: "",
        weightKg: "2",
        declaredValue: "10"
      });

      await clickQuote(element);

      expect(errorOf(element, "serviceType")).toBe(MESSAGES.serviceType);
      expect(getQuote).not.toHaveBeenCalled();
    });
  });

  describe("AC-006.3 (client mirror): the pickup date", () => {
    it.each([
      ["2026-11-21", "a Saturday"],
      ["2026-11-22", "a Sunday"],
      ["2026-11-19", "before the window"],
      ["2026-12-07", "after the window"],
      ["2026-02-30", "not a date"]
    ])("rejects %s (%s) on the client", async (pickupDate) => {
      const element = await quoted({ ...VALID, pickupDate });

      await submit(element);

      expect(errorOf(element, "pickupDate")).toBe(PICKUP_DATE_MESSAGE);
      expect(submitRequest).not.toHaveBeenCalled();
    });

    it.each([["2026-11-20"], ["2026-12-04"]])(
      "accepts %s, a business day at an end of the window",
      async (pickupDate) => {
        submitRequest.mockResolvedValue(CONFIRMATION);
        const element = await quoted({ ...VALID, pickupDate });

        await submit(element);

        expect(submitRequest).toHaveBeenCalledTimes(1);
        expect(submitRequest.mock.calls[0][0].request.pickupDate).toBe(
          pickupDate
        );
      }
    );
  });

  describe("AC-007.4: confirm and the confirmation", () => {
    it("AC-006.1: sends every entered field once, trimmed, with numbers for weight and declared value", async () => {
      submitRequest.mockResolvedValue(CONFIRMATION);
      const element = await quoted();

      await submit(element);

      expect(submitRequest).toHaveBeenCalledTimes(1);
      expect(submitRequest).toHaveBeenCalledWith({
        request: {
          pickupAddress: VALID.pickupAddress,
          pickupCity: VALID.pickupCity,
          pickupPostalCode: VALID.pickupPostalCode,
          pickupDate: VALID.pickupDate,
          recipientName: VALID.recipientName,
          recipientAddress: VALID.recipientAddress,
          recipientCity: VALID.recipientCity,
          recipientPostalCode: VALID.recipientPostalCode,
          recipientPhone: VALID.recipientPhone,
          recipientEmail: VALID.recipientEmail,
          serviceType: "Standard",
          weightKg: 2.5,
          packageDescription: VALID.packageDescription,
          declaredValue: 1000,
          customerReference: "PO-7781",
          deliveryInstructions: "Ring twice"
        }
      });
    });

    it("AC-006.1: a second request trims values and sends blank optional fields as null", async () => {
      submitRequest.mockResolvedValue(CONFIRMATION);
      const element = await quoted(EXPRESS, { ...QUOTE, price: 1870 });

      await submit(element);

      const { request } = submitRequest.mock.calls[0][0];
      expect(request.recipientName).toBe("Jorge Ruiz");
      expect(request.recipientEmail).toBe("jorge.ruiz@example.org");
      expect(request.serviceType).toBe("Express");
      expect(request.weightKg).toBe(30);
      expect(request.declaredValue).toBe(50000);
      expect(request.pickupDate).toBe("2026-12-04");
      expect(request.customerReference).toBeNull();
      expect(request.deliveryInstructions).toBeNull();
    });

    it("AC-007.4: shows the tracking number, price, estimate and access code after confirming", async () => {
      submitRequest.mockResolvedValue(CONFIRMATION);
      const element = await quoted();

      await submit(element);

      const confirmation = query(element, '[data-id="confirmation"]');
      expect(confirmation).not.toBeNull();
      expect(text(query(element, 'dd[data-field="trackingNumber"]'))).toBe(
        "RC000001234"
      );
      expect(text(query(element, 'dd[data-field="price"]'))).toBe("180.00 MXN");
      expect(text(query(element, 'dd[data-field="estimatedDelivery"]'))).toBe(
        "2026-12-01"
      );
      expect(text(query(element, '[data-field="accessCode"]'))).toBe(
        "K7M2Q9X4B6TP"
      );
      expect(query(element, 'form[data-id="form"]')).toBeNull();
    });

    it("AC-007.4: a second confirmation shows its own values", async () => {
      submitRequest.mockResolvedValue({
        trackingNumber: "RC000009876",
        price: 310,
        estimatedDelivery: "2026-11-26",
        accessCode: "ZXCV5678QWER"
      });
      const element = await quoted(
        { ...VALID, serviceType: "Express" },
        {
          ...QUOTE,
          price: 310
        }
      );

      await submit(element);

      expect(text(query(element, 'dd[data-field="trackingNumber"]'))).toBe(
        "RC000009876"
      );
      expect(text(query(element, 'dd[data-field="price"]'))).toBe("310.00 MXN");
      expect(text(query(element, 'dd[data-field="estimatedDelivery"]'))).toBe(
        "2026-11-26"
      );
      expect(text(query(element, '[data-field="accessCode"]'))).toBe(
        "ZXCV5678QWER"
      );
    });

    it("AC-007.4: links to the shipment's detail and to My shipments", async () => {
      submitRequest.mockResolvedValue(CONFIRMATION);
      const element = await quoted();

      await submit(element);

      expect(
        query(element, 'a[data-id="detail-link"]').getAttribute("href")
      ).toBe("/rutacargo/shipment-detail?tracking=RC000001234");
      expect(
        query(element, 'a[data-id="list-link"]').getAttribute("href")
      ).toBe("/rutacargo/my-shipments");
    });

    it("AC-007.4: the access code is shown once: a new request removes it from the page", async () => {
      submitRequest.mockResolvedValue(CONFIRMATION);
      const element = await quoted();
      await submit(element);

      query(element, 'button[data-id="new-request"]').click();
      await flushPromises();

      expect(element.shadowRoot.textContent).not.toContain("K7M2Q9X4B6TP");
      expect(query(element, 'form[data-id="form"]')).not.toBeNull();
      expect(confirmButton(element).disabled).toBe(true);
    });

    it("AC-007.4: the access code is never stored, logged or put in a URL", async () => {
      const setItem = jest.spyOn(Storage.prototype, "setItem");
      const consoleSpies = ["log", "info", "warn", "error", "debug"].map(
        (method) => jest.spyOn(console, method).mockImplementation(() => {})
      );
      submitRequest.mockResolvedValue(CONFIRMATION);
      const element = await quoted();

      await submit(element);

      expect(setItem).not.toHaveBeenCalled();
      consoleSpies.forEach((spy) => expect(spy).not.toHaveBeenCalled());
      Array.from(element.shadowRoot.querySelectorAll("a")).forEach((link) =>
        expect(link.getAttribute("href")).not.toContain("K7M2Q9X4B6TP")
      );
      expect(document.cookie).not.toContain("K7M2Q9X4B6TP");
    });

    it("AC-007.4: server values are rendered as text, never as markup", async () => {
      submitRequest.mockResolvedValue({
        ...CONFIRMATION,
        trackingNumber: '<img src="x" onerror="alert(1)">',
        accessCode: "<b>CODE</b>"
      });
      const element = await quoted();

      await submit(element);

      expect(element.shadowRoot.querySelector("img")).toBeNull();
      expect(element.shadowRoot.querySelector("b")).toBeNull();
      expect(text(query(element, 'dd[data-field="trackingNumber"]'))).toBe(
        '<img src="x" onerror="alert(1)">'
      );
    });

    it("AC-007.4: the confirm button is disabled while the request is sent", async () => {
      let resolve;
      submitRequest.mockReturnValue(
        new Promise((done) => {
          resolve = done;
        })
      );
      const element = await quoted();

      await submit(element);

      expect(confirmButton(element).disabled).toBe(true);
      await submit(element);
      expect(submitRequest).toHaveBeenCalledTimes(1);
      resolve(CONFIRMATION);
      await flushPromises();
      expect(query(element, '[data-id="confirmation"]')).not.toBeNull();
    });
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

    it("AC-007.4: the form is one column below 768 px (no multi-column grid outside a min-width: 48em query)", () => {
      const css = fs.readFileSync(
        path.join(dir, "rcRequestShipment.css"),
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
        path.join(dir, "rcRequestShipment.css"),
        "utf8"
      );

      expect(css).toMatch(/\.rc-request__label\s*\{[^}]*font-weight:\s*500/);
      expect(css).toMatch(
        /\.rc-request\s*\{[^}]*--dxp-c-link-text-decoration:\s*underline/
      );
      expect(css).not.toMatch(/#ff3636|#ffc91d/i);
    });
  });
});
