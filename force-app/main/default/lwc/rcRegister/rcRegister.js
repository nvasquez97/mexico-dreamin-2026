import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import register from '@salesforce/apex/CustomerAuthController.register';
import { errorMessage } from 'c/rcFormat';

const STRONG_PASSWORD = /^(?=.*[A-Za-z])(?=.*[0-9]).{10,}$/;

/** Customer sign-up (AC-005.1 to AC-005.4). The server repeats every check. */
export default class RcRegister extends LightningElement {
    customerType = 'Individual';
    accountName = '';
    firstName = '';
    lastName = '';
    email = '';
    phone = '';
    password = '';
    confirm = '';
    errorText;
    successText;
    showLoginLink = false;
    loading = false;
    loginUrl = `${basePath}/login`;

    get isIndividual() { return this.customerType === 'Individual'; }
    get isBusiness() { return this.customerType === 'Business'; }
    get accountNameLabel() { return this.isBusiness ? 'Legal name of the business' : 'Your full name'; }

    handleType(event) { this.customerType = event.target.value; }
    handleField(event) { this[event.target.dataset.field] = event.target.value; }

    async handleRegister(event) {
        event.preventDefault();
        this.errorText = undefined;
        this.successText = undefined;
        this.showLoginLink = false;
        if (![this.accountName, this.firstName, this.lastName, this.email, this.phone].every((v) => v && v.trim())) {
            this.errorText = 'Complete all the fields.';
            return;
        }
        if (!STRONG_PASSWORD.test(this.password)) {
            this.errorText = 'The password must have at least 10 characters, with letters and numbers.';
            return;
        }
        if (this.password !== this.confirm) {
            this.errorText = 'The passwords do not match.';
            return;
        }
        this.loading = true;
        try {
            const result = await register({
                customerType: this.customerType,
                accountName: this.accountName,
                firstName: this.firstName,
                lastName: this.lastName,
                email: this.email,
                phone: this.phone,
                password: this.password
            });
            if (result.success && result.redirectUrl) {
                window.location.assign(result.redirectUrl);
                return;
            }
            if (result.success) {
                this.successText = result.message;
                return;
            }
            this.errorText = result.message;
            this.showLoginLink = result.emailAlreadyRegistered;
        } catch (error) {
            this.errorText = errorMessage(error);
        } finally {
            this.loading = false;
        }
    }
}
