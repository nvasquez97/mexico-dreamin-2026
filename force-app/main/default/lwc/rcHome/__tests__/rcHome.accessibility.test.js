// Covers AC-F.10 (NFR visual identity, odd/tasks/foundation.md): the public
// home hero is exposed to anonymous visitors on the public site, so its
// rendered DOM must pass the Sa11y accessibility rules (axe-core, WCAG A and
// AA base preset): a heading with text and a region labelled by it.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcHome from "c/rcHome";

describe("c-rc-home accessibility", () => {
  beforeAll(() => {
    setup();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-F.10: the rendered home hero has no Sa11y (axe WCAG A/AA) violations", async () => {
    const element = createElement("c-rc-home", { is: RcHome });
    document.body.appendChild(element);
    await Promise.resolve();

    await expect(element).toBeAccessible();
  });
});
