// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";
import { dateFormat } from "../utils/datetime";

export default class extends Controller {
  static get targets () {
    return [];
  }

  initialize () {
  }

  connect () {
    this.replaceDatetimes();
  }

  disconnect () {
  }

  replaceDatetime (el) {
    let dt = new Date(el.getAttribute("data-datetime"));
    // TODO: fancier formatting
    el.textContent = dateFormat(dt);
  }

  replaceDatetimes () {
    requestAnimationFrame(() => {
      this.element
        .querySelectorAll("[data-datetime]")
        .forEach(el => this.replaceDatetime(el));
    });
  }
}
