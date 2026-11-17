// Covers AC-F.10 (NFR visual identity, odd/tasks/foundation.md): the site
// header is exposed to anonymous visitors on the public site, so its rendered
// DOM must pass the Sa11y accessibility rules (axe-core, WCAG A and AA base
// preset): alt text on both brand images, a named link and a named nav
// landmark.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcHeader from "c/rcHeader";

jest.mock(
  "@salesforce/resourceUrl/rcBrandLogos",
  () => ({
    __esModule: true,
    default: "/rutacargo/sfsites/c/resource/1700000000000/rcBrandLogos"
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/resourceUrl/rcMontserrat",
  () => ({
    __esModule: true,
    default: "/rutacargo/sfsites/c/resource/1700000000000/rcMontserrat"
  }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rutacargo" }),
  { virtual: true }
);

// Resolves after the pending promise callbacks (loadStyle) have run.
function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-rc-header accessibility", () => {
  beforeAll(() => {
    setup();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-F.10: the rendered header has no Sa11y (axe WCAG A/AA) violations", async () => {
    const element = createElement("c-rc-header", { is: RcHeader });
    document.body.appendChild(element);
    await flushPromises();

    // jest.config.js runs native shadow DOM, which axe walks from the host.
    await expect(element).toBeAccessible();
  });
});
