import { LightningElement } from "lwc";
import signUp from "@salesforce/apex/CustomerSignUpController.signUp";
import BASE_PATH from "@salesforce/community/basePath";

// The server's rules and messages (CustomerSignUpController, req-005 S2): the
// client mirrors them so a visitor sees every field error at once; the server
// checks everything again.
const CUSTOMER_TYPES = ["Individual", "Business"];
const MAX_ACCOUNT_NAME = 255;
const MAX_FIRST_NAME = 40;
const MAX_LAST_NAME = 80;
// The username adds "." + the 18-character org Id (19) and holds 80.
const MAX_EMAIL = 61;
const MAX_PHONE = 40;
const MIN_PHONE_DIGITS = 7;
const MIN_PASSWORD = 10;
const MAX_PASSWORD = 128;
const EMAIL_FORMAT = /^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$/;
const PHONE_CHARACTERS = /^[0-9+() .-]+$/;

const MESSAGES = {
  customerType: "Choose Individual or Business.",
  accountName: "Enter the name or legal name (up to 255 characters).",
  firstName: "Enter the first name (up to 40 characters).",
  lastName: "Enter the last name (up to 80 characters).",
  email: "Enter a valid email address (up to 61 characters).",
  phone:
    "Enter a valid phone number (digits, spaces, +, -, parentheses; up to 40 characters).",
  password:
    "The password needs at least 10 characters, with letters and numbers.",
  confirmPassword: "The password and its confirmation do not match."
};
// Client only: the server compares the confirmation after the password rule.
const MESSAGE_CONFIRMATION_EMPTY = "Enter the password again.";
const MESSAGE_FAILED =
  "We could not create your account. Please try again later.";
const MESSAGE_CREATED =
  "Your account is ready. Log in with your email and password.";
const MESSAGE_PASS_POLICY =
  "This password does not meet the password policy. Choose another one.";
const MESSAGE_EMAIL_REGISTERED =
  "This email is already registered. Log in instead.";
const CODE_CREATED = "CREATED";
const CODE_EMAIL_REGISTERED = "EMAIL_REGISTERED";
// The closed list of messages CustomerSignUpController returns (req-005
// AC-005.10): any other text (platform or exception text) is never shown.
const KNOWN_SERVER_MESSAGES = new Set([
  ...Object.values(MESSAGES),
  MESSAGE_PASS_POLICY,
  MESSAGE_EMAIL_REGISTERED,
  MESSAGE_FAILED,
  MESSAGE_CREATED
]);

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
const TEXT_FIELDS = FIELDS.slice(1);

function isFilled(value, maxLength) {
  const trimmed = value.trim();
  return trimmed !== "" && trimmed.length <= maxLength;
}

function isValidEmail(value) {
  const normalized = value.trim().toLowerCase();
  return normalized.length <= MAX_EMAIL && EMAIL_FORMAT.test(normalized);
}

function isValidPhone(value) {
  const trimmed = value.trim();
  return (
    isFilled(value, MAX_PHONE) &&
    PHONE_CHARACTERS.test(trimmed) &&
    trimmed.replace(/[^0-9]/g, "").length >= MIN_PHONE_DIGITS
  );
}

function isValidPassword(value) {
  return (
    value.length >= MIN_PASSWORD &&
    value.length <= MAX_PASSWORD &&
    /[A-Za-z]/.test(value) &&
    /[0-9]/.test(value)
  );
}

/** The client errors of a submit, by field: every invalid field at once. */
function validate(values) {
  const errors = {};
  if (!CUSTOMER_TYPES.includes(values.customerType)) {
    errors.customerType = MESSAGES.customerType;
  }
  if (!isFilled(values.accountName, MAX_ACCOUNT_NAME)) {
    errors.accountName = MESSAGES.accountName;
  }
  if (!isFilled(values.firstName, MAX_FIRST_NAME)) {
    errors.firstName = MESSAGES.firstName;
  }
  if (!isFilled(values.lastName, MAX_LAST_NAME)) {
    errors.lastName = MESSAGES.lastName;
  }
  if (!isValidEmail(values.email)) {
    errors.email = MESSAGES.email;
  }
  if (!isValidPhone(values.phone)) {
    errors.phone = MESSAGES.phone;
  }
  if (!isValidPassword(values.password)) {
    errors.password = MESSAGES.password;
  }
  if (values.confirmPassword === "") {
    errors.confirmPassword = MESSAGE_CONFIRMATION_EMPTY;
  } else if (values.password !== values.confirmPassword) {
    errors.confirmPassword = MESSAGES.confirmPassword;
  }
  return errors;
}

/** The server's message when it is a known one, else the fallback text. */
function serverMessage(result, fallback) {
  const message = result && result.message;
  return KNOWN_SERVER_MESSAGES.has(message) ? message : fallback;
}

/**
 * Customer sign-up of the RutaCargo site (req-005 S4): customer type, name or
 * legal name, contact first and last name, email, phone, password and its
 * confirmation, sent as individual fields to CustomerSignUpController.signUp
 * (imperative: it creates records). Values are read from the inputs at
 * submit; the password is kept nowhere else and is never logged, stored or
 * put in a URL. Every message is rendered as text, and only a known server
 * message is shown (a generic text otherwise). After a sign-up the form is
 * replaced by the server's message and a link to log in.
 */
export default class RcSignUp extends LightningElement {
  errors = {};
  formError = "";
  isLoading = false;
  isCreated = false;
  isEmailRegistered = false;
  successMessage = "";
  loginUrl = `${BASE_PATH}/login`;

  get invalid() {
    return Object.fromEntries(
      TEXT_FIELDS.map((field) => [field, String(Boolean(this.errors[field]))])
    );
  }

  get submitLabel() {
    return this.isLoading ? "Creating your account..." : "Create account";
  }

  readValues() {
    const values = {};
    TEXT_FIELDS.forEach((field) => {
      const input = this.template.querySelector(`[data-field="${field}"]`);
      values[field] = input ? input.value || "" : "";
    });
    const chosen = this.template.querySelector(
      'input[name="customerType"]:checked'
    );
    values.customerType = chosen ? chosen.value : "";
    return values;
  }

  handleSubmit(event) {
    event.preventDefault();
    if (this.isLoading) {
      return;
    }
    const values = this.readValues();
    this.formError = "";
    this.isEmailRegistered = false;
    this.errors = validate(values);
    if (Object.keys(this.errors).length > 0) {
      return;
    }
    this.isLoading = true;
    signUp({
      customerType: values.customerType,
      accountName: values.accountName.trim(),
      firstName: values.firstName.trim(),
      lastName: values.lastName.trim(),
      email: values.email.trim(),
      phone: values.phone.trim(),
      password: values.password,
      confirmPassword: values.confirmPassword
    })
      .then((result) => this.showResult(result))
      .catch(() => {
        this.formError = MESSAGE_FAILED;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  showResult(result) {
    if (result && result.success === true && result.code === CODE_CREATED) {
      this.successMessage = serverMessage(result, MESSAGE_CREATED);
      this.isCreated = true;
      return;
    }
    const message = serverMessage(result, MESSAGE_FAILED);
    const field = result && result.field;
    if (FIELDS.includes(field)) {
      this.errors = { [field]: message };
      this.isEmailRegistered =
        field === "email" && result.code === CODE_EMAIL_REGISTERED;
      return;
    }
    this.formError = message;
  }
}
