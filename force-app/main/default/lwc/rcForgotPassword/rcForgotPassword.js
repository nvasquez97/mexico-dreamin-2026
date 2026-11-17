import { LightningElement } from "lwc";
import forgotPassword from "@salesforce/apex/CustomerAuthController.forgotPassword";
import { reduceErrors, sitePath, validateInputs } from "c/rcUtils";

/** AC-005.6 — password reset link by email. */
export default class RcForgotPassword extends LightningElement {
  email = "";
  sent = false;
  message;
  errorMessage;
  isBusy = false;
  loginUrl = sitePath("/login");

  handleChange(event) {
    this.email = event.detail.value;
  }

  async handleSubmit(event) {
    event.preventDefault();
    if (!validateInputs(this.template)) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const result = await forgotPassword({ email: this.email.trim() });
      this.message = result.message;
      this.sent = true;
    } catch (error) {
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isBusy = false;
    }
  }
}
