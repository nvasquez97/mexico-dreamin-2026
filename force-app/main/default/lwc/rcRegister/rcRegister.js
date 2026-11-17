import { LightningElement } from "lwc";
import register from "@salesforce/apex/CustomerAuthController.register";
import { reduceErrors, sitePath, validateInputs } from "c/rcUtils";

const PASSWORD_RULE =
  "The password must have at least 10 characters, with letters and numbers.";

/** REQ-005 — customer sign-up (AC-005.1 to AC-005.4). */
export default class RcRegister extends LightningElement {
  form = {
    customerType: "Business",
    accountName: "",
    firstName: "",
    lastName: "",
    email: "",
    phone: "",
    password: "",
    confirmPassword: ""
  };
  errorMessage;
  isDuplicate = false;
  isBusy = false;

  phonePattern = "\\+?[0-9 ()\\-]{10,20}";
  loginUrl = sitePath("/login");
  forgotUrl = sitePath("/ForgotPassword");

  customerTypeOptions = [
    { label: "A business", value: "Business" },
    { label: "An individual", value: "Individual" }
  ];

  get accountNameLabel() {
    return this.form.customerType === "Business"
      ? "Legal name of the business"
      : "Your full name";
  }

  handleChange(event) {
    this.form = { ...this.form, [event.target.name]: event.detail.value };
  }

  static isValidPassword(value) {
    return (
      !!value &&
      value.length >= 10 &&
      /[A-Za-z]/.test(value) &&
      /[0-9]/.test(value)
    );
  }

  async handleSubmit(event) {
    event.preventDefault();
    const password = this.template.querySelector(".password");
    const confirm = this.template.querySelector(".confirm");
    password.setCustomValidity(
      RcRegister.isValidPassword(this.form.password) ? "" : PASSWORD_RULE
    );
    confirm.setCustomValidity(
      this.form.confirmPassword === this.form.password
        ? ""
        : "The passwords do not match."
    );
    if (!validateInputs(this.template)) {
      return;
    }
    this.isBusy = true;
    this.errorMessage = undefined;
    this.isDuplicate = false;
    try {
      const { confirmPassword, ...request } = this.form; // eslint-disable-line no-unused-vars
      const result = await register({
        request: {
          ...request,
          email: request.email.trim(),
          startUrl: sitePath("/request-shipment")
        }
      });
      if (result.success) {
        window.location.assign(result.redirectUrl || sitePath("/login"));
        return;
      }
      this.isDuplicate = result.duplicate;
      this.errorMessage = result.message;
    } catch (error) {
      this.errorMessage = reduceErrors(error);
    } finally {
      this.isBusy = false;
    }
  }
}
