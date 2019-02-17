// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [ 'output', 'status', ];
  }

  initialize () {
    this.stateHandler = null;
  }

  connect () {
    this.ensureState();
    // Handle popstate (ie back)
    if (!this.stateHandler) {
      this.stateHandler = e => this.handleState(e.state);
      window.addEventListener('popstate', this.stateHandler);
    }
    // TODO: compare current state, load page as req'd
  }

  disconnect () {
    if (this.stateHandler) {
      window.removeEventListener('popstate', this.stateHandler);
      this.stateHandler = null;
    }
  }

  navigate (e) {
    // Only want to override if no modifiers
    if (!e.altKey && !e.shiftKey && !e.ctrlKey && !e.metaKey) {
      let el = e.target;
      let href = el.getAttribute('href');
      // More for later, but only allow relative paths
      if (href && href.startsWith('/')) {
        // Don't allow normal navigation
        e.preventDefault();
        console.log(`Navigating to ${href}`);
        // Push new state
        const title = `Loading ${href}`;
        window.history.pushState({ path: href, title: title }, title, href);
        // Fetch page and replace
        this.loadPage(href);
        return false;
      }
    }
  }

  ensureState () {
    if (!window.history.state) {
      const path = window.location.pathname;
      const title = document.title;
      window.history.replaceState({ path: path, title: title }, title, path);
    }
  }

  handleState (state) {
    document.title = state.title;
    console.log(`Restoring ${state.path}`);
    this.loadPage(state.path);
  }

  showLoading (path) {
    // Add class to output
    const loadingClass = this.data.get('loadingClass');
    if (loadingClass) {
      this.outputTarget.classList.add(loadingClass);
    }
    // Set status text
    const ev = new Event('loadPath', { detail: path });
    this.statusTargets.forEach(el => el.dispatchEvent(ev));
  }

  parsePage (html) {
    const parser = new DOMParser();
    const tree = parser.parseFromString(html, 'text/html');
    const title = tree.querySelector('head title');
    // For now, we'll assume it needs to be exactly compatible
    // TODO: parameterize id to look for?
    const output = tree.getElementById('output');
    if (!output) {
      throw new Error(`Couldn't find output element in retrieved page`);
    }
    // Clone before returning
    return {
      title: title ? title.textContent : '',
      output: output.cloneNode(true),
    }
  }

  replacePage (path, output, title) {
    // Set new title, history state
    document.title = title;
    window.history.replaceState({ path: path, title: title }, title, path);
    requestAnimationFrame(() => {
      // Set new output element
      const outputTarget = this.outputTarget;
      outputTarget.parentNode.replaceChild(output, outputTarget);
    });
    // Send path update event to path target(s)
    const ev = new Event('newPath', { detail: path });
    this.statusTargets.forEach(el => el.dispatchEvent(ev));
  }

  loadPage (path) {
    const currentState = window.history.state;
    // Show loading placeholder
    this.showLoading(path);
    // Fire off request
    // Assume origin + path is sufficient
    fetch(window.location.origin + path)
      .then(res => {
        if (!res.ok) {
          console.error(`Got ${res.status} fetching ${path}`);
          throw new Error(`Couldn't retrieve ${path}`);
        }
        // Ensure state hasn't changed in the meantime
        if (currentState !== window.history.state) {
          console.log(`Old fetch for ${path}, ignoring`);
          return null;
        }
        // TODO: ensure HTML?
        return res.text();
      })
      .then(text => this.parsePage(text))
      .then(res => this.replacePage(path, res.output, res.title))
      // TODO: catch, error display
    ;
  }
}
