import { LightningElement } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import BRAND_LOGOS from "@salesforce/resourceUrl/rcBrandLogos";
import MONTSERRAT from "@salesforce/resourceUrl/rcMontserrat";
import BASE_PATH from "@salesforce/community/basePath";

// docs/brand/README.txt: logo-negative.png is cropped from night blue
// (#0D1F5F), the background of this header (rcHeader.css).
const HEADER_LOGO = "logo-negative.png";
// The Montserrat @font-face, self-hosted in the rcMontserrat static resource.
// A component stylesheet cannot declare it (shadow DOM ignores @font-face), so
// it is loaded into the page once; loadStyle skips a URL it already loaded.
const FONT_STYLESHEET = "montserrat.css";

/**
 * Site header of RutaCargo: the negative logo on night blue and the main
 * navigation. The theme layout already renders the <header> landmark around
 * this component, so it adds only the <nav> landmark.
 */
export default class RcHeader extends LightningElement {
  logoUrl = `${BRAND_LOGOS}/${HEADER_LOGO}`;
  homeUrl = `${BASE_PATH}/`;
  // 'loading', then 'loaded', or 'fallback' when the browser keeps its
  // fallback font because the stylesheet did not load.
  fontState = "loading";
  fontRequested = false;

  connectedCallback() {
    if (this.fontRequested) {
      return;
    }
    this.fontRequested = true;
    loadStyle(this, `${MONTSERRAT}/${FONT_STYLESHEET}`)
      .then(() => {
        this.fontState = "loaded";
      })
      .catch(() => {
        this.fontState = "fallback";
      });
  }
}
