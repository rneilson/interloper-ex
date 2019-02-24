// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";

export default class extends Controller {
  static get targets () {
    return [ 'output', 'path', 'status' ];
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
      const el = e.target;
      // Get configured selectors
      const navSelector = this.data.get('navigateSelector') || 'a[href^="/"]';
      const excSelector = this.data.get('excludeSelector') || 'a[target]';
      // Allow specifying via alternate attr
      let href = el.getAttribute('href');
      if (!href || href == '#') {
        href = el.getAttribute('data-href');
      }
      // More for later, but only hrefs with relative paths
      if (href && el.matches(navSelector) && (!excSelector || !el.matches(excSelector))) {
        // Don't allow normal navigation
        e.preventDefault();
        console.log(`Navigating to ${href}`);
        // Fetch page and replace
        this.loadPage(href)
          .then(state => {
            if (state) {
              window.history.pushState(state, state.title, state.path);
            }
            else if (state === null) {
              // Invalid inline replacement, actually navigate
              window.location.href = href;
            }
          })
          ;
        return false;
      }
    }
  }

  ensureState () {
    const path = window.location.pathname;
    const title = document.title;
    // Gotta look for *something*
    const error = this.outputTarget.getAttribute("data-output-error") || "";
    // TODO: Any reason to check if currently error but valid cached?
    const html = error ? false : this.outputTarget.outerHTML;
    const state = { path: path, title: title, html: html };
    window.history.replaceState(state, title, path);
  }

  handleState (state) {
    document.title = state.title;
    console.log(`Restoring ${state.path}`);
    this.loadPage(state.path, state.html)
      .then(newState => {
        // Update state if fetch now successful
        if (newState.html && !state.html) {
          window.history.replaceState(newState, newState.title, newState.path);
        }
      })
    ;
  }

  showLoading (path) {
    // Add class to output
    const loadingClass = this.data.get('loadingClass');
    if (loadingClass) {
      this.outputTarget.classList.add(loadingClass);
    }
    // Send path update event to path target(s)
    const ev = new CustomEvent('loadPath', { detail: path });
    this.pathTargets.forEach(el => el.dispatchEvent(ev));
  }

  parsePage (html) {
    const parser = new DOMParser();
    const tree = parser.parseFromString(html, 'text/html');
    const title = tree.querySelector('head title');
    // For now, we'll assume it needs to be exactly compatible
    // TODO: parameterize id to look for?
    const output = tree.getElementById(this.outputTarget.id);
    if (!output) {
      return null;
    }
    // Clone before returning
    return {
      title: title ? title.textContent : '',
      output: output.cloneNode(true),
    };
  }

  errorPage (path, message) {
    const errTemplate = document.getElementById('page-load-error');
    // If (somehow) no error template configured, skip
    if (!errTemplate) {
      return null;
    }
    // Clone template, substitute data
    const errNode = document.importNode(errTemplate.content, true);
    const errTitle = `Error - ${path}`;
    const pathText = errNode.getElementById('error-path');
    const reasonText = errNode.getElementById('error-reason');
    if (pathText) {
      pathText.textContent = path;
    }
    if (reasonText) {
      reasonText.textContent = message;
    }
    // Return arg for replacePage()
    return { title: errTitle, output: errNode, error: message };
  }

  replacePage (path, output, title, error) {
    // Set new title, history state
    document.title = title;
    requestAnimationFrame(() => {
      // Set new output element
      const outputTarget = this.outputTarget;
      outputTarget.parentNode.replaceChild(output, outputTarget);
      // Clear status text
      // this.statusTargets.forEach(el => el.textContent = '');
    });
    // Send path update event to path target(s)
    const ev = new CustomEvent('newPath', { detail: path });
    this.pathTargets.forEach(el => el.dispatchEvent(ev));
    // Return new state
    return { path: path, title: title, html: error ? false : output.outerHTML };
  }

  loadPage (path, html) {
    const currentState = window.history.state;
    // Show loading placeholder
    this.showLoading(path);
    let promise;
    if (html) {
      // Use cached HTML
      promise = Promise.resolve(html);
    }
    else {
      // Fire off request
      // Assume origin + path is sufficient
      promise = fetch(window.location.origin + path)
        .then(res => {
          // Ensure state hasn't changed in the meantime
          if (currentState !== window.history.state) {
            console.log(`Old fetch for ${path}, ignoring`);
            return false;
          }
          // TODO: ensure HTML?
          return res.text();
        })
      ;
    }
    return promise
      .then(text => this.parsePage(text))
      .catch(err => this.errorPage(path, (err && err.message) || `Could not load ${path}`))
      .then(res => res && this.replacePage(path, res.output, res.title, res.error))
    ;
  }
}
