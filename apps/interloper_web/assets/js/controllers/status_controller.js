// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [ "path", "time" ];
  }

  initialize () {
    this.currentPath = window.location.pathname;
    this.currentTime = null;
    this.clockTimer = null;
  }

  connect () {
    if (this.pathTarget) {
      this.updatePath();
    }
    if (this.timeTarget) {
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
    const pathTarget = this.pathTarget;
    if (pathTarget) {
      requestAnimationFrame(() => {
        pathTarget.textContent = this.currentPath;
      });
    }
  }

  updateClock () {
    const timeTarget = this.timeTarget;
    if (timeTarget) {
      const dt = new Date();

      let h = dt.getHours() + '';
      if (h.length == 1) h = '0' + h;
      let m = dt.getMinutes() + '';
      if (m.length == 1) m = '0' + m;
      let newTime = `${h}:${m}`;

      if (newTime != this.currentTime) {
        this.currentTime = newTime;
        requestAnimationFrame(() => {
          timeTarget.textContent = this.currentTime;
        });
      }
    }
  }
}