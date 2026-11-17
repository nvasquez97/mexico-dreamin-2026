import { LightningElement } from "lwc";
import LOGO_NEGATIVE from "@salesforce/resourceUrl/RutaCargo_Logo_Negative";

export default class RcFooter extends LightningElement {
  logoNegativeUrl = LOGO_NEGATIVE;
  year = new Date().getFullYear();
}
