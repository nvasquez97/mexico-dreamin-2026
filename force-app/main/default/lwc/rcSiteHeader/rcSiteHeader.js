import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import isGuestUser from '@salesforce/user/isGuest';
import basePath from '@salesforce/community/basePath';
import BRAND from '@salesforce/resourceUrl/rcBrand';

export default class RcSiteHeader extends NavigationMixin(LightningElement) {
    isGuest = isGuestUser;
    isotype = BRAND + '/isotype-tinto.png';
    logoutUrl = basePath + '/secur/logout.jsp?retUrl=' + encodeURIComponent(basePath + '/');

    goHome() {
        this[NavigationMixin.Navigate]({ type: 'comm__namedPage', attributes: { name: 'Home' } });
    }
    handleNav(event) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: event.currentTarget.dataset.page }
        });
    }
}
