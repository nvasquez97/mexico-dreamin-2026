import { LightningElement } from "lwc";
import { loadStyle } from "lightning/platformResourceLoader";
import BRAND_LOGOS from "@salesforce/resourceUrl/rcBrandLogos";
import MONTSERRAT from "@salesforce/resourceUrl/rcMontserrat";
import BASE_PATH from "@salesforce/community/basePath";

// docs/brand/README.txt: logo-negative.png is cropped from night blue
// (#0D1F5F), the background of this header (rcHeader.css); it is shown only
// where its visible artwork fits at the manual's minimum width, 360 px
// (manual p.4): a 440 px box, since the PNG keeps a margin around the artwork.
const HEADER_LOGO = "logo-negative.png";
// isotype-tinto.png is cropped from electric blue (#016BFA), the tile it sits
// on; it stands in for the full logo on narrow screens (manual p.5: the other
// versions exist "cuando el tamaño lo pide").
const HEADER_ISOTYPE = "isotype-tinto.png";
// The Montserrat @font-face, self-hosted in the rcMontserrat static resource.
// A component stylesheet cannot declare it (shadow DOM ignores @font-face), so
// it is loaded into the page once; loadStyle skips a URL it already loaded.
const FONT_STYLESHEET = "montserrat.css";

/**
 * Site header of RutaCargo: the brand mark on night blue (the isotype on its
 * tile on narrow screens, the full negative logo with at least 360 px of
 * visible artwork on wider ones) and
 * the main navigation. The theme layout already renders the <header> landmark
 * around this component, so it adds only the <nav> landmark.
 */
export default class RcHeader extends LightningElement {
  logoUrl = `${BRAND_LOGOS}/${HEADER_LOGO}`;
  isotypeUrl = `${BRAND_LOGOS}/${HEADER_ISOTYPE}`;
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
