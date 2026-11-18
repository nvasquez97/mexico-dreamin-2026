/**
 * @jest-environment-options {"url": "https://rutacargo-test.my.site.com/rutacargo/login"}
 */
// The page runs on an https site origin (as the published site does), so the
// redirect rule "same origin only" (F13, X4) can be tested.
// Covers odd/tasks/req-005-customer-signup.md, the login form of S4 and
// AC-005.9 (labels and errors as text only, the password never logged or
// stored, one column below 768 px), with the client side of AC-005.5: the
// startURL of the page is sent only from the closed list, the one failure
// message is shown, and the whole page opens the redirect URL of the server.
import { createElement } from "lwc";
import RcLogin from "c/rcLogin";
import login from "@salesforce/apex/CustomerLoginController.login";

// Test values of the password rule (AC-005.4), not credentials.
const VALID_PASS = "abcd12345X";

const fs = require("fs");
const path = require("path");

jest.mock(
  "@salesforce/apex/CustomerLoginController.login",
  () => ({ __esModule: true, default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/community/basePath",
  () => ({ __esModule: true, default: "/rutacargo" }),
  { virtual: true }
);
// Records every NavigationMixin.Navigate call (the stub of sfdx-lwc-jest
// records nothing).
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const mockNavigate = jest.fn();
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageReference, replace) {
        mockNavigate(pageReference, replace);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { __esModule: true, NavigationMixin, mockNavigate };
});

const { mockNavigate } = require("lightning/navigation");

const LOGIN_FAILED_MESSAGE = "Your email or password is incorrect.";
const GENERIC_ERROR = "We could not log you in. Please try again later.";
const MESSAGE_EMAIL = "Enter your email address.";
const MESSAGE_PASSWORD = "Enter your password.";
const SITE_ORIGIN = "https://rutacargo-test.my.site.com";
const REDIRECT_A = `${SITE_ORIGIN}/rutacargo/secur/frontdoor.jsp?sid=TOKEN_A`;
const REDIRECT_B = "/rutacargo/secur/frontdoor.jsp?sid=TOKEN_B";

function render() {
  const element = createElement("c-rc-login", { is: RcLogin });
  document.body.appendChild(element);
  return element;
}

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

