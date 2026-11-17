import { LightningElement } from "lwc";
import isGuestUser from "@salesforce/user/isGuest";
import basePath from "@salesforce/community/basePath";
import ISOTYPE from "@salesforce/resourceUrl/RutaCargo_Isotype_Tinto";
import { sitePath } from "c/rcUtils";

/**
 * Site header. The brand manual requires the main logo to be at least 360 px wide, which does
 * not fit a mobile header, so the header uses the official isotype (Tinto) on its own electric
 * blue background; the full logo appears in the home hero and in the footer.
 */
export default class RcHeader extends LightningElement {
  isotypeUrl = ISOTYPE;
  isGuest = isGuestUser;
  menuOpen = false;

  homeUrl = sitePath("/");
  requestUrl = sitePath("/request-shipment");
  myShipmentsUrl = sitePath("/my-shipments");
  loginUrl = sitePath("/login");
  registerUrl = sitePath("/SelfRegister");

  get logoutUrl() {
    // LWR sites log out through the Visualforce site path ({prefix}vforcesite/secur/logout.jsp).
    const prefix = (basePath || "").replace(/\/$/, "");
    return `${prefix}vforcesite/secur/logout.jsp`;
  }

  get menuExpanded() {
    return this.menuOpen ? "true" : "false";
  }

  get navClass() {
    return this.menuOpen ? "nav nav_open" : "nav";
  }

  toggleMenu() {
    this.menuOpen = !this.menuOpen;
  }
}
