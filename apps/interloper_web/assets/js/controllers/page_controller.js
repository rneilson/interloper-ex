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
    this.outputId = this.outputTarget.id;
    // Handle popstate (ie back)
    if (!this.stateHandler) {
      this.stateHandler = e => this.handleState(e.state);
      window.addEventListener('popstate', this.stateHandler);
    }
    // Init or refresh state
    this.ensureState();
  }

  disconnect () {
    if (this.stateHandler) {
      window.removeEventListener('popstate', this.stateHandler);
      this.stateHandler = null;
    }
  }

  getOutput () {
    return this.element.querySelector('#' + this.outputId);
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
    const state = window.history.state;
    const title = document.title;
    const path = window.location.pathname;
    // Gotta look for *something* (can't check status code on first page load)
    const error = this.getOutput().getAttribute('data-output-error') || '';
    const html = error ? false : this.getOutput().outerHTML;
    if (!state || (!error && state.html != html)) {
      // Set state if empty, reset if refreshed
      const newState = { path: path, title: title, html: html };
      console.log(`${state ? 'Resetting' : 'Setting'} state for ${path}`);
      window.history.replaceState(newState, title, path);
    }
  }

  handleState (state) {
    document.title = state.title;
    console.log(`Restoring ${state.path}`);
    this.loadPage(state.path, state.html)
      .then(newState => {
        // Update state if fetch now successful
        if (newState.html && newState.html != state.html) {
          console.log(`Updated ${state.path}`);
          window.history.replaceState(newState, newState.title, newState.path);
        }
      })
    ;
  }

  showLoading (path) {
    // Add class to output
    const loadingClass = this.data.get('loadingClass');
    if (loadingClass) {
      this.getOutput().classList.add(loadingClass);
    }
    // Send path update event to path target(s)
    const ev = new CustomEvent('loadPath', { detail: path });
    this.pathTargets.forEach(el => el.dispatchEvent(ev));
  }

  parsePage (html, error) {
    const parser = new DOMParser();
    const tree = parser.parseFromString(html, 'text/html');
    const title = tree.querySelector('head title');
    // For now, we'll assume it needs to be exactly compatible
    // TODO: parameterize id to look for?
    const output = tree.getElementById(this.outputId);
    if (!output) {
      return null;
    }
    // Clone before returning
    return {
      title: title ? title.textContent : '',
      output: output.cloneNode(true),
      error: error || output.getAttribute('data-output-error') || '',
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
      const outputTarget = this.getOutput();
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
    // Fire off request
    // Assume origin + path is sufficient
    return fetch(window.location.origin + path)
      .then(res => {
        // Ensure state hasn't changed in the meantime
        if (currentState !== window.history.state) {
          console.log(`Old fetch for ${path}, ignoring`);
          return false;
        }
        // TODO: ensure HTML?
        const error = res.ok ? '' : res.statusText;
        return res.text().then(text => this.parsePage(text, error));
      })
      .catch(err => {
        const msg = (err && err.message) || `Could not load ${path}`;
        console.error(`Error loading ${path}: ${msg}`);
        // If fetch errors out, use cached (state) html if available
        if (html) {
          console.log('Using cached HTML from state');
          return this.parsePage(html);
        }
        // Otherwise generate error page
        return this.errorPage(path, msg);
      })
      .then(res => res && this.replacePage(path, res.output, res.title, res.error))
    ;
  }
}
