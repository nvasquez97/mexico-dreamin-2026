// Covers AC-F.10 (odd/tasks/foundation.md): the site header shows the brand
// logo from the rcBrandLogos static resource, with alt text, and a navigation
// landmark, and loads the Montserrat @font-face from the rcMontserrat static
// resource.
import { createElement } from "lwc";
import RcHeader from "c/rcHeader";
import { loadStyle } from "lightning/platformResourceLoader";

const LOGOS_URL = "/rutacargo/sfsites/c/resource/1700000000000/rcBrandLogos";
const FONT_URL = "/rutacargo/sfsites/c/resource/1700000000000/rcMontserrat";
const BASE_PATH = "/rutacargo";

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

function render(
  Component = RcHeader,
  create = createElement,
  tag = "c-rc-header"
) {
  const element = create(tag, { is: Component });
  document.body.appendChild(element);
  return element;
}

// Loads the component again with other values for its imports. The isolated
// registry has its own LWC engine, so the element is created with it, under a
// tag name that engine has not registered yet.
let isolatedRenders = 0;
function renderWith({
  logosUrl = LOGOS_URL,
  fontUrl = FONT_URL,
  basePath = BASE_PATH
}) {
  let Component;
  let create;
  let isolatedLoadStyle;
  jest.isolateModules(() => {
    jest.doMock(
      "@salesforce/resourceUrl/rcBrandLogos",
      () => ({ __esModule: true, default: logosUrl }),
      { virtual: true }
    );
    jest.doMock(
      "@salesforce/resourceUrl/rcMontserrat",
      () => ({ __esModule: true, default: fontUrl }),
      { virtual: true }
    );
    jest.doMock(
      "@salesforce/community/basePath",
      () => ({ __esModule: true, default: basePath }),
      { virtual: true }
    );
    create = require("lwc").createElement;
    isolatedLoadStyle = require("lightning/platformResourceLoader").loadStyle;
    Component = require("c/rcHeader").default;
  });
  isolatedRenders += 1;
  const element = render(
    Component,
    create,
    `c-rc-header-isolated-${isolatedRenders}`
  );
  return { element, loadStyle: isolatedLoadStyle };
}

// Resolves after the pending promise callbacks (loadStyle) have run.
function flushPromises() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-rc-header", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.resetModules();
  });

  it("AC-F.10: shows logo-negative.png from the rcBrandLogos static resource with alt text RutaCargo", () => {
    const element = render();

    const logos = element.shadowRoot.querySelectorAll("img");
    expect(logos.length).toBe(1);
    expect(logos[0].getAttribute("src")).toBe(`${LOGOS_URL}/logo-negative.png`);
    expect(logos[0].getAttribute("alt")).toBe("RutaCargo");
  });

  it("AC-F.10: builds the logo URL from the static resource URL the platform gives", () => {
    const { element } = renderWith({
      logosUrl: "/cargo/sfsites/c/resource/42/rcBrandLogos"
    });

    const logo = element.shadowRoot.querySelector("img");
    expect(logo.getAttribute("src")).toBe(
      "/cargo/sfsites/c/resource/42/rcBrandLogos/logo-negative.png"
    );
  });

  it("AC-F.10: renders a named nav landmark with a Track link to the site home", () => {
    const element = render();

    const nav = element.shadowRoot.querySelector("nav");
    expect(nav).not.toBeNull();
    expect(nav.getAttribute("aria-label")).toBe("Main");
    const links = nav.querySelectorAll("a");
    expect(links.length).toBe(1);
    expect(links[0].textContent.trim()).toBe("Track");
    expect(links[0].getAttribute("href")).toBe(`${BASE_PATH}/`);
  });

  it("AC-F.10: builds the home links from the site base path the platform gives", () => {
    const { element } = renderWith({ basePath: "/shipping" });

    const hrefs = Array.from(element.shadowRoot.querySelectorAll("a")).map(
      (a) => a.getAttribute("href")
    );
    expect(hrefs).toEqual(["/shipping/", "/shipping/"]);
  });

  it("AC-F.10: the logo links to the site home", () => {
    const element = render();

    const logoLink = element.shadowRoot.querySelector("img").closest("a");
    expect(logoLink).not.toBeNull();
    expect(logoLink.getAttribute("href")).toBe(`${BASE_PATH}/`);
  });

  it("AC-F.10: adds no second banner landmark, because the theme layout renders the <header>", () => {
    const element = render();

    expect(
      element.shadowRoot.querySelector('header, [role="banner"]')
    ).toBeNull();
  });

  it("AC-F.10: loads the Montserrat @font-face stylesheet from the rcMontserrat static resource", async () => {
    const element = render();
    await flushPromises();

    expect(loadStyle).toHaveBeenCalledTimes(1);
    expect(loadStyle.mock.calls[0][1]).toBe(`${FONT_URL}/montserrat.css`);
    expect(element.shadowRoot.querySelector(".rc-header").dataset.font).toBe(
      "loaded"
    );
  });

  it("AC-F.10: builds the font stylesheet URL from the static resource URL the platform gives", async () => {
    const { loadStyle: isolatedLoadStyle } = renderWith({
      fontUrl: "/cargo/sfsites/c/resource/42/rcMontserrat"
    });
    await flushPromises();

    expect(isolatedLoadStyle).toHaveBeenCalledTimes(1);
    expect(isolatedLoadStyle.mock.calls[0][1]).toBe(
      "/cargo/sfsites/c/resource/42/rcMontserrat/montserrat.css"
    );
  });

  it("AC-F.10: keeps the header working with the fallback font when the font stylesheet fails to load", async () => {
    loadStyle.mockRejectedValueOnce(new Error("blocked"));
    const element = render();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".rc-header").dataset.font).toBe(
      "fallback"
    );
    expect(element.shadowRoot.querySelector("img").getAttribute("alt")).toBe(
      "RutaCargo"
    );
    expect(element.shadowRoot.querySelector("nav")).not.toBeNull();
  });
});
