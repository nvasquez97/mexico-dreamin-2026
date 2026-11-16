import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import login from '@salesforce/apex/CustomerAuthController.login';
import { errorMessage } from 'c/rcFormat';

/** Customer login with email and password (AC-005.5). */
export default class RcLogin extends LightningElement {
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
            const result = await login({ email: this.email, password: this.password });
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
