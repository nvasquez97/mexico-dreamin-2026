// Covers AC-005.9 (odd/tasks/req-005-customer-signup.md): the login form is
// exposed to anonymous visitors, so its rendered DOM must pass the Sa11y rules
// (axe-core, WCAG A and AA base preset) empty, with the field errors and with
// the failure message.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcLogin from "c/rcLogin";
import login from "@salesforce/apex/CustomerLoginController.login";

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

// Test values of the password rule (AC-005.4), not credentials.
const VALID_PASS = "abcd12345X";

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function renderAndSubmit(values) {
  const element = createElement("c-rc-login", { is: RcLogin });
  document.body.appendChild(element);
  await Promise.resolve();
  if (values) {
    Object.entries(values).forEach(([field, value]) => {
      element.shadowRoot.querySelector(`[data-field="${field}"]`).value = value;
    });
    element.shadowRoot
      .querySelector('form[data-id="form"]')
      .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
    await flushPromises();
  }
  return element;
}

describe("c-rc-login accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    login.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-005.9: the empty login form has no Sa11y violations", async () => {
    const element = await renderAndSubmit();

    await expect(element).toBeAccessible();
  });

  it("AC-005.9: the login form with both field errors has no Sa11y violations", async () => {
    const element = await renderAndSubmit({});

    expect(
      element.shadowRoot.querySelectorAll('[aria-invalid="true"]').length
    ).toBe(2);
    await expect(element).toBeAccessible();
  });

  it("AC-005.9: the login form with the failure message has no Sa11y violations", async () => {
    login.mockResolvedValue({
      success: false,
      redirectUrl: null,
      message: "Your email or password is incorrect."
    });

    const element = await renderAndSubmit({
      email: "ana.lopez@example.com",
      password: VALID_PASS
    });

    expect(
      element.shadowRoot.querySelector('[data-id="form-error"]').textContent
    ).toContain("Your email or password is incorrect.");
    await expect(element).toBeAccessible();
  });
});
