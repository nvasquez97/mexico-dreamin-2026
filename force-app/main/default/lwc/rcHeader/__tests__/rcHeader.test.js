// Covers AC-F.10 (odd/tasks/foundation.md): the site header shows the brand
// marks from the rcBrandLogos static resource (the isotype for narrow screens
// and the full negative logo for wider ones, assumption A14), with alt text
// naming what they show, and a navigation landmark, and loads the Montserrat
// @font-face from the rcMontserrat static resource.
// Covers AC-005.5 (odd/tasks/req-005-customer-signup.md, header part): guests
// see "Log in" and "Sign up", logged-in users see only "Log out", which points
// to the site base path + /secur/logout.jsp.
import { createElement } from "lwc";
import RcHeader from "c/rcHeader";
import { loadStyle } from "lightning/platformResourceLoader";

const LOGOS_URL = "/rutacargo/sfsites/c/resource/1700000000000/rcBrandLogos";
const FONT_URL = "/rutacargo/sfsites/c/resource/1700000000000/rcMontserrat";
const BASE_PATH = "/rutacargo";
const LOGO_ALT = "Coffee Blazers Summit";

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
jest.mock(
  "@salesforce/user/isGuest",
  () => ({ __esModule: true, default: true }),
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
  basePath = BASE_PATH,
  isGuest = true
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
    jest.doMock(
      "@salesforce/user/isGuest",
      () => ({ __esModule: true, default: isGuest }),
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

  it("AC-F.10 (A14): shows the full logo logo-negative.png from the rcBrandLogos static resource, with alt text Coffee Blazers Summit", () => {
    const element = render();

    const logo = element.shadowRoot.querySelector("img.rc-header__logo");
    expect(logo.getAttribute("src")).toBe(`${LOGOS_URL}/logo-negative.png`);
    expect(logo.getAttribute("alt")).toBe(LOGO_ALT);
  });

  it("AC-F.10 (A14): shows the isotype isotype-tinto.png from the rcBrandLogos static resource, with alt text Coffee Blazers Summit", () => {
    const element = render();

    const isotype = element.shadowRoot.querySelector("img.rc-header__isotype");
    expect(isotype.getAttribute("src")).toBe(`${LOGOS_URL}/isotype-tinto.png`);
    expect(isotype.getAttribute("alt")).toBe(LOGO_ALT);
  });

  it("AC-F.10 (A14): shows exactly two brand images, the isotype and the full logo", () => {
    const element = render();

    const sources = Array.from(element.shadowRoot.querySelectorAll("img")).map(
      (img) => img.getAttribute("src")
    );
    expect(sources).toEqual([
      `${LOGOS_URL}/isotype-tinto.png`,
      `${LOGOS_URL}/logo-negative.png`
    ]);
  });

  it("AC-F.10: builds the logo URLs from the static resource URL the platform gives", () => {
    const { element } = renderWith({
      logosUrl: "/cargo/sfsites/c/resource/42/rcBrandLogos"
    });

    const sources = Array.from(element.shadowRoot.querySelectorAll("img")).map(
      (img) => img.getAttribute("src")
    );
    expect(sources).toEqual([
      "/cargo/sfsites/c/resource/42/rcBrandLogos/isotype-tinto.png",
      "/cargo/sfsites/c/resource/42/rcBrandLogos/logo-negative.png"
    ]);
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

    const hrefs = Array.from(
      element.shadowRoot.querySelectorAll(
        'a.rc-header__brand, nav[aria-label="Main"] a'
      )
    ).map((a) => a.getAttribute("href"));
    expect(hrefs).toEqual(["/shipping/", "/shipping/"]);
  });

  it("AC-F.10: both brand images link to the site home", () => {
    const element = render();

    const hrefs = Array.from(element.shadowRoot.querySelectorAll("img")).map(
      (img) => img.closest("a")?.getAttribute("href")
    );
    expect(hrefs).toEqual([`${BASE_PATH}/`, `${BASE_PATH}/`]);
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
    expect(
      element.shadowRoot
        .querySelector("img.rc-header__logo")
        .getAttribute("alt")
    ).toBe(LOGO_ALT);
    expect(element.shadowRoot.querySelector("nav")).not.toBeNull();
  });

  describe("AC-005.5: account links", () => {
    function accountLinks(element) {
      const nav = element.shadowRoot.querySelector('nav[aria-label="Account"]');
      expect(nav).not.toBeNull();
      return Array.from(nav.querySelectorAll("a")).map((a) => ({
        text: a.textContent.trim(),
        href: a.getAttribute("href")
      }));
    }

    it('AC-005.5: a guest sees "Log in" and "Sign up" and no "Log out"', () => {
      const element = render();

      expect(accountLinks(element)).toEqual([
        { text: "Log in", href: `${BASE_PATH}/login` },
        { text: "Sign up", href: `${BASE_PATH}/SelfRegister` }
      ]);
      expect(element.shadowRoot.textContent).not.toContain("Log out");
    });

    it('AC-005.5: a logged-in user sees only "Log out", to the site base path + /secur/logout.jsp', () => {
      const { element } = renderWith({ isGuest: false });

      expect(accountLinks(element)).toEqual([
        { text: "Log out", href: `${BASE_PATH}/secur/logout.jsp` }
      ]);
      expect(element.shadowRoot.textContent).not.toContain("Log in");
      expect(element.shadowRoot.textContent).not.toContain("Sign up");
    });

    it("AC-005.5: builds the account links from the site base path the platform gives", () => {
      const guest = renderWith({ basePath: "/shipping" }).element;
      const customer = renderWith({
        basePath: "/shipping",
        isGuest: false
      }).element;

      expect(accountLinks(guest).map((link) => link.href)).toEqual([
        "/shipping/login",
        "/shipping/SelfRegister"
      ]);
      expect(accountLinks(customer).map((link) => link.href)).toEqual([
        "/shipping/secur/logout.jsp"
      ]);
    });

    it("AC-005.5: keeps the Main navigation with its one Track link for logged-in users", () => {
      const { element } = renderWith({ isGuest: false });

      const links = element.shadowRoot.querySelectorAll(
        'nav[aria-label="Main"] a'
      );
      expect(Array.from(links).map((a) => a.textContent.trim())).toEqual([
        "Track"
      ]);
    });
  });
});
