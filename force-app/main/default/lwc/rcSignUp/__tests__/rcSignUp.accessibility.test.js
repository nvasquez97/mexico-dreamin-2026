// Covers AC-005.9 (odd/tasks/req-005-customer-signup.md): the sign-up form is
// exposed to anonymous visitors, so its rendered DOM must pass the Sa11y rules
// (axe-core, WCAG A and AA base preset) empty, with every field error, with
// the duplicate-email message and its link, and after a sign-up.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcSignUp from "c/rcSignUp";
import signUp from "@salesforce/apex/CustomerSignUpController.signUp";

jest.mock(
  "@salesforce/apex/CustomerSignUpController.signUp",
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

const VALID = {
  accountName: "Ferretería Norte SA",
  firstName: "Luis",
  lastName: "Garza",
  email: "luis.garza@example.com",
  phone: "81-5555-0101",
  password: VALID_PASS,
  confirmPassword: VALID_PASS
};

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function renderAndSubmit(values) {
  const element = createElement("c-rc-sign-up", { is: RcSignUp });
  document.body.appendChild(element);
  await Promise.resolve();
  if (values) {
    Object.entries(values).forEach(([field, value]) => {
      element.shadowRoot.querySelector(`[data-field="${field}"]`).value = value;
    });
    if (values.accountName) {
      element.shadowRoot.querySelector(
        'input[name="customerType"][value="Business"]'
      ).checked = true;
    }
    element.shadowRoot
      .querySelector('form[data-id="form"]')
      .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
    await flushPromises();
  }
  return element;
}

describe("c-rc-sign-up accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    signUp.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-005.9: the empty form has no Sa11y violations", async () => {
    const element = await renderAndSubmit();

    await expect(element).toBeAccessible();
  });

  it("AC-005.9: the form with an error under every field has no Sa11y violations", async () => {
    const element = await renderAndSubmit({});

    expect(
      element.shadowRoot.querySelectorAll('[aria-invalid="true"]').length
    ).toBe(7);
    await expect(element).toBeAccessible();
  });

  it("AC-005.9: the duplicate-email message with its login link has no Sa11y violations", async () => {
    signUp.mockResolvedValue({
      success: false,
      code: "EMAIL_REGISTERED",
      field: "email",
      message: "This email is already registered. Log in instead."
    });

    const element = await renderAndSubmit(VALID);

    expect(
      element.shadowRoot.querySelector('a[data-id="registered-login"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });

  it("AC-005.9: the confirmation after a sign-up has no Sa11y violations", async () => {
    signUp.mockResolvedValue({
      success: true,
      code: "CREATED",
      field: null,
      message: "Your account is ready. Log in with your email and password."
    });

    const element = await renderAndSubmit(VALID);

    expect(
      element.shadowRoot.querySelector('[data-id="success-message"]')
    ).not.toBeNull();
    await expect(element).toBeAccessible();
  });
});
