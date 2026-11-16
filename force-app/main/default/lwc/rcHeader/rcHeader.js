import { LightningElement } from 'lwc';
import isGuestUser from '@salesforce/user/isGuest';
import basePath from '@salesforce/community/basePath';
import BRAND from '@salesforce/resourceUrl/RutaCargoBrand';

export default class RcHeader extends LightningElement {
    isGuest = isGuestUser;

    connectedCallback() {
        // Montserrat is self-hosted in the RutaCargoBrand static resource (no third-party font calls).
        try {
            if (typeof FontFace !== 'undefined' && !window.__rcFontLoaded) {
                window.__rcFontLoaded = true;
                const font = new FontFace('Montserrat', `url(${BRAND}/fonts/Montserrat-latin-variable.woff2)`, { weight: '100 900' });
                font.load().then((loaded) => document.fonts.add(loaded)).catch(() => {});
            }
        } catch (e) {
            // Falls back to the system font stack.
        }
    }

    get logoUrl() { return `${BRAND}/logos/logo-negative.png`; }
    get homeUrl() { return `${basePath}/`; }
    get loginUrl() { return `${basePath}/login`; }
    get registerUrl() { return `${basePath}/SelfRegister`; }
    get requestUrl() { return `${basePath}/request-shipment`; }
    get mineUrl() { return `${basePath}/my-shipments`; }
    get logoutUrl() { return `${basePath.replace(/\/s$/, '')}/secur/logout.jsp`; }
}
