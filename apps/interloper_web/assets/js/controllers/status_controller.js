// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [ "path", "time" ];
  }

  initialize () {
    this.currentTime = null;
    this.clockTimer = null;
  }

  connect () {
    this.updatePath();
    if (this.hasTimeTarget) {
      this.updateClock();
      this.clockTimer = setInterval(() => this.updateClock(), 1000);
    }
  }

  disconnect () {
    if (this.clockTimer) {
      clearInterval(this.clockTimer);
      this.clockTimer = null;
    }
  }

  updatePath() {
    const pathTargets = this.pathTargets;
    if (pathTargets.length > 0) {
      requestAnimationFrame(() => {
        pathTargets.forEach(el => el.textContent = window.location.pathname);
      });
    }
  }

  updateClock () {
    const dt = new Date();

    let h = dt.getHours() + '';
    if (h.length == 1) h = '0' + h;
    let m = dt.getMinutes() + '';
    if (m.length == 1) m = '0' + m;
    let newTime = `${h}:${m}`;

    if (newTime != this.currentTime) {
      this.currentTime = newTime;
      requestAnimationFrame(() => {
        this.timeTarget.textContent = this.currentTime;
      });
    }
  }
}