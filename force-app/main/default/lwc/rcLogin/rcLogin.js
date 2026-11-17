import { LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import login from "@salesforce/apex/CustomerAuthController.login";
import { reduceErrors, sitePath, validateInputs } from "c/rcUtils";

/** AC-005.5 — log in with email and password. */
export default class RcLogin extends LightningElement {
  email = "";
  password = "";
  errorMessage;
  isBusy = false;
  startUrl;

  forgotUrl = sitePath("/ForgotPassword");
  registerUrl = sitePath("/SelfRegister");

  @wire(CurrentPageReference)
  handlePageReference(pageRef) {
    this.startUrl = pageRef?.state?.startURL || pageRef?.state?.startUrl;
  }

  handleChange(event) {
    this[event.target.name] = event.detail.value;
  }

  async handleLogin(event) {
    event.preventDefault();
    if (!validateInputs(this.template)) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    try {
      const result = await login({
        email: this.email.trim(),
        password: this.password,
        startUrl: this.startUrl || sitePath("/my-shipments")
      });
      if (result.success && result.redirectUrl) {
        window.location.assign(result.redirectUrl);
        return;
      }
      this.errorMessage = result.message;
    } catch (error) {
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isBusy = false;
    }
  }
}
