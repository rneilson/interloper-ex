// import { Controller } from "stimulus"

export default class extends Stimulus.Controller {
  static get targets () {
    return [ "clock", "replace" ];
  }

  initialize () {
    this.clockTimer = null;
  }

  connect () {
    this.updateClock();
    this.clockTimer = setInterval(() => this.updateClock(), 1000);
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
}
