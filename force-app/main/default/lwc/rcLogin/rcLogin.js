import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import isGuest from '@salesforce/user/isGuest';
import login from '@salesforce/apex/CustomerAuthController.login';
import { errorMessage } from 'c/rcFormat';

/** Customer login with email and password (AC-005.5). */
export default class RcLogin extends LightningElement {
    isGuest = isGuest;

    /** Visitor-only page: a logged-in customer goes to My shipments (the auth Apex is only available to visitors). */
    connectedCallback() {
        if (!this.isGuest) {
            window.location.assign(`${basePath}/my-shipments`);
        }
    }

    email = '';
    password = '';
    errorText;
    loading = false;
    forgotUrl = `${basePath}/ForgotPassword`;
    registerUrl = `${basePath}/SelfRegister`;

    handleEmail(event) { this.email = event.target.value; }
    handlePassword(event) { this.password = event.target.value; }

    async handleLogin(event) {
        event.preventDefault();
        this.errorText = undefined;
        if (!this.email || !this.password) {
            this.errorText = 'Enter your email and password.';
            return;
        }
        this.loading = true;
        try {
            const result = await login({ email: this.email, password: this.password, startPath: `${basePath}/my-shipments` });
            if (result.success) {
                window.location.assign(result.redirectUrl);
                return;
            }
            this.errorText = result.message;
        } catch (error) {
            this.errorText = errorMessage(error);
        } finally {
            this.loading = false;
        }
    }
}
