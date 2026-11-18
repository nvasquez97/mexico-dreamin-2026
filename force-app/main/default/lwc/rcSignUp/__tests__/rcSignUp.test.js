// Covers odd/tasks/req-005-customer-signup.md, the client parts of AC-005.1
// (the form's fields and its per-field errors, the 61/62-character email
// boundary, the closed customer type list, field lengths), AC-005.3 (the
// duplicate-email message with a link to the login page), AC-005.4 (the
// client password rule and the confirmation) and AC-005.9 (text-only
// rendering, no password logged or stored, one column below 768 px) and
// AC-005.10 (only the server's known messages are shown, a generic text otherwise).
import { createElement } from "lwc";
import RcSignUp from "c/rcSignUp";
import signUp from "@salesforce/apex/CustomerSignUpController.signUp";

// Test values of the password rule (AC-005.4), not credentials.
const VALID_PASS = "abcd12345X";
const OTHER_VALID_PASS = "Zz9zz9zz9z";
const DIFFERENT_CASE_PASS = "abcd12345x";

const fs = require("fs");
const path = require("path");

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

// The server's messages (CustomerSignUpController, T2 d609edc).
const MESSAGE_CUSTOMER_TYPE = "Choose Individual or Business.";
const MESSAGE_ACCOUNT_NAME =
  "Enter the name or legal name (up to 255 characters).";
const MESSAGE_FIRST_NAME = "Enter the first name (up to 40 characters).";
const MESSAGE_LAST_NAME = "Enter the last name (up to 80 characters).";
const MESSAGE_EMAIL = "Enter a valid email address (up to 61 characters).";
const MESSAGE_PHONE =
  "Enter a valid phone number (digits, spaces, +, -, parentheses; up to 40 characters).";
const MESSAGE_PASS_RULES =
  "The password needs at least 10 characters, with letters and numbers.";
const MESSAGE_CONFIRMATION = "The password and its confirmation do not match.";
// Client only: the server compares the confirmation after the password rule.
const MESSAGE_CONFIRMATION_EMPTY = "Enter the password again.";
const MESSAGE_PASS_POLICY =
  "This password does not meet the password policy. Choose another one.";
const MESSAGE_EMAIL_REGISTERED =
  "This email is already registered. Log in instead.";
const MESSAGE_FAILED =
  "We could not create your account. Please try again later.";
const MESSAGE_CREATED =
  "Your account is ready. Log in with your email and password.";
const LOGIN_URL = "/rutacargo/login";

const FIELDS = [
  "customerType",
  "accountName",
  "firstName",
  "lastName",
  "email",
  "phone",
  "password",
  "confirmPassword"
];

const BUSINESS = {
  customerType: "Business",
  accountName: "Ferretería Norte SA",
  firstName: "Luis",
  lastName: "Garza",
  email: " Luis.Garza@Example.com ",
  phone: "81-5555-0101",
  password: VALID_PASS,
  confirmPassword: VALID_PASS
};

const INDIVIDUAL = {
  customerType: "Individual",
  accountName: "Ana López",
  firstName: "Ana",
  lastName: "López",
  email: "ana.lopez@example.com",
  phone: "+52 (55) 1234 5678",
  password: OTHER_VALID_PASS,
  confirmPassword: OTHER_VALID_PASS
};

function render() {
  const element = createElement("c-rc-sign-up", { is: RcSignUp });
  document.body.appendChild(element);
  return element;
}

// Settles the mocked Apex promise chain and the re-render it triggers.
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

function fill(element, values) {
  Object.entries(values).forEach(([field, value]) => {
    if (field === "customerType") {
      element.shadowRoot
        .querySelectorAll('input[name="customerType"]')
        .forEach((radio) => {
          radio.checked = radio.value === value;
        });
      return;
    }
    query(element, `[data-field="${field}"]`).value = value;
  });
}

async function submit(element) {
  query(element, 'form[data-id="form"]').dispatchEvent(
    new CustomEvent("submit", { cancelable: true })
  );
  await flushPromises();
}

async function signUpWith(values) {
  const element = render();
  fill(element, values);
  await submit(element);
  return element;
}

function serverResult(overrides) {
  return {
    success: false,
    code: "INVALID",
    field: null,
    message: null,
    ...overrides
  };
}

