// Covers odd/tasks/req-001-public-tracking.md, the LWC parts of AC-001.1
// (client split, de-duplication and the 10-value cap), AC-001.3 (the "Not
// found" list and the truncation text), AC-001.4 (client-side sorting) and
// AC-001.7 (result cards, generic errors, text-only rendering).
import { createElement } from "lwc";
import RcTracking from "c/rcTracking";
import search from "@salesforce/apex/PublicTrackingController.search";

const fs = require("fs");
const path = require("path");

jest.mock(
  "@salesforce/apex/PublicTrackingController.search",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);

const GENERIC_ERROR = "We could not complete the search. Please try again.";
const CAP_ERROR = "Enter up to 10 values.";
const TRUNCATION_TEXT = "Showing the first 50 results. Narrow your search.";

function render() {
  const element = createElement("c-rc-tracking", { is: RcTracking });
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

async function chooseMode(element, mode) {
  const group = query(element, 'lightning-radio-group[data-id="mode"]');
  group.dispatchEvent(new CustomEvent("change", { detail: { value: mode } }));
  await Promise.resolve();
}

async function typeValues(element, value) {
  const area = query(element, 'lightning-textarea[data-id="values"]');
  area.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await Promise.resolve();
}

async function clickSearch(element) {
  query(element, 'lightning-button[data-id="search"]').click();
  await flushPromises();
}

async function sortBy(element, value) {
  const select = query(element, 'lightning-combobox[data-id="sort"]');
  select.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await Promise.resolve();
}

async function searchFor(element, value, mode) {
  if (mode) {
    await chooseMode(element, mode);
  }
  await typeValues(element, value);
  await clickSearch(element);
}

function shipment(overrides) {
  return {
    trackingNumber: "RC000000001",
    status: "In transit",
    originCity: "Monterrey",
    destinationCity: "Guadalajara",
    lastLocation: "Saltillo hub",
    lastUpdate: "2026-11-20 10:00",
    estimatedDelivery: "2026-11-22",
    ...overrides
  };
}

function response(results = [], notFound = [], truncated = false) {
  return { results, notFound, truncated };
}

function cardNumbers(element) {
  return queryAll(element, '[data-id="card-number"]').map(text);
}

function cardField(card, name) {
  return text(card.querySelector(`[data-field="${name}"]`));
}

function errorText(element) {
  return text(query(element, '[data-id="error"]'));
}

function values(count, prefix = "RC") {
  return Array.from(
    { length: count },
    (unused, index) => `${prefix}${String(index + 1).padStart(9, "0")}`
  );
}

describe("c-rc-tracking", () => {
  beforeEach(() => {
    search.mockReset();
    search.mockResolvedValue(response());
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  describe("AC-001.1 client: split, de-duplicate, 10-value cap", () => {
    it('AC-001.1: the textarea value "A, B\\nC" becomes 3 values sent in tracking mode', async () => {
      const element = render();

      await searchFor(element, "A, B\nC");

      expect(search).toHaveBeenCalledTimes(1);
      expect(search).toHaveBeenCalledWith({
        mode: "TRACKING_NUMBER",
        values: ["A", "B", "C"]
      });
    });

    it("AC-001.1: commas, CRLF and blank lines split, values are trimmed and empties dropped", async () => {
      const element = render();

      await searchFor(
        element,
        " RC000000007 ,\r\n\n RC000000008,,RC000000009 \n"
      );

      expect(search).toHaveBeenCalledWith({
        mode: "TRACKING_NUMBER",
        values: ["RC000000007", "RC000000008", "RC000000009"]
      });
    });

    it("AC-001.1: the Order reference choice sends the REFERENCE mode", async () => {
      const element = render();

      await searchFor(element, "PO-7781", "REFERENCE");

      expect(search).toHaveBeenCalledWith({
        mode: "REFERENCE",
        values: ["PO-7781"]
      });
    });

    it("AC-001.1: exactly 10 distinct values are accepted and sent", async () => {
      const element = render();
      const ten = values(10);

      await searchFor(element, ten.join("\n"));

      expect(search).toHaveBeenCalledWith({
        mode: "TRACKING_NUMBER",
        values: ten
      });
      expect(errorText(element)).toBeNull();
    });

    it('AC-001.1: 11 distinct values show "Enter up to 10 values" and make no Apex call', async () => {
      const element = render();

      await searchFor(element, values(11).join(", "));

      expect(search).not.toHaveBeenCalled();
      expect(errorText(element)).toBe(CAP_ERROR);
    });

    it("AC-001.1: 11 raw entries with one case-insensitive duplicate are sent as 10, first spelling kept", async () => {
      const element = render();
      const ten = values(10, "po-");
      const raw = [...ten.slice(0, 5), "PO-000000003", ...ten.slice(5)];

      await searchFor(element, raw.join("\n"), "REFERENCE");

      expect(search).toHaveBeenCalledWith({ mode: "REFERENCE", values: ten });
      expect(errorText(element)).toBeNull();
    });

    it("AC-001.1: an input with no value makes no Apex call", async () => {
      const element = render();

      await searchFor(element, " ,\n , ");

      expect(search).not.toHaveBeenCalled();
      expect(errorText(element)).toBe("Enter at least one value.");
    });
  });

  describe("AC-001.3 client: Not found and truncation", () => {
    it('AC-001.3: lists the notFound values under "Not found" in the order received', async () => {
      search.mockResolvedValue(
        response([shipment()], ["RC999999999", "ABC", "RC12"])
      );
      const element = render();

      await searchFor(element, "RC000000001, RC999999999, ABC, RC12");

      const section = query(element, '[data-id="not-found"]');
      expect(text(section.querySelector("h3"))).toBe("Not found");
      expect(queryAll(element, '[data-id="not-found"] li').map(text)).toEqual([
        "RC999999999",
        "ABC",
        "RC12"
      ]);
    });

    it("AC-001.3: a second notFound list renders its own values", async () => {
      search.mockResolvedValue(response([], ["PO-1", "PO-2"]));
      const element = render();

      await searchFor(element, "PO-1\nPO-2", "REFERENCE");

      expect(queryAll(element, '[data-id="not-found"] li').map(text)).toEqual([
        "PO-1",
        "PO-2"
      ]);
    });

    it('AC-001.3: no "Not found" list when every value was found', async () => {
      search.mockResolvedValue(response([shipment()], []));
      const element = render();

      await searchFor(element, "RC000000001");

      expect(query(element, '[data-id="not-found"]')).toBeNull();
    });

    it("AC-001.3: shows the truncation text when truncated is true", async () => {
      search.mockResolvedValue(response([shipment()], [], true));
      const element = render();

      await searchFor(element, "PO-7781", "REFERENCE");

      expect(text(query(element, '[data-id="truncated"]'))).toBe(
        TRUNCATION_TEXT
      );
    });

    it("AC-001.3: no truncation text when truncated is false", async () => {
      search.mockResolvedValue(response([shipment()], [], false));
      const element = render();

      await searchFor(element, "PO-7781", "REFERENCE");

      expect(query(element, '[data-id="truncated"]')).toBeNull();
    });
  });

  describe("AC-001.4: client-side sorting", () => {
    const AC_RESULTS = [
      shipment({
        trackingNumber: "RC000000001",
        status: "Delivered",
        estimatedDelivery: "2026-11-25"
      }),
      shipment({
        trackingNumber: "RC000000002",
        status: "Requested",
        estimatedDelivery: null
      }),
      shipment({
        trackingNumber: "RC000000003",
        status: "In transit",
        estimatedDelivery: "2026-11-21"
      })
    ];

    it("AC-001.4: by Status the order is Requested, In transit, Delivered", async () => {
      search.mockResolvedValue(response(AC_RESULTS));
      const element = render();
      await searchFor(element, "RC000000001, RC000000002, RC000000003");

      await sortBy(element, "STATUS");

      expect(
        queryAll(element, '[data-id="card"]').map((c) => cardField(c, "status"))
      ).toEqual(["Requested", "In transit", "Delivered"]);
    });

    it("AC-001.4: by Status every lifecycle value follows the picklist order, not the alphabet", async () => {
      const lifecycle = [
        "Requested",
        "Picked up",
        "In transit",
        "Out for delivery",
        "Delivered",
        "Exception"
      ];
      const shuffled = [5, 2, 0, 4, 1, 3].map((i, n) =>
        shipment({
          trackingNumber: `RC00000001${n}`,
          status: lifecycle[i]
        })
      );
      search.mockResolvedValue(response(shuffled));
      const element = render();
      await searchFor(element, "PO-7781", "REFERENCE");

      await sortBy(element, "STATUS");

      expect(
        queryAll(element, '[data-id="card"]').map((c) => cardField(c, "status"))
      ).toEqual(lifecycle);
    });

    it("AC-001.4: by Estimated delivery the order is 2026-11-21, 2026-11-25, empty last", async () => {
      search.mockResolvedValue(response(AC_RESULTS));
      const element = render();
      await searchFor(element, "RC000000001, RC000000002, RC000000003");

      await sortBy(element, "ESTIMATED_DELIVERY");

      expect(cardNumbers(element)).toEqual([
        "RC000000003",
        "RC000000001",
        "RC000000002"
      ]);
    });

    it("AC-001.4: by Estimated delivery a second set sorts ascending across months, empties last", async () => {
      search.mockResolvedValue(
        response([
          shipment({ trackingNumber: "RC000000004", estimatedDelivery: "" }),
          shipment({
            trackingNumber: "RC000000005",
            estimatedDelivery: "2026-12-01"
          }),
          shipment({
            trackingNumber: "RC000000006",
            estimatedDelivery: "2026-11-30"
          })
        ])
      );
      const element = render();
      await searchFor(element, "PO-1", "REFERENCE");

      await sortBy(element, "ESTIMATED_DELIVERY");

      expect(cardNumbers(element)).toEqual([
        "RC000000006",
        "RC000000005",
        "RC000000004"
      ]);
    });

    it("AC-001.4: the sort selector offers Status and Estimated delivery", async () => {
      search.mockResolvedValue(response(AC_RESULTS));
      const element = render();
      await searchFor(element, "RC000000001");

      const select = query(element, 'lightning-combobox[data-id="sort"]');
      expect(select.options.map((o) => [o.label, o.value])).toEqual([
        ["Status", "STATUS"],
        ["Estimated delivery", "ESTIMATED_DELIVERY"]
      ]);
    });
  });

  describe("AC-001.7: result cards, generic errors, text-only rendering", () => {
    it("AC-001.7: a result card shows the seven labelled fields as received", async () => {
      search.mockResolvedValue(response([shipment()]));
      const element = render();

      await searchFor(element, "RC000000001");

      const cards = queryAll(element, '[data-id="card"]');
      expect(cards.length).toBe(1);
      const labels = Array.from(cards[0].querySelectorAll("dt")).map(text);
      expect(labels).toEqual([
        "Status",
        "Origin city",
        "Destination city",
        "Last location",
        "Last update",
        "Estimated delivery"
      ]);
      const title = cards[0].querySelector("h3");
      expect(title.querySelector('[data-id="card-label"]').textContent).toBe(
        "Tracking number"
      );
      expect(cardField(cards[0], "trackingNumber")).toBe("RC000000001");
      expect(cardField(cards[0], "status")).toBe("In transit");
      expect(cardField(cards[0], "originCity")).toBe("Monterrey");
      expect(cardField(cards[0], "destinationCity")).toBe("Guadalajara");
      expect(cardField(cards[0], "lastLocation")).toBe("Saltillo hub");
      expect(cardField(cards[0], "lastUpdate")).toBe("2026-11-20 10:00");
      expect(cardField(cards[0], "estimatedDelivery")).toBe("2026-11-22");
    });

    it("AC-001.7: a second result shows its own values and a missing date as Not available", async () => {
      search.mockResolvedValue(
        response([
          shipment({
            trackingNumber: "RC000000042",
            status: "Exception",
            originCity: "Puebla",
            destinationCity: "Mérida",
            lastLocation: null,
            lastUpdate: "2026-11-20 21:00",
            estimatedDelivery: null
          })
        ])
      );
      const element = render();

      await searchFor(element, "RC000000042");

      const card = query(element, '[data-id="card"]');
      expect(cardField(card, "trackingNumber")).toBe("RC000000042");
      expect(cardField(card, "status")).toBe("Exception");
      expect(cardField(card, "originCity")).toBe("Puebla");
      expect(cardField(card, "destinationCity")).toBe("Mérida");
      expect(cardField(card, "lastLocation")).toBe("Not available");
      expect(cardField(card, "lastUpdate")).toBe("2026-11-20 21:00");
      expect(cardField(card, "estimatedDelivery")).toBe("Not available");
    });

    it("AC-001.7: the result count is announced in a polite live region", async () => {
      search.mockResolvedValue(
        response([shipment(), shipment({ trackingNumber: "RC000000002" })])
      );
      const element = render();

      await searchFor(element, "RC000000001, RC000000002");

      const status = query(element, '[data-id="summary"]');
      expect(status.getAttribute("aria-live")).toBe("polite");
      expect(text(status)).toBe("2 shipments found.");
    });

    it("AC-001.7: a known server message is shown as sent (cap message)", async () => {
      search.mockRejectedValue({ body: { message: CAP_ERROR }, status: 500 });
      const element = render();

      await searchFor(element, "RC000000001");

      expect(errorText(element)).toBe(CAP_ERROR);
    });

    const FAILURES = [
      [
        "an AuraHandledException with the generic message",
        { body: { message: GENERIC_ERROR }, status: 500 }
      ],
      [
        "an error body with an unknown message",
        { body: { message: "System.QueryException: secret detail" } }
      ],
      [
        "an error body with page errors only",
        { body: { pageErrors: [{ message: "internal" }] } }
      ],
      ["a network error", new TypeError("Failed to fetch")],
      ["an unexpected string", "boom"],
      ["undefined", undefined]
    ];

    it.each(FAILURES)(
      "AC-001.7: a failed call with %s shows the generic error text",
      async (label, failure) => {
        search.mockRejectedValue(failure);
        const element = render();

        await searchFor(element, "RC000000001");

        const error = query(element, '[data-id="error"]');
        expect(error.getAttribute("role")).toBe("alert");
        expect(text(error)).toBe(GENERIC_ERROR);
        expect(queryAll(element, '[data-id="card"]').length).toBe(0);
      }
    );

    it.each([
      ["null", null],
      ["an object without lists", { results: "x" }],
      ["a list of results without notFound", { results: [] }]
    ])(
      "AC-001.7: a success with an unexpected shape (%s) shows the generic error text",
      async (label, payload) => {
        search.mockResolvedValue(payload);
        const element = render();

        await searchFor(element, "RC000000001");

        expect(errorText(element)).toBe(GENERIC_ERROR);
      }
    );

    it("AC-001.7: a new search clears the previous error", async () => {
      search.mockRejectedValueOnce(new TypeError("Failed to fetch"));
      search.mockResolvedValueOnce(response([shipment()]));
      const element = render();

      await searchFor(element, "RC000000001");
      await clickSearch(element);

      expect(errorText(element)).toBeNull();
      expect(cardNumbers(element)).toEqual(["RC000000001"]);
    });

    it("AC-001.7: typed and returned values render only as text, never as markup", async () => {
      const typed = '<img src=x onerror="alert(1)">';
      search.mockResolvedValue(
        response([shipment({ lastLocation: "<b>Hub</b>" })], [typed])
      );
      const element = render();

      await searchFor(element, typed);

      expect(queryAll(element, '[data-id="not-found"] li').map(text)).toEqual([
        typed
      ]);
      expect(
        cardField(query(element, '[data-id="card"]'), "lastLocation")
      ).toBe("<b>Hub</b>");
      expect(element.shadowRoot.querySelector("img, b")).toBeNull();
    });

    it('AC-001.7: the bundle source has no lwc:inner-html, innerHTML or lwc:dom="manual"', () => {
      const dir = path.resolve(__dirname, "..");
      const sources = fs
        .readdirSync(dir)
        .filter((name) => /\.(js|html)$/.test(name))
        .map((name) => fs.readFileSync(path.join(dir, name), "utf8"));

      expect(sources.length).toBeGreaterThanOrEqual(2);
      sources.forEach((source) => {
        expect(source).not.toMatch(/lwc:inner-html|innerHTML|lwc:dom/);
      });
    });

    it("AC-001.7: the CSS is one column by default and adds columns only from 48em (768 px)", () => {
      const css = fs.readFileSync(
        path.resolve(__dirname, "..", "rcTracking.css"),
        "utf8"
      );
      const base = css.split("@media")[0];

      expect(base).toMatch(
        /\.rc-tracking__cards\s*\{[^}]*grid-template-columns:\s*1fr;/
      );
      expect(css).toMatch(
        /@media \(min-width: 48em\)\s*\{[^@]*\.rc-tracking__cards\s*\{[^}]*grid-template-columns:\s*repeat\(2, 1fr\)/
      );
    });
  });
});
