import { LightningElement } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import isGuest from '@salesforce/user/isGuest';
import basePath from '@salesforce/community/basePath';
import BRAND from '@salesforce/resourceUrl/rcBrand';

/**
 * Site header. Uses the official logo files of docs/brand: the main colour logo
 * on white at its 360 px minimum screen width, and the Tinto isotype on electric
 * blue when the screen is too narrow for the full logo. Loads the Montserrat
 * fonts for the whole site.
 */
export default class RcHeader extends LightningElement {
    isGuest = isGuest;
    menuOpen = false;
    logoColorUrl = `${BRAND}/img/logo-color.png`;
    isotypeUrl = `${BRAND}/img/isotype-tinto.png`;
    homeUrl = `${basePath}/`;
    loginUrl = `${basePath}/login`;
    registerUrl = `${basePath}/SelfRegister`;
    requestUrl = `${basePath}/request-shipment`;
    myShipmentsUrl = `${basePath}/my-shipments`;
    logoutUrl = `${basePath.replace(/\/s$/i, '')}/secur/logout.jsp`;

    connectedCallback() {
        loadStyle(this, `${BRAND}/brand.css`).catch(() => {
            // Fonts fall back to the system sans-serif; the site keeps working.
        });
    }

    get menuExpanded() {
        return String(this.menuOpen);
    }

    get navClass() {
        return this.menuOpen ? 'rc-header__nav rc-header__nav_open' : 'rc-header__nav';
    }

    toggleMenu() {
        this.menuOpen = !this.menuOpen;
    }
}