function query(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

function text(node) {
  return node ? node.textContent.replace(/\s+/g, " ").trim() : null;
}

function errorOf(element, field) {
  return text(query(element, `[data-error="${field}"]`));
}

async function logIn(values) {
  const element = render();
  Object.entries(values).forEach(([field, value]) => {
    query(element, `[data-field="${field}"]`).value = value;
  });
  query(element, 'form[data-id="form"]').dispatchEvent(
    new CustomEvent("submit", { cancelable: true })
  );
  await flushPromises();
  return element;
}

function openPage(search) {
  window.history.replaceState({}, "", `/rutacargo/login${search}`);
}

const ANA = { email: "Ana.Lopez@Example.com", password: VALID_PASS };

describe("c-rc-login", () => {
  beforeEach(() => {
    login.mockReset();
    mockNavigate.mockReset();
    login.mockResolvedValue({
      success: false,
      redirectUrl: null,
      message: LOGIN_FAILED_MESSAGE
    });
    openPage("");
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-005.9: asks for the email and the password, each with a label", () => {
    const element = render();

    const fields = ["email", "password"].map((field) => {
      const input = query(element, `[data-field="${field}"]`);
      return {
        type: input.type,
        autocomplete: input.getAttribute("autocomplete"),
        label: text(query(element, `label[for="${input.id}"]`))
      };
    });
    expect(fields).toEqual([
      { type: "email", autocomplete: "email", label: "Email" },
      { type: "password", autocomplete: "current-password", label: "Password" }
    ]);
  });

  it('AC-005.9: links "Forgot your password?" and "Sign up" to the site pages', () => {
    const element = render();

    const forgot = query(element, 'a[data-id="forgot-link"]');
    const signUp = query(element, 'a[data-id="sign-up-link"]');
    expect([text(forgot), forgot.getAttribute("href")]).toEqual([
      "Forgot your password?",
      "/rutacargo/ForgotPassword"
    ]);
    expect([text(signUp), signUp.getAttribute("href")]).toEqual([
      "Sign up",
      "/rutacargo/SelfRegister"
    ]);
  });

  it("AC-005.9: an empty form shows an error under each field and calls nothing", async () => {
    const element = await logIn({});

    expect(errorOf(element, "email")).toBe(MESSAGE_EMAIL);
    expect(errorOf(element, "password")).toBe(MESSAGE_PASSWORD);
    expect(login).not.toHaveBeenCalled();
  });

  it("AC-005.9: an email of only spaces is empty", async () => {
    const element = await logIn({ email: "   ", password: VALID_PASS });

    expect(errorOf(element, "email")).toBe(MESSAGE_EMAIL);
    expect(errorOf(element, "password")).toBe("");
    expect(login).not.toHaveBeenCalled();
  });

  it('AC-005.5: without a startURL the email (trimmed), the password and "/" are sent', async () => {
    await logIn({ email: "  Ana.Lopez@Example.com ", password: VALID_PASS });

    expect(login).toHaveBeenCalledTimes(1);
    expect(login).toHaveBeenCalledWith({
      email: "Ana.Lopez@Example.com",
      password: VALID_PASS,
      startUrl: "/"
    });
  });

  it.each(["/my-shipments", "/request-shipment", "/"])(
    'AC-005.5: the listed startURL "%s" is sent',
    async (startUrl) => {
      openPage(`?startURL=${encodeURIComponent(startUrl)}`);

      await logIn(ANA);

      expect(login).toHaveBeenCalledTimes(1);
      expect(login.mock.calls[0][0].startUrl).toBe(startUrl);
    }
  );

  it.each([
    "/rutacargo/my-shipments",
    "/rutacargo/request-shipment",
    "/rutacargo/"
  ])(
    'AC-005.5 (F13): the site base path form "%s" of a listed page is sent for the server to map',
    async (startUrl) => {
      openPage(`?startURL=${encodeURIComponent(startUrl)}`);

      await logIn(ANA);

      expect(login).toHaveBeenCalledTimes(1);
      expect(login.mock.calls[0][0].startUrl).toBe(startUrl);
    }
  );

  it.each([
    "https://evil.example",
    "//evil.example",
    "/secur/frontdoor.jsp",
    "/my-shipments/../admin",
    "/rutacargox/my-shipments",
    "/rutacargo/secur/frontdoor.jsp"
  ])(
    'AC-005.5: the startURL "%s" outside the list is sent as "/"',
    async (startUrl) => {
      openPage(`?startURL=${encodeURIComponent(startUrl)}`);

      await logIn(ANA);

      expect(login).toHaveBeenCalledTimes(1);
      expect(login.mock.calls[0][0].startUrl).toBe("/");
    }
  );

  it.each([REDIRECT_A, REDIRECT_B])(
    "AC-005.5: a successful login opens the server's redirect URL %s in the whole page",
    async (redirectUrl) => {
      login.mockResolvedValue({ success: true, redirectUrl, message: null });

      await logIn(ANA);

      expect(mockNavigate).toHaveBeenCalledTimes(1);
      expect(mockNavigate.mock.calls[0][0]).toEqual({
        type: "standard__webPage",
        attributes: { url: redirectUrl }
      });
    }
  );

  it("AC-005.5: the test page runs on the https site origin", () => {
    expect(window.location.origin).toBe(SITE_ORIGIN);
  });

  it.each([
    "https://evil.example/rutacargo/secur/frontdoor.jsp?sid=TOKEN_C",
    "https://rutacargo-test.my.site.com.evil.example/rutacargo/secur/frontdoor.jsp",
    "http://rutacargo-test.my.site.com/rutacargo/secur/frontdoor.jsp"
  ])(
    'AC-005.5 (X4): a redirect URL "%s" outside the site\'s own https origin is not opened',
    async (redirectUrl) => {
      login.mockResolvedValue({ success: true, redirectUrl, message: null });

      const element = await logIn(ANA);

      expect(mockNavigate).not.toHaveBeenCalled();
      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        GENERIC_ERROR
      );
    }
  );

  it.each(["javascript:alert(1)", "//evil.example/x", "data:text/html,x"])(
    'AC-005.5: a redirect URL "%s" that is neither https nor site-relative is not opened',
    async (redirectUrl) => {
      login.mockResolvedValue({ success: true, redirectUrl, message: null });

      const element = await logIn(ANA);

      expect(mockNavigate).not.toHaveBeenCalled();
      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        GENERIC_ERROR
      );
    }
  );

  it("AC-005.5: a failed login shows the one failure message, opens nothing and clears the password", async () => {
    const element = await logIn(ANA);

    expect(text(query(element, '[data-id="form-error"]'))).toBe(
      LOGIN_FAILED_MESSAGE
    );
    expect(mockNavigate).not.toHaveBeenCalled();
    expect(query(element, '[data-field="password"]').value).toBe("");
  });

  it("AC-005.5: a failed login with another server message still shows the one failure message", async () => {
    login.mockResolvedValue({
      success: false,
      redirectUrl: null,
      message: "No user with this email"
    });

    const element = await logIn(ANA);

    expect(text(query(element, '[data-id="form-error"]'))).toBe(
      LOGIN_FAILED_MESSAGE
    );
  });

  it("AC-005.9: a rejected call shows the generic message, never the error detail", async () => {
    login.mockRejectedValue({ body: { message: "System.SecurityException" } });

    const element = await logIn(ANA);

    expect(text(query(element, '[data-id="form-error"]'))).toBe(GENERIC_ERROR);
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it("AC-005.9: a second submit while the first is pending sends nothing", async () => {
    login.mockReturnValue(new Promise(() => {}));
    const element = await logIn(ANA);
    query(element, 'form[data-id="form"]').dispatchEvent(
      new CustomEvent("submit", { cancelable: true })
    );
    await flushPromises();

    expect(login).toHaveBeenCalledTimes(1);
    expect(query(element, 'button[data-id="submit"]').disabled).toBe(true);
  });

  it('AC-005.9: the bundle has no lwc:inner-html, innerHTML or lwc:dom="manual", and never logs or stores a value', () => {
    const dir = path.join(__dirname, "..");
    const sources = fs
      .readdirSync(dir)
      .filter((name) => /\.(js|html)$/.test(name))
      .map((name) => fs.readFileSync(path.join(dir, name), "utf8"));

    expect(sources.length).toBe(2);
    sources.forEach((source) => {
      expect(source).not.toMatch(/lwc:inner-html|innerHTML|outerHTML|lwc:dom/);
      expect(source).not.toMatch(
        /console\.|localStorage|sessionStorage|document\.cookie|indexedDB/
      );
    });
  });

  it("AC-005.9: the form is one column below 768 px", () => {
    const css = fs.readFileSync(
      path.join(__dirname, "..", "rcLogin.css"),
      "utf8"
    );
    const outsideWideQuery = css.replace(
      /@media \(min-width: 48em\) \{[\s\S]*?\n\}/g,
      ""
    );

    expect(outsideWideQuery).not.toMatch(
      /grid-template-columns:\s*(repeat\(\s*[2-9]|[^;]*fr[^;]*fr)/
    );
    expect(outsideWideQuery).not.toMatch(/flex-direction:\s*row/);
  });
});
