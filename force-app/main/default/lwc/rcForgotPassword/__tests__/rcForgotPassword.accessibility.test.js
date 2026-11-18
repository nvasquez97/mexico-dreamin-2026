// Covers AC-005.9 (odd/tasks/req-005-customer-signup.md): the forgot-password
// form is exposed to anonymous visitors, so its rendered DOM must pass the
// Sa11y rules (axe-core, WCAG A and AA base preset) empty, with the email
// error and with the generic failure message.
import { createElement } from "lwc";
import { setup } from "@sa11y/jest";
import RcForgotPassword from "c/rcForgotPassword";
import forgotPassword from "@salesforce/apex/CustomerLoginController.forgotPassword";

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

function flushPromises() {
  return Array.from({ length: 10 }).reduce(
    (chain) => chain.then(() => undefined),
    Promise.resolve()
  );
}

async function renderAndSubmit(email) {
  const element = createElement("c-rc-forgot-password", {
    is: RcForgotPassword
  });
  document.body.appendChild(element);
  await Promise.resolve();
  if (email !== undefined) {
    element.shadowRoot.querySelector('[data-field="email"]').value = email;
    element.shadowRoot
      .querySelector('form[data-id="form"]')
      .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
    await flushPromises();
  }
  return element;
}

describe("c-rc-forgot-password accessibility", () => {
  beforeAll(() => {
    setup();
  });

  beforeEach(() => {
    forgotPassword.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("AC-005.9: the empty forgot-password form has no Sa11y violations", async () => {
    const element = await renderAndSubmit();

    await expect(element).toBeAccessible();
  });

  it("AC-005.9: the form with the email error has no Sa11y violations", async () => {
    const element = await renderAndSubmit("");

    expect(
      element.shadowRoot
        .querySelector('[data-field="email"]')
        .getAttribute("aria-invalid")
    ).toBe("true");
    await expect(element).toBeAccessible();
  });

  it("AC-005.9: the form with the generic failure message has no Sa11y violations", async () => {
    forgotPassword.mockRejectedValue({ body: { message: "x" } });

    const element = await renderAndSubmit("ana.lopez@example.com");

    expect(
      element.shadowRoot.querySelector('[data-id="form-error"]').textContent
    ).toContain("We could not send the request.");
    await expect(element).toBeAccessible();
  });
});
