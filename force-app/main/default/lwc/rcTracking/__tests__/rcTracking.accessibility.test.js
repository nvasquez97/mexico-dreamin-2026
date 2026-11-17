// Covers AC-001.7 (odd/tasks/req-001-public-tracking.md): the public tracking
// component is exposed to anonymous visitors, so its rendered DOM must pass
// the Sa11y accessibility rules (axe-core, WCAG A and AA base preset) empty,
// with result cards, a "Not found" list and the truncation text, and with an
// error.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcTracking from "c/rcTracking";
import search from "@salesforce/apex/PublicTrackingController.search";

jest.mock(
  "@salesforce/apex/PublicTrackingController.search",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);

// Settles the mocked Apex promise chain (then, catch, finally) and the
// re-render it triggers: a few microtask turns, no timers.
function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function renderAndSearch(value) {
  const element = createElement("c-rc-tracking", { is: RcTracking });
  document.body.appendChild(element);
  await Promise.resolve();
  if (value !== undefined) {
    const area = element.shadowRoot.querySelector(
      'lightning-textarea[data-id="values"]'
    );
    area.dispatchEvent(new CustomEvent("change", { detail: { value } }));
    await Promise.resolve();
    element.shadowRoot
      .querySelector('lightning-button[data-id="search"]')
      .click();
    await flushPromises();
  }
  return element;
}

describe("c-rc-tracking accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    search.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-001.7: the empty search form has no Sa11y (axe WCAG A/AA) violations", async () => {
    const element = await renderAndSearch();

    await expect(element).toBeAccessible();
  });

  it("AC-001.7: result cards, the Not found list and the truncation text have no Sa11y violations", async () => {
    search.mockResolvedValue({
      results: [
        {
          trackingNumber: "RC000000001",
          status: "In transit",
          originCity: "Monterrey",
          destinationCity: "Guadalajara",
          lastLocation: "Saltillo hub",
          lastUpdate: "2026-11-20 10:00",
          estimatedDelivery: null
        }
      ],
      notFound: ["RC999999999"],
      truncated: true
    });
    const element = await renderAndSearch("RC000000001, RC999999999");

    expect(element.shadowRoot.querySelectorAll('[data-id="card"]').length).toBe(
      1
    );
    await expect(element).toBeAccessible();
  });

  it("AC-001.7: the generic error text has no Sa11y violations", async () => {
    search.mockRejectedValue(new TypeError("Failed to fetch"));
    const element = await renderAndSearch("RC000000001");

    expect(
      element.shadowRoot.querySelector('[data-id="error"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });
});
