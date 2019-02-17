// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [];
  }

  initialize () {
    // Here instead of constructor just to keep clean
    this.keymap = {
      'Escape': this.deselect,
      'ArrowUp': this.selectUp,
      'ArrowDown': this.selectDown,
      // 'Tab': this.selectDown,
    };
    this.codemap = {
      // 9: 'Tab',
      27: 'Escape',
      38: 'ArrowUp',
      40: 'ArrowDown',
    };
  }

  connect () {}

  disconnect () {}

  handleKey (e) {
    if (e.defaultPrevented) {
      return;
    }

    let key;
    let handled = false;
    let el = e.target;
    let tag = el.tagName;
    // Don't fire if in input, textarea, select, or contenteditable elements
    if (
      tag == 'INPUT' ||
      tag == 'TEXTAREA' ||
      tag == 'SELECT' ||
      (el.contentEditable && el.contentEditable == 'true')
    ) {
      return;
    }

    if (!e.altKey && !e.shiftKey && !e.ctrlKey && !e.metaKey) {
      if (e.key !== undefined){
        key = this.keymap[e.key];
      }
      if (key === undefined && e.keyCode !== undefined) {
        let code = this.codemap[e.keyCode];
        if (code !== undefined) {
          key = this.keymap[code];
        }
      }

      if (key !== undefined) {
        handled = true;
        key.apply(this);
      }
    }

    if (handled) {
      e.preventDefault();
      return false;
    }
  }

  getSelectors () {
    return Array.from(this.element.querySelectorAll('.selector'));
  }

  selectUp () {
    // Select previous entry
    const selectors = this.getSelectors();
    let idx = selectors.indexOf(document.activeElement);
    if (idx <= 0) {
      idx = selectors.length;
    }
    this.select(selectors[idx - 1]);
  }

  selectDown () {
    // Select next entry
    const selectors = this.getSelectors();
    let idx = selectors.indexOf(document.activeElement);
    if (idx < 0 || idx == selectors.length - 1) {
      idx = -1;
    }
    this.select(selectors[idx + 1]);
  }

  select (el) {
    if (el) {
      if (el != document.activeElement) {
        el.focus();
      }
      // Anything else?
    }
    else {
      // Easier to forward tbh
      this.deselect();
    }
  }

  deselect () {
    // Clear selection
    if (document.activeElement) {
      document.activeElement.blur();
    }
  }
}