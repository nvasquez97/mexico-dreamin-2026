import { LightningElement, api } from "lwc";

/**
 * Brand segmented control (native radio inputs, keyboard accessible). Replaces
 * lightning-radio-group type="button", whose colours and wrapping do not follow the brand on mobile.
 * Fires "change" with detail { value } and exposes the name like base inputs (event.target.name).
 */
export default class RcSegmented extends LightningElement {
  @api label;
  @api name;
  @api options = [];
  selected;

  @api
  get value() {
    return this.selected;
  }
  set value(v) {
    this.selected = v;
  }

  get items() {
    return (this.options || []).map((option) => {
      const checked = option.value === this.selected;
      return {
        ...option,
        checked,
        css: checked ? "option option_checked" : "option"
      };
    });
  }

  handleChange(event) {
    this.selected = event.target.value;
    this.dispatchEvent(
      new CustomEvent("change", { detail: { value: this.selected } })
    );
  }
}
