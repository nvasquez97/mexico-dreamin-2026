import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import login from "@salesforce/apex/CustomerLoginController.login";
import BASE_PATH from "@salesforce/community/basePath";

// The pages a customer may land on after login (CustomerLoginController, S3),
// also in their site base path form (/rutacargo/my-shipments), which the
// server maps to the listed page: the server enforces the same closed list;
// anything else becomes "/".
const PAGES = ["/", "/my-shipments", "/request-shipment"];
const START_URLS = [
  ...PAGES,
  BASE_PATH,
  ...PAGES.map((page) => `${BASE_PATH}${page}`)
];
const DEFAULT_START_URL = "/";
const LOGIN_FAILED_MESSAGE = "Your email or password is incorrect.";
const GENERIC_ERROR = "We could not log you in. Please try again later.";
const MESSAGE_EMAIL = "Enter your email address.";
const MESSAGE_PASSWORD = "Enter your password.";

function requestedStartUrl() {
  const value = new URLSearchParams(window.location.search).get("startURL");
  return START_URLS.includes(value) ? value : DEFAULT_START_URL;
}

// Only a site-relative path (not "//host") or an https URL of the site's own
// origin is opened: never another host, nor a javascript:, data: or
// protocol-relative URL, whatever the server returns (X4).
function isOpenableUrl(url) {
  if (typeof url !== "string" || url === "") {
    return false;
  }
  if (url.startsWith("/")) {
    return !url.startsWith("//") && !url.startsWith("/\\");
  }
  if (!/^https:\/\/[^/\\]/i.test(url)) {
    return false;
  }
  try {
    return new URL(url).origin === window.location.origin;
  } catch {
    return false;
  }
}

/**
 * Customer login of the RutaCargo site (req-005 S4): email and password sent
 * to CustomerLoginController.login with the page's startURL when it is in the
 * closed list. On success the whole page opens the server's redirect URL
 * (never logged or stored); any failure shows the one message. The password
 * is read from its input at submit and cleared after a failed attempt.
 */
export default class RcLogin extends NavigationMixin(LightningElement) {
  errors = {};
  formError = "";
  isLoading = false;
  forgotPasswordUrl = `${BASE_PATH}/ForgotPassword`;
  signUpUrl = `${BASE_PATH}/SelfRegister`;

  get invalid() {
    return {
      email: String(Boolean(this.errors.email)),
      password: String(Boolean(this.errors.password))
    };
  }

  get submitLabel() {
    return this.isLoading ? "Logging in..." : "Log in";
  }

  input(field) {
    return this.template.querySelector(`[data-field="${field}"]`);
  }

  handleSubmit(event) {
    event.preventDefault();
    if (this.isLoading) {
      return;
    }
    const email = (this.input("email").value || "").trim();
    const password = this.input("password").value || "";
    this.formError = "";
    const errors = {};
    if (email === "") {
      errors.email = MESSAGE_EMAIL;
    }
    if (password === "") {
      errors.password = MESSAGE_PASSWORD;
    }
    this.errors = errors;
    if (Object.keys(errors).length > 0) {
      return;
    }
    this.isLoading = true;
    login({ email, password, startUrl: requestedStartUrl() })
      .then((result) => this.showResult(result))
      .catch(() => {
        this.formError = GENERIC_ERROR;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  showResult(result) {
    if (result && result.success === true) {
      if (isOpenableUrl(result.redirectUrl)) {
        this[NavigationMixin.Navigate]({
          type: "standard__webPage",
          attributes: { url: result.redirectUrl }
        });
      } else {
        this.formError = GENERIC_ERROR;
      }
      return;
    }
    this.input("password").value = "";
    this.formError = LOGIN_FAILED_MESSAGE;
  }
}
