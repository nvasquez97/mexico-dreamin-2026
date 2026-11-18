// Covers odd/tasks/req-005-customer-signup.md, the client part of AC-005.6
// (after the reset request the check-email page is shown for any email,
// whatever the server returns) and AC-005.9 (labels and errors as text only,
// one column below 768 px).
import { createElement } from "lwc";
import RcForgotPassword from "c/rcForgotPassword";
import forgotPassword from "@salesforce/apex/CustomerLoginController.forgotPassword";

const fs = require("fs");
const path = require("path");

jest.mock(
  "@salesforce/apex/CustomerLoginController.forgotPassword",
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

const CHECK_EMAIL_PAGE = {
  type: "comm__namedPage",
  attributes: { name: "Check_Password" }
};
const MESSAGE_EMAIL = "Enter a valid email address.";
const GENERIC_ERROR = "We could not send the request. Please try again later.";

function render() {
  const element = createElement("c-rc-forgot-password", {
    is: RcForgotPassword
  });
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

async function requestReset(email) {
  const element = render();
  if (email !== undefined) {
    query(element, '[data-field="email"]').value = email;
  }
  query(element, 'form[data-id="form"]').dispatchEvent(
    new CustomEvent("submit", { cancelable: true })
  );
  await flushPromises();
  return element;
}

describe("c-rc-forgot-password", () => {
  beforeEach(() => {
    forgotPassword.mockReset();
    mockNavigate.mockReset();
    forgotPassword.mockResolvedValue(true);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-005.9: asks for the email with a label", () => {
    const element = render();

    const input = query(element, '[data-field="email"]');
    expect(input.type).toBe("email");
    expect(input.getAttribute("autocomplete")).toBe("email");
    expect(text(query(element, `label[for="${input.id}"]`))).toBe("Email");
  });

  it("AC-005.9: links back to the login page", () => {
    const element = render();

    const link = query(element, 'a[data-id="login-link"]');
    expect([text(link), link.getAttribute("href")]).toEqual([
      "Back to log in",
      "/rutacargo/login"
    ]);
  });

  it.each([undefined, "   ", "ana.lopez@", "ana lopez@example.com"])(
    'AC-005.6: the email "%s" is rejected on the client and nothing is called',
    async (email) => {
      const element = await requestReset(email);

      expect(text(query(element, '[data-error="email"]'))).toBe(MESSAGE_EMAIL);
      expect(
        query(element, '[data-field="email"]').getAttribute("aria-invalid")
      ).toBe("true");
      expect(forgotPassword).not.toHaveBeenCalled();
      expect(mockNavigate).not.toHaveBeenCalled();
    }
  );

  it.each([
    [
      "a registered customer",
      " Ana.Lopez@Example.com ",
      "Ana.Lopez@Example.com"
    ],
    ["an unregistered email", "nadie@example.com", "nadie@example.com"]
  ])(
    "AC-005.6: for %s the trimmed email is sent once and the check-email page is shown",
    async (unused, typed, sent) => {
      await requestReset(typed);

      expect(forgotPassword).toHaveBeenCalledTimes(1);
      expect(forgotPassword).toHaveBeenCalledWith({ email: sent });
      expect(mockNavigate).toHaveBeenCalledTimes(1);
      expect(mockNavigate.mock.calls[0][0]).toEqual(CHECK_EMAIL_PAGE);
    }
  );

  it.each([true, false, null, undefined, "other"])(
    "AC-005.6: the check-email page is shown whatever the server returns (%s)",
    async (answer) => {
      forgotPassword.mockResolvedValue(answer);

      const element = await requestReset("ana.lopez@example.com");

      expect(mockNavigate).toHaveBeenCalledTimes(1);
      expect(mockNavigate.mock.calls[0][0]).toEqual(CHECK_EMAIL_PAGE);
      expect(text(query(element, '[data-id="form-error"]'))).toBe("");
    }
  );

  it("AC-005.6: a rejected call shows the generic message and stays on the page", async () => {
    forgotPassword.mockRejectedValue({ body: { message: "Internal detail" } });

    const element = await requestReset("ana.lopez@example.com");

    expect(text(query(element, '[data-id="form-error"]'))).toBe(GENERIC_ERROR);
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it("AC-005.6: a second submit while the first is pending sends nothing", async () => {
    forgotPassword.mockReturnValue(new Promise(() => {}));
    const element = await requestReset("ana.lopez@example.com");
    query(element, 'form[data-id="form"]').dispatchEvent(
      new CustomEvent("submit", { cancelable: true })
    );
    await flushPromises();

    expect(forgotPassword).toHaveBeenCalledTimes(1);
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
      path.join(__dirname, "..", "rcForgotPassword.css"),
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
