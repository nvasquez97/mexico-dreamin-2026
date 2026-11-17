import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuestUser from '@salesforce/user/isGuest';
import BRAND from '@salesforce/resourceUrl/rcBrand';

export default class RcHome extends NavigationMixin(LightningElement) {
    isGuest = isGuestUser;
    logo = BRAND + '/logo-color.png';
    tn = '';

    handleTn(event) {
        this.tn = event.target.value;
    }
    handleTrack(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'Track__c' },
            state: { tn: this.tn.trim() }
        });
    }
    goRequest() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Request__c' } });
    }
    goSignup() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Register' } });
    }
}
