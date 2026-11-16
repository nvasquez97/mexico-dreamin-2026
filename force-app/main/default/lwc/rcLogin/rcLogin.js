import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import login from '@salesforce/apex/RutaCargoController.login';
import forgotPassword from '@salesforce/apex/RutaCargoController.forgotPassword';
import { errorMessage } from 'c/rcUtil';

export default class RcLogin extends LightningElement {
    mode = 'login';
    email = '';
    password = '';
    message;
    isError = false;
    isBusy = false;

    get isLogin() { return this.mode === 'login'; }
    get title() { return this.isLogin ? 'Log in' : 'Reset your password'; }
    get buttonLabel() { return this.isLogin ? 'Log in' : 'Send reset link'; }
    get toggleLabel() { return this.isLogin ? 'Forgot your password?' : 'Back to log in'; }
    get registerUrl() { return `${basePath}/SelfRegister`; }
    get messageClass() { return 'rc-msg ' + (this.isError ? 'rc-msg--error' : 'rc-msg--ok'); }

    handleEmail(event) { this.email = event.target.value.trim(); }
    handlePassword(event) { this.password = event.target.value; }

    toggleMode() {
        this.mode = this.isLogin ? 'reset' : 'login';
        this.message = undefined;
    }

    async handleSubmit(event) {
        event.preventDefault();
        this.isBusy = true;
        this.message = undefined;
        try {
            if (this.isLogin) {
                const url = await login({ email: this.email, password: this.password, startUrl: `${basePath}/my-shipments` });
                window.location.assign(url);
            } else {
                this.isError = false;
                this.message = await forgotPassword({ email: this.email });
            }
        } catch (e) {
            this.isError = true;
            this.message = errorMessage(e, 'Invalid email or password.');
        } finally {
            this.isBusy = false;
        }
    }
}
