import { createElement } from "lwc";
import RcTracking from "c/rcTracking";
import track from "@salesforce/apex/PublicTrackingController.track";

jest.mock(
  "@salesforce/apex/PublicTrackingController.track",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("@salesforce/community/basePath", () => ({ default: "/rutacargo" }), {
  virtual: true
});

const RESULTS = [
  {
    key: "a",
    searchValue: "RC000000003",
    found: true,
    trackingNumber: "RC000000003",
    status: "Delivered",
    statusOrder: 4,
    estimatedDelivery: "2026-11-10"
  },
  { key: "b", searchValue: "RC000000099", found: false, statusOrder: 7 },
  {
    key: "c",
    searchValue: "RC000000001",
    found: true,
    trackingNumber: "RC000000001",
    status: "In transit",
    statusOrder: 2,
    estimatedDelivery: "2026-11-25"
  },
  {
    key: "d",
    searchValue: "RC000000002",
    found: true,
    trackingNumber: "RC000000002",
    status: "Requested",
    statusOrder: 0,
    estimatedDelivery: "2026-11-30"
  }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function trackingOrder(element) {
  return [...element.shadowRoot.querySelectorAll(".result .tracking")].map(
    (n) => n.textContent
  );
}

async function search(element, value) {
  const textarea = element.shadowRoot.querySelector("lightning-textarea");
  textarea.value = value;
  textarea.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  textarea.reportValidity = () => true;
  textarea.setCustomValidity = () => {};
  element.shadowRoot
    .querySelector("form")
    .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
  await flush();
  await flush();
}

describe("c-rc-tracking", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("AC-001.1/AC-001.3: sends the values and lists not found ones", async () => {
    track.mockResolvedValue(RESULTS);
    const element = createElement("c-rc-tracking", { is: RcTracking });
    document.body.appendChild(element);
    await search(element, "RC000000003, RC000000099\nRC000000001,RC000000002");
    expect(track).toHaveBeenCalledWith({
      searchBy: "TRACKING",
      searchText: "RC000000003, RC000000099\nRC000000001,RC000000002"
    });
    expect(
      element.shadowRoot.querySelectorAll(".rc-status_not-found").length
    ).toBe(1);
  });

  it("AC-001.4: sorts by status (lifecycle order, not found last) and by estimated delivery", async () => {
    track.mockResolvedValue(RESULTS);
    const element = createElement("c-rc-tracking", { is: RcTracking });
    document.body.appendChild(element);
    await search(element, "RC000000003,RC000000099,RC000000001,RC000000002");
    expect(trackingOrder(element)).toEqual([
      "RC000000002",
      "RC000000001",
      "RC000000003",
      "RC000000099"
    ]);

    const sort = element.shadowRoot.querySelector("lightning-combobox");
    sort.dispatchEvent(
      new CustomEvent("change", { detail: { value: "estimatedDelivery" } })
    );
    await flush();
    expect(trackingOrder(element)).toEqual([
      "RC000000003",
      "RC000000001",
      "RC000000002",
      "RC000000099"
    ]);
  });

  it("rejects more than 10 values before calling the server", async () => {
    const element = createElement("c-rc-tracking", { is: RcTracking });
    document.body.appendChild(element);
    const textarea = element.shadowRoot.querySelector("lightning-textarea");
    const values = Array.from({ length: 11 }, (_, i) => `RC00000000${i}`).join(
      ","
    );
    textarea.dispatchEvent(
      new CustomEvent("change", { detail: { value: values } })
    );
    textarea.reportValidity = () => false;
    textarea.setCustomValidity = jest.fn();
    element.shadowRoot
      .querySelector("form")
      .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
    await flush();
    expect(textarea.setCustomValidity).toHaveBeenCalledWith(
      "You can search up to 10 values at a time."
    );
    expect(track).not.toHaveBeenCalled();
  });
});
