// Covers AC-F.10 (odd/tasks/foundation.md): the public home page renders the
// "Track your shipment" hero as a labelled region of the page; its text points
// to the rcTracking search below it (AC-001.7, odd/tasks/req-001-public-tracking.md).
import { createElement } from "lwc";
import RcHome from "c/rcHome";

function render() {
  const element = createElement("c-rc-home", { is: RcHome });
  document.body.appendChild(element);
  return element;
}

describe("c-rc-home", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('AC-F.10: renders the title "Track your shipment" as the page heading', () => {
    const element = render();

    const headings = element.shadowRoot.querySelectorAll("h1");
    expect(headings.length).toBe(1);
    expect(headings[0].textContent.trim()).toBe("Track your shipment");
  });

  it("AC-F.10: the hero region is labelled by its heading", () => {
    const element = render();

    const region = element.shadowRoot.querySelector("section");
    const heading = element.shadowRoot.querySelector("h1");
    expect(region).not.toBeNull();
    expect(heading.id).not.toBe("");
    expect(region.getAttribute("aria-labelledby")).toBe(heading.id);
  });

  it("AC-F.10: renders a short text under the title", () => {
    const element = render();

    const text = element.shadowRoot.querySelector("section p");
    expect(text).not.toBeNull();
    expect(text.textContent.trim()).toBe(
      "Follow your cargo from pickup to delivery. Search by tracking number or order reference below."
    );
  });

  it("AC-F.10: adds no second main landmark, because the theme layout renders the <main>", () => {
    const element = render();

    expect(element.shadowRoot.querySelector('main, [role="main"]')).toBeNull();
  });
});
