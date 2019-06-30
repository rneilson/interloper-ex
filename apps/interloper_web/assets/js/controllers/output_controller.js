// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";
import { insertDatetime } from "../utils/datetime";

export default class extends Controller {
  static get targets () {
    return [ 'initFocus' ];
  }

  initialize () {
  }

  connect () {
    requestAnimationFrame(() => {
      this.replaceDatetimes();
      if (this.hasInitFocusTarget) {
        this.initFocusTarget.focus();
      }
      else {
        this.element.focus();
      }
    });
  }

  disconnect () {
  }

  replaceDatetimes () {
    this.element
      .querySelectorAll("[data-datetime]")
      .forEach(el => insertDatetime(el, el.getAttribute("data-datetime")));
  }
}
