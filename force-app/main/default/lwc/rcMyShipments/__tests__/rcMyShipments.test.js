// Covers odd/tasks/req-006-007-customer-shipments.md, AC-007.4 (UI, list
// part): "My shipments" lists the customer's shipments as the server returns
// them (most recent first) as cards with the seven AC-007.1 fields, filters
// by a status of the closed Status__c list, searches by tracking number,
// recipient or reference (at most 50 characters, as the server), opens a
// detail by tracking number, renders every value as text, shows only the
// server's known messages, and is one column below 768 px.
import { createElement } from "lwc";
import RcMyShipments from "c/rcMyShipments";
import listShipments from "@salesforce/apex/MyShipmentsController.listShipments";

const fs = require("fs");
const path = require("path");

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

// The server's messages (MyShipmentsController, T2 8a322bd).
const NOT_AVAILABLE_MESSAGE =
  "This service is available only to signed-in customers.";
const INVALID_FILTER_MESSAGE = "Check the status filter and the search text.";
const GENERIC_MESSAGE =
  "We could not load your shipments. Please try again later.";
const SEARCH_MESSAGE = "Search with up to 50 characters.";

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

async function render(rows = ROWS) {
  listShipments.mockResolvedValue(rows);
  const element = createElement("c-rc-my-shipments", { is: RcMyShipments });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function query(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

function queryAll(element, selector) {
  return Array.from(element.shadowRoot.querySelectorAll(selector));
}

function text(node) {
  return node ? node.textContent.replace(/\s+/g, " ").trim() : null;
}

function cards(element) {
  return queryAll(element, 'li[data-id="card"]').map((card) => {
    const value = (name) => text(card.querySelector(`[data-field="${name}"]`));
    return {
      trackingNumber: value("trackingNumber"),
      requestDate: value("requestDate"),
      recipientName: value("recipientName"),
      destinationCity: value("destinationCity"),
      status: value("status"),
      serviceType: value("serviceType"),
      price: value("price")
    };
  });
}

async function chooseStatus(element, status) {
  const select = query(element, 'select[data-id="status"]');
  select.value = status;
  select.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
}

async function search(element, term) {
  query(element, 'input[data-id="search"]').value = term;
  query(element, 'form[data-id="filters"]').dispatchEvent(
    new CustomEvent("submit", { cancelable: true })
  );
  await flushPromises();
}

function serverError(message) {
  return { body: { message }, status: 500 };
}

// The active values of the Status__c picklist, read from its metadata.
function statusPicklist() {
  const xml = fs.readFileSync(
    path.join(
      __dirname,
      "../../../objects/Shipment__c/fields/Status__c.field-meta.xml"
    ),
    "utf8"
  );
  return Array.from(
    xml.matchAll(/<value>\s*<fullName>([^<]+)<\/fullName>/g)
  ).map((match) => match[1]);
}

describe("c-rc-my-shipments", () => {
  beforeEach(() => {
    listShipments.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.restoreAllMocks();
  });

  it("AC-007.4: loads every status with no search on open", async () => {
    await render();

    expect(listShipments).toHaveBeenCalledTimes(1);
    expect(listShipments).toHaveBeenCalledWith({ status: "", searchTerm: "" });
  });

  it("AC-007.4: shows one card per shipment, in the server's order, with the seven AC-007.1 fields", async () => {
    const element = await render();

    expect(cards(element)).toEqual([
      {
        trackingNumber: "RC000001060",
        requestDate: "2026-11-18 09:15",
        recipientName: "Laura Méndez",
        destinationCity: "Puebla",
        status: "Requested",
        serviceType: "Express",
        price: "310.00 MXN"
      },
      {
        trackingNumber: "RC000001059",
        requestDate: "2026-11-17 16:40",
        recipientName: "Jorge Ruiz",
        destinationCity: "Monterrey",
        status: "In transit",
        serviceType: "Standard",
        price: "1,870.00 MXN"
      }
    ]);
  });

  it("AC-007.4: each tracking number links to its detail page", async () => {
    const element = await render();

    const hrefs = queryAll(element, 'a[data-id="card-link"]').map((link) =>
      link.getAttribute("href")
    );
    expect(hrefs).toEqual([
      "/rutacargo/shipment-detail?tracking=RC000001060",
      "/rutacargo/shipment-detail?tracking=RC000001059"
    ]);
  });

  it("AC-007.4: the detail link encodes the tracking number", async () => {
    const element = await render([{ ...ROWS[0], trackingNumber: "RC1&x=<y>" }]);

    expect(query(element, 'a[data-id="card-link"]').getAttribute("href")).toBe(
      "/rutacargo/shipment-detail?tracking=RC1%26x%3D%3Cy%3E"
    );
  });

  it("AC-007.4: announces how many shipments are shown", async () => {
    const two = await render();
    expect(text(query(two, '[data-id="summary"]'))).toBe("2 shipments");

    document.body.removeChild(two);
    const one = await render([ROWS[0]]);
    expect(text(query(one, '[data-id="summary"]'))).toBe("1 shipment");
  });

  it("AC-007.4: the status filter offers All statuses and exactly the Status__c picklist values", async () => {
    const element = await render();

    const options = queryAll(element, 'select[data-id="status"] option').map(
      (option) => ({ value: option.value, label: text(option) })
    );
    expect(options[0]).toEqual({ value: "", label: "All statuses" });
    expect(options.slice(1).map((option) => option.value)).toEqual(
      statusPicklist()
    );
    expect(statusPicklist().length).toBe(6);
  });

  it('AC-007.4: choosing "In transit" reloads with that status', async () => {
    const element = await render();
    listShipments.mockResolvedValue([ROWS[1]]);

    await chooseStatus(element, "In transit");

    expect(listShipments).toHaveBeenLastCalledWith({
      status: "In transit",
      searchTerm: ""
    });
    expect(cards(element).map((card) => card.trackingNumber)).toEqual([
      "RC000001059"
    ]);
  });

  it('AC-007.4: choosing "Delivered" reloads with that status', async () => {
    const element = await render();
    listShipments.mockResolvedValue([]);

    await chooseStatus(element, "Delivered");

    expect(listShipments).toHaveBeenLastCalledWith({
      status: "Delivered",
      searchTerm: ""
    });
  });

  it("AC-007.4: a search sends the trimmed term with the chosen status", async () => {
    const element = await render();
    await chooseStatus(element, "Requested");
    listShipments.mockResolvedValue([ROWS[0]]);

    await search(element, "  laura ");

    expect(listShipments).toHaveBeenLastCalledWith({
      status: "Requested",
      searchTerm: "laura"
    });
    expect(cards(element).map((card) => card.trackingNumber)).toEqual([
      "RC000001060"
    ]);
  });

  it("AC-007.4: a search by tracking prefix sends it as typed", async () => {
    const element = await render();

    await search(element, "RC00000100");

    expect(listShipments).toHaveBeenLastCalledWith({
      status: "",
      searchTerm: "RC00000100"
    });
  });

  it("AC-007.4: a search of 50 characters is sent, 51 is refused on the client", async () => {
    const element = await render();

    await search(element, "a".repeat(50));
    expect(listShipments).toHaveBeenLastCalledWith({
      status: "",
      searchTerm: "a".repeat(50)
    });
    const calls = listShipments.mock.calls.length;

    await search(element, "a".repeat(51));
    expect(listShipments.mock.calls.length).toBe(calls);
    expect(text(query(element, '[data-error="search"]'))).toBe(SEARCH_MESSAGE);
    expect(
      query(element, 'input[data-id="search"]').getAttribute("aria-invalid")
    ).toBe("true");
  });

  it("AC-007.4: with no shipments, says so and links to the request page", async () => {
    const element = await render([]);

    expect(text(query(element, '[data-id="empty"]'))).toBe(
      "You have no shipments yet."
    );
    expect(text(query(element, '[data-id="summary"]'))).toBe("0 shipments");
    expect(
      query(element, 'a[data-id="request-link"]').getAttribute("href")
    ).toBe("/rutacargo/request-shipment");
  });

  it("AC-007.4: with a filter and no match, says no shipment matches", async () => {
    const element = await render();
    listShipments.mockResolvedValue([]);

    await search(element, "nobody");

    expect(text(query(element, '[data-id="empty"]'))).toBe(
      "No shipments match your filter."
    );
    expect(queryAll(element, 'li[data-id="card"]').length).toBe(0);
  });

  it.each([[INVALID_FILTER_MESSAGE], [NOT_AVAILABLE_MESSAGE]])(
    "AC-007.4: the server's known message is shown as text: %s",
    async (message) => {
      listShipments.mockRejectedValue(serverError(message));
      const element = createElement("c-rc-my-shipments", { is: RcMyShipments });
      document.body.appendChild(element);
      await flushPromises();

      expect(text(query(element, '[data-id="error"]'))).toBe(message);
      expect(queryAll(element, 'li[data-id="card"]').length).toBe(0);
    }
  );

  it("AC-007.4: an unknown server text is never shown", async () => {
    listShipments.mockRejectedValue(
      serverError("System.QueryException: No such column 'Carrier_Cost__c'")
    );
    const element = createElement("c-rc-my-shipments", { is: RcMyShipments });
    document.body.appendChild(element);
    await flushPromises();

    expect(text(query(element, '[data-id="error"]'))).toBe(GENERIC_MESSAGE);
    expect(element.shadowRoot.textContent).not.toContain("QueryException");
  });

  it("AC-007.4: a slower earlier answer never replaces a later one", async () => {
    const element = await render();
    let resolveFirst;
    listShipments.mockReturnValueOnce(
      new Promise((done) => {
        resolveFirst = done;
      })
    );
    listShipments.mockResolvedValueOnce([ROWS[1]]);

    await chooseStatus(element, "Requested");
    await chooseStatus(element, "In transit");
    resolveFirst([ROWS[0]]);
    await flushPromises();

    expect(cards(element).map((card) => card.trackingNumber)).toEqual([
      "RC000001059"
    ]);
  });

  it("AC-007.4: server values are rendered as text, never as markup", async () => {
    const element = await render([
      { ...ROWS[0], recipientName: '<img src="x" onerror="alert(1)">' }
    ]);

    expect(element.shadowRoot.querySelector("img")).toBeNull();
    expect(cards(element)[0].recipientName).toBe(
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

    it("AC-007.4: the cards are one column below 768 px and take more only from 48em", () => {
      const css = fs.readFileSync(path.join(dir, "rcMyShipments.css"), "utf8");
      const outsideWideQuery = css.replace(
        /@media \(min-width: 48em\) \{[\s\S]*?\n\}/g,
        ""
      );

      expect(css).toMatch(
        /@media \(min-width: 48em\)\s*\{[^@]*\.rc-shipments__cards\s*\{[^}]*grid-template-columns:\s*repeat\(2, 1fr\)/
      );
      expect(outsideWideQuery).not.toMatch(
        /grid-template-columns:\s*(repeat\(\s*[2-9]|[^;]*fr[^;]*fr)/
      );
      expect(outsideWideQuery).not.toMatch(/flex-direction:\s*row/);
    });

    it("AC-007.4: brand: labels are Montserrat Medium (500) and links are underlined through the DXP hook", () => {
      const css = fs.readFileSync(path.join(dir, "rcMyShipments.css"), "utf8");

      expect(css).toMatch(/\.rc-shipments__label\s*\{[^}]*font-weight:\s*500/);
      expect(css).toMatch(
        /\.rc-shipments\s*\{[^}]*--dxp-c-link-text-decoration:\s*underline/
      );
      expect(css).not.toMatch(/#ff3636|#ffc91d/i);
    });
  });
});
