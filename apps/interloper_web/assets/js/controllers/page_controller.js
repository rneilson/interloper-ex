// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [ 'output', 'path' ];
  }

  initialize () {}

  connect () {
    this.ensureState();
    // TODO: compare current state, load page as req'd
  }

  disconnect () {}

  navigate (e) {
    // Only want to override if no modifiers
    if (!e.altKey && !e.shiftKey && !e.ctrlKey && !e.metaKey) {
      let el = e.target;
      let href = el.getAttribute('href');
      // More for later, but only allow relative paths
      if (href && href.startsWith('/')) {
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

  showLoading (path) {
    // TODO: move into template element
    let text = path ? `Loading ${path}` : `Loading...`;
    this.outputTarget.innerHtml = `<div class="textbox"><span class="yellow">${text}</span></div>`;
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
    // Set new output element
    requestAnimationFrame(() => {
      const outputTarget = this.outputTarget;
      outputTarget.parentNode.replaceChild(output, outputTarget);
    });
    // TODO: send path update event to path target(s)
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
      .then(({ title, output }) => this.replacePage(path, output, title))
      // TODO: catch, error display
    ;
  }
}
