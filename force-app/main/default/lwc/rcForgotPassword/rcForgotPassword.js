import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import forgotPassword from "@salesforce/apex/CustomerLoginController.forgotPassword";
import BASE_PATH from "@salesforce/community/basePath";

const EMAIL_FORMAT = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MESSAGE_EMAIL = "Enter a valid email address.";
const GENERIC_ERROR = "We could not send the request. Please try again later.";
// The site's existing check-email page (route Check_Password).
const CHECK_EMAIL_PAGE = {
  type: "comm__namedPage",
  attributes: { name: "Check_Password" }
};

/**
 * Password reset request of the RutaCargo site (req-005 S3, S4): the email is
 * sent to CustomerLoginController.forgotPassword, which answers the same for
 * every email (X16); the component then shows the check-email page whatever
 * the answer, so the page never tells whether an email is registered.
 */
export default class RcForgotPassword extends NavigationMixin(
  LightningElement
) {
  errors = {};
  formError = "";
  isLoading = false;
  loginUrl = `${BASE_PATH}/login`;

  get invalid() {
    return { email: String(Boolean(this.errors.email)) };
  }

  get submitLabel() {
    return this.isLoading ? "Sending..." : "Send reset link";
  }

  handleSubmit(event) {
    event.preventDefault();
    if (this.isLoading) {
      return;
    }
    const input = this.template.querySelector('[data-field="email"]');
    const email = (input.value || "").trim();
    this.formError = "";
    if (!EMAIL_FORMAT.test(email)) {
      this.errors = { email: MESSAGE_EMAIL };
      return;
    }
    this.errors = {};
    this.isLoading = true;
    forgotPassword({ email })
      .then(() => {
        this[NavigationMixin.Navigate](CHECK_EMAIL_PAGE);
      })
      .catch(() => {
        this.formError = GENERIC_ERROR;
      })
      .finally(() => {
        this.isLoading = false;
      });
  }
}
