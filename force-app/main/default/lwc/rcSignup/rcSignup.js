import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import signUp from '@salesforce/apex/AuthController.signUp';
import { errorMessage } from 'c/rcUtils';

export default class RcSignup extends NavigationMixin(LightningElement) {
    form = {};
    error;
    busy = false;

    get nameLabel() {
        return this.form.customerType === 'Individual' ? 'Your full name' : 'Business legal name';
    }
    get showLoginLink() {
        return !!this.error && this.error.indexOf('already registered') >= 0; // AC-005.3
    }

    handleChange(event) {
        this.form = { ...this.form, [event.target.name]: event.target.value };
    }
    goLogin() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Login' } });
    }

    async handleSubmit(event) {
        event.preventDefault();
        this.error = undefined;
        this.busy = true;
        try {
            const url = await signUp({ form: this.form, startUrl: basePath + '/request' });
            window.location.assign(url); // signed in right after registering
        } catch (e) {
            this.error = errorMessage(e);
            this.busy = false;
        }
    }
}
