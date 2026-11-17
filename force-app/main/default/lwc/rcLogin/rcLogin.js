import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import login from '@salesforce/apex/AuthController.login';
import forgotPassword from '@salesforce/apex/AuthController.forgotPassword';
import { errorMessage } from 'c/rcUtils';

export default class RcLogin extends NavigationMixin(LightningElement) {
    email = '';
    password = '';
    error;
    notice;
    busy = false;
    resetMode = false;
    startUrl;

    @wire(CurrentPageReference)
    pageRef(ref) {
        const s = ref && ref.state && ref.state.startURL;
        if (s) {
            this.startUrl = s;
        }
    }

    get title() {
        return this.resetMode ? 'Reset password' : 'Log in';
    }

    handleEmail(event) {
        this.email = event.target.value;
    }
    handlePassword(event) {
        this.password = event.target.value;
    }
    showReset() {
        this.resetMode = true;
        this.error = undefined;
        this.notice = undefined;
    }
    hideReset() {
        this.resetMode = false;
        this.error = undefined;
        this.notice = undefined;
    }
    goSignup() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Register' } });
    }

    async handleLogin(event) {
        event.preventDefault();
        this.error = undefined;
        this.busy = true;
        try {
            const target = this.startUrl || basePath + '/my-shipments';
            const url = await login({ email: this.email, password: this.password, startUrl: target });
            window.location.assign(url); // full load: the session cookie is set by Site.login
        } catch (e) {
            this.error = errorMessage(e);
            this.busy = false;
        }
    }

    async handleReset(event) {
        event.preventDefault();
        this.error = undefined;
        this.notice = undefined;
        this.busy = true;
        try {
            await forgotPassword({ email: this.email });
            // Same answer whether or not the email is registered
            this.notice = 'If that email is registered, we sent you a link to reset your password.';
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.busy = false;
        }
    }
}