describe("c-rc-sign-up", () => {
  beforeEach(() => {
    signUp.mockReset();
    signUp.mockResolvedValue(
      serverResult({ success: true, code: "CREATED", message: MESSAGE_CREATED })
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  describe("AC-005.1 client: the fields and their errors", () => {
    it("AC-005.1: asks for the customer type with the two options Individual and Business", () => {
      const element = render();

      const legend = query(element, 'fieldset[data-id="customerType"] legend');
      expect(text(legend)).toBe("Customer type");
      const options = Array.from(
        element.shadowRoot.querySelectorAll('input[name="customerType"]')
      ).map((radio) => ({
        type: radio.type,
        value: radio.value,
        label: text(query(element, `label[for="${radio.id}"]`))
      }));
      expect(options).toEqual([
        { type: "radio", value: "Individual", label: "Individual" },
        { type: "radio", value: "Business", label: "Business" }
      ]);
    });

    it("AC-005.1: asks for name or legal name, contact first and last name, email, phone, password and confirmation, each with a label", () => {
      const element = render();

      const fields = FIELDS.slice(1).map((field) => {
        const input = query(element, `[data-field="${field}"]`);
        return {
          field,
          type: input.type,
          label: text(query(element, `label[for="${input.id}"]`))
        };
      });
      expect(fields).toEqual([
        { field: "accountName", type: "text", label: "Name or legal name" },
        { field: "firstName", type: "text", label: "Contact first name" },
        { field: "lastName", type: "text", label: "Contact last name" },
        { field: "email", type: "email", label: "Email" },
        { field: "phone", type: "tel", label: "Phone" },
        { field: "password", type: "password", label: "Password" },
        {
          field: "confirmPassword",
          type: "password",
          label: "Confirm password"
        }
      ]);
    });

    it("AC-005.1: an empty form shows the server's message under every field and calls nothing", async () => {
      const element = await signUpWith({});

      expect(FIELDS.map((field) => errorOf(element, field))).toEqual([
        MESSAGE_CUSTOMER_TYPE,
        MESSAGE_ACCOUNT_NAME,
        MESSAGE_FIRST_NAME,
        MESSAGE_LAST_NAME,
        MESSAGE_EMAIL,
        MESSAGE_PHONE,
        MESSAGE_PASS_RULES,
        MESSAGE_CONFIRMATION_EMPTY
      ]);
      expect(signUp).not.toHaveBeenCalled();
    });

    it("AC-005.1: values of only spaces count as empty", async () => {
      const element = await signUpWith({
        ...BUSINESS,
        accountName: "   ",
        firstName: " ",
        lastName: "  ",
        phone: "   "
      });

      expect(errorOf(element, "accountName")).toBe(MESSAGE_ACCOUNT_NAME);
      expect(errorOf(element, "firstName")).toBe(MESSAGE_FIRST_NAME);
      expect(errorOf(element, "lastName")).toBe(MESSAGE_LAST_NAME);
      expect(errorOf(element, "phone")).toBe(MESSAGE_PHONE);
      expect(errorOf(element, "email")).toBe("");
      expect(signUp).not.toHaveBeenCalled();
    });

    it("AC-005.1: marks only the invalid fields with aria-invalid", async () => {
      const element = await signUpWith({ ...BUSINESS, firstName: "" });

      expect(
        query(element, '[data-field="firstName"]').getAttribute("aria-invalid")
      ).toBe("true");
      expect(
        query(element, '[data-field="lastName"]').getAttribute("aria-invalid")
      ).toBe("false");
    });

    it("AC-005.1: a customer type outside {Individual, Business} is rejected on the client", async () => {
      const element = render();
      fill(element, BUSINESS);
      const radio = query(
        element,
        'input[name="customerType"][value="Business"]'
      );
      radio.value = "Partner";
      radio.checked = true;
      await submit(element);

      expect(errorOf(element, "customerType")).toBe(MESSAGE_CUSTOMER_TYPE);
      expect(signUp).not.toHaveBeenCalled();
    });

    it("AC-005.1: a 61-character email is accepted and sent", async () => {
      const email = `${"a".repeat(49)}@example.com`;
      expect(email.length).toBe(61);

      const element = await signUpWith({ ...BUSINESS, email });

      expect(signUp).toHaveBeenCalledTimes(1);
      expect(signUp.mock.calls[0][0].email).toBe(email);
      expect(query(element, '[data-id="success-message"]')).not.toBeNull();
    });

    it("AC-005.1: a 62-character email is rejected with the email message", async () => {
      const email = `${"a".repeat(50)}@example.com`;
      expect(email.length).toBe(62);

      const element = await signUpWith({ ...BUSINESS, email });

      expect(errorOf(element, "email")).toBe(MESSAGE_EMAIL);
      expect(signUp).not.toHaveBeenCalled();
    });

    it.each(["ana.lopez@", "ana lopez@example.com", "ana.lopez@example"])(
      'AC-005.1: the malformed email "%s" is rejected',
      async (email) => {
        const element = await signUpWith({ ...BUSINESS, email });

        expect(errorOf(element, "email")).toBe(MESSAGE_EMAIL);
        expect(signUp).not.toHaveBeenCalled();
      }
    );

    it.each([
      ["accountName", "N".repeat(256), MESSAGE_ACCOUNT_NAME],
      ["firstName", "F".repeat(41), MESSAGE_FIRST_NAME],
      ["lastName", "L".repeat(81), MESSAGE_LAST_NAME],
      ["phone", "1".repeat(41), MESSAGE_PHONE]
    ])(
      "AC-005.1: %s longer than its field is rejected",
      async (field, value, message) => {
        const element = await signUpWith({ ...BUSINESS, [field]: value });

        expect(errorOf(element, field)).toBe(message);
        expect(signUp).not.toHaveBeenCalled();
      }
    );

    it.each(["81-5555-01a1", "12345"])(
      'AC-005.1: the phone "%s" (a letter, or fewer than 7 digits) is rejected',
      async (phone) => {
        const element = await signUpWith({ ...BUSINESS, phone });

        expect(errorOf(element, "phone")).toBe(MESSAGE_PHONE);
        expect(signUp).not.toHaveBeenCalled();
      }
    );

    it("AC-005.1: valid Business values are sent once, as individual fields, trimmed", async () => {
      await signUpWith(BUSINESS);

      expect(signUp).toHaveBeenCalledTimes(1);
      expect(signUp).toHaveBeenCalledWith({
        customerType: "Business",
        accountName: "Ferretería Norte SA",
        firstName: "Luis",
        lastName: "Garza",
        email: "Luis.Garza@Example.com",
        phone: "81-5555-0101",
        password: VALID_PASS,
        confirmPassword: VALID_PASS
      });
    });

    it("AC-005.1: valid Individual values are sent once", async () => {
      await signUpWith(INDIVIDUAL);

      expect(signUp).toHaveBeenCalledTimes(1);
      expect(signUp).toHaveBeenCalledWith({
        customerType: "Individual",
        accountName: "Ana López",
        firstName: "Ana",
        lastName: "López",
        email: "ana.lopez@example.com",
        phone: "+52 (55) 1234 5678",
        password: OTHER_VALID_PASS,
        confirmPassword: OTHER_VALID_PASS
      });
    });

    it("AC-005.1: a server field error is shown under that field", async () => {
      signUp.mockResolvedValue(
        serverResult({ field: "phone", message: MESSAGE_PHONE })
      );

      const element = await signUpWith(BUSINESS);

      expect(errorOf(element, "phone")).toBe(MESSAGE_PHONE);
      expect(errorOf(element, "email")).toBe("");
      expect(text(query(element, '[data-id="form-error"]'))).toBe("");
    });

    it("AC-005.1: a server failure without a field is shown above the button", async () => {
      signUp.mockResolvedValue(
        serverResult({ code: "FAILED", message: MESSAGE_FAILED })
      );

      const element = await signUpWith(INDIVIDUAL);

      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        MESSAGE_FAILED
      );
    });

    it("AC-005.1: a rejected call shows the generic message, never the error detail", async () => {
      signUp.mockRejectedValue({
        body: { message: "System.DmlException: Insert failed" }
      });

      const element = await signUpWith(BUSINESS);

      expect(text(query(element, '[data-id="form-error"]'))).toBe(
        MESSAGE_FAILED
      );
    });
  });

  describe("AC-005.3 client: a registered email", () => {
    it("AC-005.3: shows the duplicate message under the email with a link to the login page", async () => {
      signUp.mockResolvedValue(
        serverResult({
          code: "EMAIL_REGISTERED",
          field: "email",
          message: MESSAGE_EMAIL_REGISTERED
        })
      );

      const element = await signUpWith({
        ...BUSINESS,
        email: " Ana.Lopez@Example.com "
      });

      const error = query(element, '[data-error="email"]');
      // The message, then the link (a CSS margin separates them on screen).
      expect(text(error)).toBe(`${MESSAGE_EMAIL_REGISTERED}Log in`);
      const link = error.querySelector('a[data-id="registered-login"]');
      expect(link.getAttribute("href")).toBe(LOGIN_URL);
      expect(text(link)).toBe("Log in");
    });

    it("AC-005.3: the link is not shown for another email error", async () => {
      signUp.mockResolvedValue(
        serverResult({ field: "email", message: MESSAGE_EMAIL })
      );

      const element = await signUpWith(BUSINESS);

      expect(errorOf(element, "email")).toBe(MESSAGE_EMAIL);
      expect(query(element, 'a[data-id="registered-login"]')).toBeNull();
    });
  });

  describe("AC-005.4 client: the password rule", () => {
    it.each([
      ["abc123def", "9 characters"],
      ["abcdefghij", "no digit"],
      ["1234567890", "no letter"]
    ])(
      'AC-005.4: the password "%s" (%s) is rejected with the password message',
      async (password) => {
        const element = await signUpWith({
          ...BUSINESS,
          password,
          confirmPassword: password
        });

        expect(errorOf(element, "password")).toBe(MESSAGE_PASS_RULES);
        expect(signUp).not.toHaveBeenCalled();
      }
    );

    it("AC-005.4: a confirmation that differs is rejected under the confirmation", async () => {
      const element = await signUpWith({
        ...BUSINESS,
        confirmPassword: DIFFERENT_CASE_PASS
      });

      expect(errorOf(element, "confirmPassword")).toBe(MESSAGE_CONFIRMATION);
      expect(errorOf(element, "password")).toBe("");
      expect(signUp).not.toHaveBeenCalled();
    });

    it.each(["abcd12345X", "Zz9zz9zz9z"])(
      'AC-005.4: the password "%s" is accepted and sent',
      async (password) => {
        const element = await signUpWith({
          ...BUSINESS,
          password,
          confirmPassword: password
        });

        expect(signUp).toHaveBeenCalledTimes(1);
        expect(query(element, '[data-id="success-message"]')).not.toBeNull();
        expect(signUp.mock.calls[0][0].password).toBe(password);
      }
    );

    it("AC-005.4: the server's password policy message is shown under the password", async () => {
      signUp.mockResolvedValue(
        serverResult({ field: "password", message: MESSAGE_PASS_POLICY })
      );

      const element = await signUpWith(BUSINESS);

      expect(errorOf(element, "password")).toBe(MESSAGE_PASS_POLICY);
    });
  });

  describe("AC-005.10: only the server's known messages are shown", () => {
    // The platform text the owner reported on 2026-11-18, and another raw one.
    const PLATFORM_TEXT = "accountId parameter value is not valid";
    const RAW_TEXTS = [
      `Site.ExternalUserCreateException: [${PLATFORM_TEXT}.]`,
      "System.DmlException: Insert failed. First exception on row 0"
    ];
    const KNOWN_GENERAL = [MESSAGE_FAILED, MESSAGE_EMAIL_REGISTERED];
    const KNOWN_BY_FIELD = [
      ["customerType", MESSAGE_CUSTOMER_TYPE],
      ["accountName", MESSAGE_ACCOUNT_NAME],
      ["firstName", MESSAGE_FIRST_NAME],
      ["lastName", MESSAGE_LAST_NAME],
      ["email", MESSAGE_EMAIL],
      ["email", MESSAGE_EMAIL_REGISTERED],
      ["phone", MESSAGE_PHONE],
      ["password", MESSAGE_PASS_RULES],
      ["password", MESSAGE_PASS_POLICY],
      ["confirmPassword", MESSAGE_CONFIRMATION]
    ];

    it.each(RAW_TEXTS)(
      "AC-005.10: an unknown failure message (%s) is replaced by the generic text",
      async (raw) => {
        signUp.mockResolvedValue(
          serverResult({ code: "FAILED", message: raw })
        );

        const element = await signUpWith(BUSINESS);

        expect(text(query(element, '[data-id="form-error"]'))).toBe(
          MESSAGE_FAILED
        );
        expect(element.shadowRoot.textContent).not.toContain(raw);
      }
    );

    it.each([
      ["email", RAW_TEXTS[0]],
      ["password", RAW_TEXTS[1]]
    ])(
      "AC-005.10: an unknown message for the field %s is replaced by the generic text",
      async (field, raw) => {
        signUp.mockResolvedValue(serverResult({ field, message: raw }));

        const element = await signUpWith(BUSINESS);

        expect(errorOf(element, field)).toBe(MESSAGE_FAILED);
        expect(element.shadowRoot.textContent).not.toContain(PLATFORM_TEXT);
        expect(element.shadowRoot.textContent).not.toContain(raw);
      }
    );

    it.each([PLATFORM_TEXT, "Welcome <b>back</b>"])(
      "AC-005.10: a success with an unknown message (%s) shows the known created text",
      async (raw) => {
        signUp.mockResolvedValue(
          serverResult({ success: true, code: "CREATED", message: raw })
        );

        const element = await signUpWith(BUSINESS);

        expect(text(query(element, '[data-id="success-message"]'))).toBe(
          MESSAGE_CREATED
        );
        expect(element.shadowRoot.textContent).not.toContain(raw);
      }
    );

    it.each(KNOWN_GENERAL)(
      "AC-005.10: the known general message \"%s\" is shown above the button",
      async (known) => {
        signUp.mockResolvedValue(
          serverResult({ code: "FAILED", message: known })
        );

        const element = await signUpWith(INDIVIDUAL);

        expect(text(query(element, '[data-id="form-error"]'))).toBe(known);
      }
    );

    it.each(KNOWN_BY_FIELD)(
      "AC-005.10: the known message for %s (\"%s\") is shown under the field",
      async (field, known) => {
        signUp.mockResolvedValue(serverResult({ field, message: known }));

        const element = await signUpWith(BUSINESS);

        expect(errorOf(element, field)).toBe(known);
      }
    );
  });

  describe("sign-up success", () => {
    it("AC-005.1: after a sign-up the form is replaced by the server's message and a link to log in", async () => {
      const element = await signUpWith(BUSINESS);

      expect(text(query(element, '[data-id="success-message"]'))).toBe(
        MESSAGE_CREATED
      );
      expect(
        query(element, 'a[data-id="success-login"]').getAttribute("href")
      ).toBe(LOGIN_URL);
      expect(query(element, 'form[data-id="form"]')).toBeNull();
      expect(query(element, 'input[type="password"]')).toBeNull();
    });

    it("AC-005.1: a second submit while the first is pending sends nothing", async () => {
      signUp.mockReturnValue(new Promise(() => {}));
      const element = render();
      fill(element, BUSINESS);
      await submit(element);
      await submit(element);

      expect(signUp).toHaveBeenCalledTimes(1);
      expect(query(element, 'button[data-id="submit"]').disabled).toBe(true);
    });
  });

  describe("AC-005.9: text only, no stored password, mobile first", () => {
    it("AC-005.9: a server message with markup is never rendered (neither as markup nor as text)", async () => {
      signUp.mockResolvedValue(
        serverResult({ code: "FAILED", message: "<b>Bold</b> & co" })
      );

      const element = await signUpWith(BUSINESS);

      const formError = query(element, '[data-id="form-error"]');
      expect(text(formError)).toBe(MESSAGE_FAILED);
      expect(formError.querySelector("b")).toBeNull();
    });

    it("AC-005.9: the form links to the login page for registered customers", () => {
      const element = render();

      const link = query(element, 'a[data-id="login-link"]');
      expect(link.getAttribute("href")).toBe(LOGIN_URL);
      expect(text(link)).toBe("Log in");
    });

    it('AC-005.9: the bundle has no lwc:inner-html, innerHTML or lwc:dom="manual", and never logs or stores a value', () => {
      const dir = path.join(__dirname, "..");
      const sources = fs
        .readdirSync(dir)
        .filter((name) => /\.(js|html)$/.test(name))
        .map((name) => fs.readFileSync(path.join(dir, name), "utf8"));

      expect(sources.length).toBe(2);
      sources.forEach((source) => {
        expect(source).not.toMatch(
          /lwc:inner-html|innerHTML|outerHTML|lwc:dom/
        );
        expect(source).not.toMatch(
          /console\.|localStorage|sessionStorage|document\.cookie|indexedDB/
        );
      });
    });

    it("AC-005.9: the form is one column below 768 px (no multi-column grid outside a min-width: 48em query)", () => {
      const css = fs.readFileSync(
        path.join(__dirname, "..", "rcSignUp.css"),
        "utf8"
      );
      const outsideWideQuery = css.replace(
        /@media \(min-width: 48em\) \{[\s\S]*?\n\}/g,
        ""
      );

      expect(css).toMatch(/@media \(min-width: 48em\)/);
      expect(outsideWideQuery).not.toMatch(
        /grid-template-columns:\s*(repeat\(\s*[2-9]|[^;]*fr[^;]*fr)/
      );
      expect(outsideWideQuery).not.toMatch(/flex-direction:\s*row/);
    });
  });
});
