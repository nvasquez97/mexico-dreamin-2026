import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import forgotPassword from '@salesforce/apex/CustomerAuthController.forgotPassword';
import { errorMessage } from 'c/rcFormat';

/** Password reset by email link (AC-005.6). The answer never reveals whether the email exists. */
export default class RcForgotPassword extends LightningElement {
    email = '';
    errorText;
    successText;
    loading = false;
    loginUrl = `${basePath}/login`;

    handleEmail(event) { this.email = event.target.value; }

    async handleSubmit(event) {
        event.preventDefault();
        this.errorText = undefined;
        this.successText = undefined;
        if (!this.email) {
            this.errorText = 'Enter your email.';
            return;
        }
        this.loading = true;
        try {
            const result = await forgotPassword({ email: this.email });
            this.successText = result.message;
        } catch (error) {
            this.errorText = errorMessage(error);
        } finally {
            this.loading = false;
        }
    }
}
