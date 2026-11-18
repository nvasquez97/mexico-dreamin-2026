// Covers odd/tasks/req-002-003-recipient-delivery.md, AC-002.8 (the delivery
// details component: postal code and access code inputs, the five details
// labelled, the proof button only when proofAvailable, the reschedule form only
// when canReschedule, the exact server texts, text-only rendering, the code in
// component memory only) and the UI parts of AC-002.2 (details labelled),
// AC-002.3 (the wrong postal code text and no details), AC-002.4 (the PDF
// download), AC-002.5 (the proof error text) and AC-003.1 (the form and the
// saved date).
import { createElement } from "lwc";
import RcDeliveryDetails from "c/rcDeliveryDetails";
import getDeliveryDetails from "@salesforce/apex/RecipientDeliveryController.getDeliveryDetails";
import rescheduleDelivery from "@salesforce/apex/RecipientDeliveryController.rescheduleDelivery";
import downloadProof from "@salesforce/apex/RecipientDeliveryController.downloadProof";

const fs = require("fs");
const path = require("path");

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

// The server's texts (RecipientAccess, RecipientDeliveryController).
const NOT_MATCHED = "The details do not match this shipment";
const LOCKED = "Too many attempts. Please try again in 15 minutes.";
const PROOF_UNAVAILABLE =
  "We could not get the proof of delivery, please try again later";
const PROOF_NOT_AVAILABLE =
  "The proof of delivery is not available for this shipment.";
const WINDOW_MESSAGE =
  "The new delivery date is outside the allowed rescheduling window.";
const STATUS_MESSAGE =
  "This delivery cannot be rescheduled in its current status.";
const LIMIT_MESSAGE =
  "This delivery has already been rescheduled the maximum number of times.";
const NO_ESTIMATE_MESSAGE =
  "This delivery has no estimated date to reschedule from yet.";
const GENERIC_ERROR =
  "We could not complete your request. Please try again later.";

// "%PDF-1.4\n%EOF" as base64: a small PDF payload.
const PDF_TEXT = "%PDF-1.4\n%EOF";
const PDF_BASE64 = btoa(PDF_TEXT);

function details(overrides) {
  return {
    recipientName: "Ana López",
    deliveryAddress: "Av. Juárez 120, 06050 Ciudad de México",
    contactPhone: "+52 55 1234 5678",
    estimatedDelivery: "2026-11-20",
    deliveryInstructions: "Ring twice",
    status: "In transit",
    canReschedule: false,
    reschedulesLeft: 2,
    rescheduleFrom: null,
    rescheduleTo: null,
    proofAvailable: false,
    ...overrides
  };
}

function success(detailOverrides) {
  return {
    outcome: "SUCCESS",
    message: null,
    details: details(detailOverrides)
  };
}

function render(trackingNumber = "RC000001001") {
  const element = createElement("c-rc-delivery-details", {
    is: RcDeliveryDetails
  });
  element.trackingNumber = trackingNumber;
  document.body.appendChild(element);
  return element;
}

// Settles the mocked Apex promise chain (then, catch, finally) and the
// re-render it triggers: a few microtask turns, no timers.
function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

function query(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

function queryAll(element, selector) {
  return Array.from(element.shadowRoot.querySelectorAll(selector));
}

function text(node) {
  return node ? node.textContent.trim() : null;
}

async function change(element, selector, value) {
  const input = query(element, selector);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await Promise.resolve();
}

async function click(element, selector) {
  query(element, selector).click();
  await flushPromises();
}

async function verify(element, postalCode = "06050", code = "ABCD2345EFGH") {
  await change(element, '[data-id="postal-code"]', postalCode);
  await change(element, '[data-id="access-code"]', code);
  await click(element, '[data-id="verify"]');
}

function detailValue(element, name) {
  return text(query(element, `[data-field="${name}"]`));
}

function detailLabels(element) {
  return queryAll(element, '[data-id="details"] dt').map(text);
}

function readBlob(blob) {
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.readAsText(blob);
  });
}

