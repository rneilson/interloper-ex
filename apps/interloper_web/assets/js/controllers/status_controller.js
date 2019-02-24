// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [ 'path', 'load', 'time' ];
  }

  initialize () {
    this.currentTime = null;
    this.clockTimer = null;
    this.reqFrame = null;
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

  loadingPath(ev = {}) {
    const pathTargets = this.pathTargets;
    const loadTargets = this.loadTargets;
    const loadPath = ev.detail ? `${ev.detail} loading...` : 'Loading...';
    if (pathTargets.length > 0 || loadTargets.length > 0) {
      this.reqFrame = requestAnimationFrame(() => {
        this.reqFrame = null;
        pathTargets.forEach(el => el.textContent = '');
        loadTargets.forEach(el => el.textContent = loadPath);
      });
    }
  }

  updatePath(ev = {}) {
    const pathTargets = this.pathTargets;
    const loadTargets = this.loadTargets;
    const newPath = ev.detail || window.location.pathname;
    if (pathTargets.length > 0 || loadTargets.length > 0) {
      if (this.reqFrame) {
        cancelAnimationFrame(this.reqFrame);
      }
      this.reqFrame = requestAnimationFrame(() => {
        this.reqFrame = null;
        pathTargets.forEach(el => el.textContent = newPath);
        loadTargets.forEach(el => el.textContent = '');
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