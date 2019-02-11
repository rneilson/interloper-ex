// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [ "clock", "replace" ];
  }

  initialize () {
    this.clockTimer = null;
  }

  connect () {
    this.updateClock();
    this.clockTimer = setInterval(() => this.updateClock(), 1000);
    this.replaceDatetimes();
  }

  disconnect () {
    if (this.clockTimer) {
      clearInterval(this.clockTimer);
      this.clockTimer = null;
    }
  }

  updateClock () {
    const dt = new Date();

    let h = dt.getHours() + '';
    if (h.length == 1) h = '0' + h;

    let m = dt.getMinutes() + '';
    if (m.length == 1) m = '0' + m;

    const clock = this.clockTarget;
    if (clock) {
      clock.innerHTML = `${h}:${m}`;
    }
  }

  replaceDatetimes () {
    this.element
      .querySelectorAll("[data-datetime]")
      .forEach(el => {
        console.log(el);
        let dt = new Date(el.getAttribute("data-datetime"));
        // TODO: fancier formatting
        el.innerHTML = dt.toString();
      });
  }
}
