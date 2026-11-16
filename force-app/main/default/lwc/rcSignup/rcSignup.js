import { LightningElement } from 'lwc';
import basePath from '@salesforce/community/basePath';
import registerCustomer from '@salesforce/apex/RutaCargoController.registerCustomer';
import { errorMessage } from 'c/rcUtil';

export default class RcSignup extends LightningElement {
    form = { customerType: 'Individual', accountName: '', firstName: '', lastName: '', email: '', phone: '', password: '' };
    message;
    isError = false;
    alreadyRegistered = false;
    isBusy = false;

    get loginUrl() { return `${basePath}/login`; }
    get isIndividual() { return this.form.customerType === 'Individual'; }
    get isBusiness() { return this.form.customerType === 'Business'; }
    get nameLabel() { return this.isBusiness ? 'Legal name' : 'Full name'; }
    get messageClass() { return 'rc-msg ' + (this.isError ? 'rc-msg--error' : 'rc-msg--ok'); }

    handleField(event) {
        this.form = { ...this.form, [event.target.dataset.field]: event.target.value };
    }

    async handleSubmit(event) {
        event.preventDefault();
        this.isBusy = true;
        this.message = undefined;
        this.alreadyRegistered = false;
        try {
            const result = await registerCustomer({ ...this.form });
            if (result.success) {
                this.isError = false;
                this.message = result.message;
                this.dispatchEvent(new CustomEvent('registered'));
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => { window.location.assign(this.loginUrl); }, 1500);
            } else if (result.message === 'ALREADY_REGISTERED') {
                this.alreadyRegistered = true;
            } else {
                this.isError = true;
                this.message = result.message;
            }
        } catch (e) {
            this.isError = true;
            this.message = errorMessage(e);
        } finally {
            this.isBusy = false;
        }
    }
}