describe("c-rc-delivery-details", () => {
  let createObjectURL;
  let revokeObjectURL;
  let clickedAnchors;

  beforeEach(() => {
    getDeliveryDetails.mockReset();
    rescheduleDelivery.mockReset();
    downloadProof.mockReset();
    getDeliveryDetails.mockResolvedValue(success());
    createObjectURL = jest.fn(() => "blob:https://rutacargo.example/1a2b");
    revokeObjectURL = jest.fn();
    URL.createObjectURL = createObjectURL;
    URL.revokeObjectURL = revokeObjectURL;
    clickedAnchors = [];
    jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(function recordClick() {
        clickedAnchors.push({ href: this.href, download: this.download });
      });
    window.localStorage.clear();
    window.sessionStorage.clear();
  });

  afterEach(() => {
    jest.restoreAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  describe("verification form", () => {
    it("AC-002.8: shows the postal code and access code inputs and no details before verifying", () => {
      const element = render();

      expect(query(element, '[data-id="postal-code"]').label).toBe(
        "Destination postal code"
      );
      expect(query(element, '[data-id="access-code"]').label).toBe(
        "Access code"
      );
      expect(query(element, '[data-id="details"]')).toBeNull();
      expect(getDeliveryDetails).not.toHaveBeenCalled();
    });

    it.each([
      ["abcd2345efgh", "ABCD-2345-EFGH"],
      ["k7m9 p2q3-r4s5xyz", "K7M9-P2Q3-R4S5"]
    ])(
      "AC-002.8: the typed code %s is shown grouped as %s, any case",
      async (typed, shown) => {
        const element = render();

        await change(element, '[data-id="access-code"]', typed);

        expect(query(element, '[data-id="access-code"]').value).toBe(shown);
      }
    );

    it("AC-002.8: sends the tracking number, postal code and grouped code to getDeliveryDetails", async () => {
      const element = render("RC000001042");

      await verify(element, " 64000 ", "wxyz2345abcd");

      expect(getDeliveryDetails).toHaveBeenCalledTimes(1);
      expect(getDeliveryDetails).toHaveBeenCalledWith({
        trackingNumber: "RC000001042",
        postalCode: "64000",
        accessCode: "WXYZ-2345-ABCD"
      });
    });

    it("AC-002.8: an empty postal code or code makes no Apex call and asks for both", async () => {
      const element = render();

      await change(element, '[data-id="postal-code"]', "06050");
      await click(element, '[data-id="verify"]');

      expect(getDeliveryDetails).not.toHaveBeenCalled();
      expect(text(query(element, '[data-id="error"]'))).toBe(
        "Enter the destination postal code and the access code."
      );
    });
  });

  describe("details", () => {
    it("AC-002.2: shows the five details labelled, as received", async () => {
      const element = render();

      await verify(element);

      expect(detailLabels(element)).toEqual([
        "Recipient name",
        "Delivery address",
        "Contact phone",
        "Estimated delivery",
        "Delivery instructions"
      ]);
      expect(detailValue(element, "recipientName")).toBe("Ana López");
      expect(detailValue(element, "deliveryAddress")).toBe(
        "Av. Juárez 120, 06050 Ciudad de México"
      );
      expect(detailValue(element, "contactPhone")).toBe("+52 55 1234 5678");
      expect(detailValue(element, "estimatedDelivery")).toBe("2026-11-20");
      expect(detailValue(element, "deliveryInstructions")).toBe("Ring twice");
    });

    it("AC-002.2: a second shipment shows its own values and missing ones as Not available", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({
          recipientName: "Marta Ruiz",
          deliveryAddress: "Calle 5 de Mayo 33, 64000 Monterrey",
          contactPhone: null,
          estimatedDelivery: "2026-12-03",
          deliveryInstructions: null
        })
      );
      const element = render("RC000001061");

      await verify(element, "64000", "WXYZ2345ABCD");

      expect(detailValue(element, "recipientName")).toBe("Marta Ruiz");
      expect(detailValue(element, "deliveryAddress")).toBe(
        "Calle 5 de Mayo 33, 64000 Monterrey"
      );
      expect(detailValue(element, "contactPhone")).toBe("Not available");
      expect(detailValue(element, "estimatedDelivery")).toBe("2026-12-03");
      expect(detailValue(element, "deliveryInstructions")).toBe(
        "Not available"
      );
    });

    it("AC-002.3: a wrong postal code shows exactly the server text and no details", async () => {
      getDeliveryDetails.mockResolvedValue({
        outcome: "NOT_MATCHED",
        message: NOT_MATCHED,
        details: null
      });
      const element = render();

      await verify(element, "99999");

      expect(text(query(element, '[data-id="error"]'))).toBe(NOT_MATCHED);
      expect(query(element, '[data-id="error"]').getAttribute("role")).toBe(
        "alert"
      );
      expect(query(element, '[data-id="details"]')).toBeNull();
    });

    it("AC-002.1b: the lock shows exactly the server text and no details", async () => {
      getDeliveryDetails.mockResolvedValue({
        outcome: "LOCKED",
        message: LOCKED,
        details: null
      });
      const element = render();

      await verify(element);

      expect(text(query(element, '[data-id="error"]'))).toBe(LOCKED);
      expect(query(element, '[data-id="details"]')).toBeNull();
    });

    it("AC-002.8: a failed outcome never renders details, even when the payload carries some", async () => {
      getDeliveryDetails.mockResolvedValue({
        outcome: "NOT_MATCHED",
        message: NOT_MATCHED,
        details: details()
      });
      const element = render();

      await verify(element);

      expect(query(element, '[data-id="details"]')).toBeNull();
      expect(element.shadowRoot.textContent).not.toContain("Ana López");
    });

    it("AC-002.8: no details are rendered while the verification is pending", async () => {
      let resolveCall;
      getDeliveryDetails.mockReturnValue(
        new Promise((resolve) => {
          resolveCall = resolve;
        })
      );
      const element = render();

      await verify(element);

      expect(query(element, '[data-id="details"]')).toBeNull();
      expect(query(element, '[data-id="verify"]').disabled).toBe(true);
      resolveCall(success());
      await flushPromises();
      expect(query(element, '[data-id="details"]')).not.toBeNull();
    });

    it("AC-002.3: a second verification after a success that fails hides the earlier details", async () => {
      getDeliveryDetails.mockResolvedValueOnce(success());
      getDeliveryDetails.mockResolvedValueOnce({
        outcome: "NOT_MATCHED",
        message: NOT_MATCHED,
        details: null
      });
      const element = render();

      await verify(element);
      await verify(element, "11111");

      expect(query(element, '[data-id="details"]')).toBeNull();
      expect(text(query(element, '[data-id="error"]'))).toBe(NOT_MATCHED);
    });

    it.each([
      [
        "an unknown message",
        () =>
          Promise.resolve({
            outcome: "NOT_MATCHED",
            message: "Shipment__c row 0 locked by another user",
            details: null
          })
      ],
      [
        "a thrown error",
        () =>
          Promise.reject({
            body: { message: "System.QueryException: List has no rows" }
          })
      ],
      ["a malformed response", () => Promise.resolve("unexpected")]
    ])("AC-002.8: %s shows the generic text only", async (label, answer) => {
      getDeliveryDetails.mockImplementation(answer);
      const element = render();

      await verify(element);

      expect(text(query(element, '[data-id="error"]'))).toBe(GENERIC_ERROR);
      expect(query(element, '[data-id="details"]')).toBeNull();
    });

    it("AC-002.8: values render only as text, never as markup", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({
          recipientName: '<img src=x onerror="alert(1)">',
          deliveryInstructions: "<b>Leave it</b>"
        })
      );
      const element = render();

      await verify(element);

      expect(detailValue(element, "recipientName")).toBe(
        '<img src=x onerror="alert(1)">'
      );
      expect(detailValue(element, "deliveryInstructions")).toBe(
        "<b>Leave it</b>"
      );
      expect(element.shadowRoot.querySelector("img, b")).toBeNull();
    });
  });

  describe("proof of delivery", () => {
    it("AC-002.8: no proof button when proofAvailable is false", async () => {
      const element = render();

      await verify(element);

      expect(query(element, '[data-id="download-proof"]')).toBeNull();
    });

    it("AC-002.8: the proof button is labelled Download proof of delivery when proofAvailable", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({ status: "Delivered", proofAvailable: true })
      );
      const element = render();

      await verify(element);

      expect(query(element, '[data-id="download-proof"]').label).toBe(
        "Download proof of delivery"
      );
    });

    it.each([
      ["proof-RC000001001.pdf", "proof-RC000001001.pdf", "Ana López"],
      ["../../evil<script>.pdf", "evil_script_.pdf", "<b>Marta</b>"]
    ])(
      "AC-002.4: downloads %s as a PDF Blob named %s, signed by text",
      async (fileName, savedAs, signedBy) => {
        getDeliveryDetails.mockResolvedValue(
          success({ status: "Delivered", proofAvailable: true })
        );
        downloadProof.mockResolvedValue({
          outcome: "SUCCESS",
          message: null,
          proofAvailable: true,
          fileName,
          signedBy,
          pdfBase64: PDF_BASE64
        });
        const element = render("RC000001010");

        await verify(element, "06050", "abcd2345efgh");
        await click(element, '[data-id="download-proof"]');

        expect(downloadProof).toHaveBeenCalledWith({
          trackingNumber: "RC000001010",
          postalCode: "06050",
          accessCode: "ABCD-2345-EFGH"
        });
        expect(createObjectURL).toHaveBeenCalledTimes(1);
        const blob = createObjectURL.mock.calls[0][0];
        expect(blob.type).toBe("application/pdf");
        expect(await readBlob(blob)).toBe(PDF_TEXT);
        expect(clickedAnchors).toEqual([
          { href: "blob:https://rutacargo.example/1a2b", download: savedAs }
        ]);
        expect(text(query(element, '[data-id="signed-by"]'))).toBe(
          `Signed by: ${signedBy}`
        );
        expect(element.shadowRoot.querySelector("b")).toBeNull();
      }
    );

    it("AC-002.4: the download never navigates to a data: URL", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({ status: "Delivered", proofAvailable: true })
      );
      downloadProof.mockResolvedValue({
        outcome: "SUCCESS",
        message: null,
        proofAvailable: true,
        fileName: "proof.pdf",
        signedBy: "Ana",
        pdfBase64: PDF_BASE64
      });
      const openSpy = jest.spyOn(window, "open").mockImplementation(() => null);
      const element = render();

      await verify(element);
      await click(element, '[data-id="download-proof"]');

      expect(openSpy).not.toHaveBeenCalled();
      expect(clickedAnchors).toHaveLength(1);
      expect(clickedAnchors[0].href).toBe(
        createObjectURL.mock.results[0].value
      );
      expect(clickedAnchors[0].href).toMatch(/^blob:/);
    });

    it.each([
      ["NOT_MATCHED", NOT_MATCHED],
      ["LOCKED", LOCKED]
    ])(
      "AC-002.3 / AC-002.1b: a %s answer to the download hides the details and shows exactly the server text",
      async (outcome, message) => {
        getDeliveryDetails.mockResolvedValue(
          success({ status: "Delivered", proofAvailable: true })
        );
        downloadProof.mockResolvedValue({
          outcome,
          message,
          proofAvailable: false
        });
        const element = render();

        await verify(element);
        await click(element, '[data-id="download-proof"]');

        expect(query(element, '[data-id="details"]')).toBeNull();
        expect(query(element, '[data-id="download-proof"]')).toBeNull();
        expect(text(query(element, '[data-id="error"]'))).toBe(message);
        expect(element.shadowRoot.textContent).not.toContain("Ana López");
        expect(createObjectURL).not.toHaveBeenCalled();
        expect(clickedAnchors).toEqual([]);
      }
    );

    it("AC-002.5: a NOT_AVAILABLE answer shows exactly the server text, keeps the details and downloads nothing", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({ status: "Delivered", proofAvailable: true })
      );
      downloadProof.mockResolvedValue({
        outcome: "NOT_AVAILABLE",
        message: PROOF_NOT_AVAILABLE,
        proofAvailable: false
      });
      const element = render();

      await verify(element);
      await click(element, '[data-id="download-proof"]');

      expect(text(query(element, '[data-id="proof-error"]'))).toBe(
        PROOF_NOT_AVAILABLE
      );
      expect(query(element, '[data-id="details"]')).not.toBeNull();
      expect(query(element, '[data-id="error"]')).toBeNull();
      expect(createObjectURL).not.toHaveBeenCalled();
      expect(clickedAnchors).toEqual([]);
    });

    it("AC-002.5: an EntregaYa failure shows exactly the server text and downloads nothing", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({ status: "Delivered", proofAvailable: true })
      );
      downloadProof.mockResolvedValue({
        outcome: "UNAVAILABLE",
        message: PROOF_UNAVAILABLE,
        proofAvailable: true
      });
      const element = render();

      await verify(element);
      await click(element, '[data-id="download-proof"]');

      expect(text(query(element, '[data-id="proof-error"]'))).toBe(
        PROOF_UNAVAILABLE
      );
      expect(createObjectURL).not.toHaveBeenCalled();
      expect(clickedAnchors).toEqual([]);
    });

    it.each([
      [
        "a thrown error",
        () => Promise.reject({ body: { message: "Read timed out" } })
      ],
      [
        "a payload that is not a PDF",
        () =>
          Promise.resolve({
            outcome: "SUCCESS",
            proofAvailable: true,
            fileName: "proof.pdf",
            signedBy: "Ana",
            pdfBase64: btoa("<html>not a pdf</html>")
          })
      ]
    ])(
      "AC-002.5: %s shows the proof text and downloads nothing",
      async (label, answer) => {
        getDeliveryDetails.mockResolvedValue(
          success({ status: "Delivered", proofAvailable: true })
        );
        downloadProof.mockImplementation(answer);
        const element = render();

        await verify(element);
        await click(element, '[data-id="download-proof"]');

        expect(text(query(element, '[data-id="proof-error"]'))).toBe(
          PROOF_UNAVAILABLE
        );
        expect(clickedAnchors).toEqual([]);
      }
    );
  });

  describe("reschedule", () => {
    const window1 = {
      canReschedule: true,
      reschedulesLeft: 2,
      rescheduleFrom: "2026-11-18",
      rescheduleTo: "2026-11-27"
    };

    it("AC-003.1: no reschedule form when canReschedule is false", async () => {
      const element = render();

      await verify(element);

      expect(query(element, '[data-id="reschedule-form"]')).toBeNull();
    });

    it("AC-003.1: the form bounds the date by rescheduleFrom/rescheduleTo and shows the reschedules left", async () => {
      getDeliveryDetails.mockResolvedValue(success(window1));
      const element = render();

      await verify(element);

      const date = query(element, '[data-id="new-date"]');
      expect(date.type).toBe("date");
      expect(date.min).toBe("2026-11-18");
      expect(date.max).toBe("2026-11-27");
      expect(query(element, '[data-id="instructions"]').maxLength).toBe(1000);
      expect(query(element, '[data-id="instructions"]').value).toBe(
        "Ring twice"
      );
      expect(text(query(element, '[data-id="reschedules-left"]'))).toBe(
        "Reschedules left: 2"
      );
    });

    it("AC-003.1: a second window shows its own bounds and one reschedule left", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({
          canReschedule: true,
          reschedulesLeft: 1,
          rescheduleFrom: "2026-12-01",
          rescheduleTo: "2026-12-09"
        })
      );
      const element = render();

      await verify(element);

      expect(query(element, '[data-id="new-date"]').min).toBe("2026-12-01");
      expect(query(element, '[data-id="new-date"]').max).toBe("2026-12-09");
      expect(text(query(element, '[data-id="reschedules-left"]'))).toBe(
        "Reschedules left: 1"
      );
    });

    it.each([
      ["2026-11-25", "Leave with the doorman"],
      ["2026-11-19", "Call before arriving"]
    ])(
      "AC-003.1: saving %s with new instructions shows the saved date",
      async (newDate, instructions) => {
        getDeliveryDetails.mockResolvedValue(success(window1));
        rescheduleDelivery.mockResolvedValue(
          success({
            ...window1,
            reschedulesLeft: 1,
            estimatedDelivery: newDate,
            deliveryInstructions: instructions
          })
        );
        const element = render("RC000001005");

        await verify(element, "06050", "ABCD2345EFGH");
        await change(element, '[data-id="new-date"]', newDate);
        await change(element, '[data-id="instructions"]', instructions);
        await click(element, '[data-id="reschedule"]');

        expect(rescheduleDelivery).toHaveBeenCalledWith({
          trackingNumber: "RC000001005",
          postalCode: "06050",
          accessCode: "ABCD-2345-EFGH",
          newDate,
          instructions
        });
        expect(text(query(element, '[data-id="reschedule-success"]'))).toBe(
          `Your delivery is rescheduled for ${newDate}.`
        );
        expect(detailValue(element, "estimatedDelivery")).toBe(newDate);
        expect(detailValue(element, "deliveryInstructions")).toBe(instructions);
        expect(text(query(element, '[data-id="reschedules-left"]'))).toBe(
          "Reschedules left: 1"
        );
      }
    );

    it("AC-003.1: the saved date stays shown when no reschedule is left", async () => {
      getDeliveryDetails.mockResolvedValue(success(window1));
      rescheduleDelivery.mockResolvedValue(
        success({ estimatedDelivery: "2026-11-26", reschedulesLeft: 0 })
      );
      const element = render();

      await verify(element);
      await change(element, '[data-id="new-date"]', "2026-11-26");
      await click(element, '[data-id="reschedule"]');

      expect(query(element, '[data-id="reschedule-form"]')).toBeNull();
      expect(text(query(element, '[data-id="reschedule-success"]'))).toBe(
        "Your delivery is rescheduled for 2026-11-26."
      );
    });

    // The details the server returns with these rejections
    // (RecipientDeliveryController.detailsOf): once the shipment can no longer
    // be rescheduled, canReschedule is false and the window is null.
    const closed = {
      canReschedule: false,
      rescheduleFrom: null,
      rescheduleTo: null
    };

    it.each([
      [STATUS_MESSAGE, { ...closed, status: "Delivered", reschedulesLeft: 2 }],
      [LIMIT_MESSAGE, { ...closed, reschedulesLeft: 0 }],
      [NO_ESTIMATE_MESSAGE, { ...closed, estimatedDelivery: null }],
      [WINDOW_MESSAGE, { ...closed, reschedulesLeft: 1 }]
    ])(
      "AC-003.1: the rejection '%s' with canReschedule false shows the exact text, hides the form and no success",
      async (message, serverDetails) => {
        getDeliveryDetails.mockResolvedValue(success(window1));
        rescheduleDelivery.mockResolvedValue({
          outcome: "REJECTED",
          message,
          details: details(serverDetails)
        });
        const element = render();

        await verify(element);
        await change(element, '[data-id="new-date"]', "2026-11-20");
        await click(element, '[data-id="reschedule"]');

        const error = query(element, '[data-id="reschedule-error"]');
        expect(text(error)).toBe(message);
        expect(error.getAttribute("role")).toBe("alert");
        expect(query(element, '[data-id="reschedule-form"]')).toBeNull();
        expect(query(element, '[data-id="reschedule-success"]')).toBeNull();
        expect(query(element, '[data-id="details"]')).not.toBeNull();
      }
    );

    it("AC-003.1: a window rejection while the window is still open keeps the form with the new bounds and the typed date", async () => {
      getDeliveryDetails.mockResolvedValue(success(window1));
      rescheduleDelivery.mockResolvedValue({
        outcome: "REJECTED",
        message: WINDOW_MESSAGE,
        details: details({
          ...window1,
          rescheduleFrom: "2026-11-21",
          rescheduleTo: "2026-11-27"
        })
      });
      const element = render();

      await verify(element);
      await change(element, '[data-id="new-date"]', "2026-11-20");
      await click(element, '[data-id="reschedule"]');

      expect(text(query(element, '[data-id="reschedule-error"]'))).toBe(
        WINDOW_MESSAGE
      );
      expect(query(element, '[data-id="reschedule-form"]')).not.toBeNull();
      expect(query(element, '[data-id="new-date"]').min).toBe("2026-11-21");
      expect(query(element, '[data-id="new-date"]').value).toBe("2026-11-20");
      expect(query(element, '[data-id="reschedule-success"]')).toBeNull();
    });

    it.each([
      ["", "no date"],
      ["2026-11-17", "a date before rescheduleFrom"],
      ["2026-11-28", "a date after rescheduleTo"]
    ])(
      "AC-003.1: %s (%s) makes no Apex call and names the window",
      async (newDate) => {
        getDeliveryDetails.mockResolvedValue(success(window1));
        const element = render();

        await verify(element);
        await change(element, '[data-id="new-date"]', newDate);
        await click(element, '[data-id="reschedule"]');

        expect(rescheduleDelivery).not.toHaveBeenCalled();
        expect(text(query(element, '[data-id="reschedule-error"]'))).toBe(
          "Choose a date between 2026-11-18 and 2026-11-27."
        );
      }
    );

    it("AC-002.1b: a lock during the reschedule hides the details and shows the lock text", async () => {
      getDeliveryDetails.mockResolvedValue(success(window1));
      rescheduleDelivery.mockResolvedValue({
        outcome: "LOCKED",
        message: LOCKED,
        details: null
      });
      const element = render();

      await verify(element);
      await change(element, '[data-id="new-date"]', "2026-11-20");
      await click(element, '[data-id="reschedule"]');

      expect(query(element, '[data-id="details"]')).toBeNull();
      expect(text(query(element, '[data-id="error"]'))).toBe(LOCKED);
    });

    it("AC-003.1: a thrown reschedule error shows the generic text", async () => {
      getDeliveryDetails.mockResolvedValue(success(window1));
      rescheduleDelivery.mockRejectedValue({
        body: { message: "FIELD_CUSTOM_VALIDATION_EXCEPTION" }
      });
      const element = render();

      await verify(element);
      await change(element, '[data-id="new-date"]', "2026-11-20");
      await click(element, '[data-id="reschedule"]');

      expect(text(query(element, '[data-id="reschedule-error"]'))).toBe(
        GENERIC_ERROR
      );
    });
  });

  describe("access code memory", () => {
    it("AC-002.8: the code is never written to localStorage, sessionStorage, a cookie or the URL", async () => {
      const setItem = jest.spyOn(Storage.prototype, "setItem");
      const pushState = jest.spyOn(window.history, "pushState");
      const replaceState = jest.spyOn(window.history, "replaceState");
      const hrefBefore = window.location.href;
      getDeliveryDetails.mockResolvedValue(
        success({ ...{ proofAvailable: true, status: "Delivered" } })
      );
      downloadProof.mockResolvedValue({
        outcome: "SUCCESS",
        proofAvailable: true,
        fileName: "proof.pdf",
        signedBy: "Ana",
        pdfBase64: PDF_BASE64
      });
      const element = render();

      await verify(element, "06050", "ABCD2345EFGH");
      await click(element, '[data-id="download-proof"]');

      expect(setItem).not.toHaveBeenCalled();
      expect(window.localStorage.length).toBe(0);
      expect(window.sessionStorage.length).toBe(0);
      expect(document.cookie).not.toMatch(/ABCD/i);
      expect(pushState).not.toHaveBeenCalled();
      expect(replaceState).not.toHaveBeenCalled();
      expect(window.location.href).toBe(hrefBefore);
    });

    it("AC-002.8: removing the component revokes the Blob URL and clears the code, the postal code and the details", async () => {
      getDeliveryDetails.mockResolvedValue(
        success({ status: "Delivered", proofAvailable: true })
      );
      downloadProof.mockResolvedValue({
        outcome: "SUCCESS",
        proofAvailable: true,
        fileName: "proof.pdf",
        signedBy: "Ana",
        pdfBase64: PDF_BASE64
      });
      const element = render();
      await verify(element, "06050", "ABCD2345EFGH");
      await click(element, '[data-id="download-proof"]');
      expect(revokeObjectURL).not.toHaveBeenCalled();

      document.body.removeChild(element);

      expect(revokeObjectURL).toHaveBeenCalledTimes(1);
      expect(revokeObjectURL).toHaveBeenCalledWith(
        "blob:https://rutacargo.example/1a2b"
      );
      // Re-attached, the same instance renders what it still holds in memory.
      document.body.appendChild(element);
      await flushPromises();
      expect(query(element, '[data-id="postal-code"]').value).toBe("");
      expect(query(element, '[data-id="access-code"]').value).toBe("");
      expect(query(element, '[data-id="details"]')).toBeNull();
      await click(element, '[data-id="verify"]');
      expect(getDeliveryDetails).toHaveBeenCalledTimes(1);
      expect(text(query(element, '[data-id="error"]'))).toBe(
        "Enter the destination postal code and the access code."
      );
    });

    it("AC-002.8: the bundle source has no storage, cookie, URL or HTML-injection sink", () => {
      const dir = path.resolve(__dirname, "..");
      const sources = fs
        .readdirSync(dir)
        .filter((name) => /\.(js|html)$/.test(name))
        .map((name) => fs.readFileSync(path.join(dir, name), "utf8"));

      expect(sources.length).toBeGreaterThanOrEqual(2);
      sources.forEach((source) => {
        expect(source).not.toMatch(
          /lwc:inner-html|innerHTML|outerHTML|insertAdjacentHTML|lwc:dom|localStorage|sessionStorage|document\.cookie|location\.|history\.|window\.open|data:/
        );
      });
    });

    it("AC-002.8: the CSS is one column by default and uses media queries only from 48em (768 px)", () => {
      const css = fs.readFileSync(
        path.resolve(__dirname, "..", "rcDeliveryDetails.css"),
        "utf8"
      );
      const base = css.split("@media")[0];

      expect(base).not.toMatch(/grid-template-columns:\s*(?!\s|1fr;)/);
      (css.match(/@media[^{]*/g) || []).forEach((media) => {
        expect(media.trim()).toBe("@media (min-width: 48em)");
      });
    });
  });
});
