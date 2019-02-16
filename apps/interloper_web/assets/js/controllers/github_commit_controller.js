// import { Controller } from "stimulus"
import { Controller } from "../../vendor/stimulus.umd.js";
import { dateFormat } from "../utils/datetime";

export default class extends Controller {
  static get targets () {
    return [ "text", "link", "time", "err" ];
  }

  initialize () {
    // For later
    this.fetching = false;
  }

  connect () {
    const commitUrl = this.data.get('url');
    const textTarget = this.textTarget;
    // No URL specified, abort
    if (!commitUrl) {
      console.error("No commit URL given, aborting");
      if (textTarget) {
        textTarget.textContent = "Commit details unavailable"
      }
      return;
    }
    // Fetch commit details
    if (textTarget) {
      textTarget.textContent = "Loading last commit...";
    }
    this.fetching = true;
    this.fetchCommit(commitUrl)
      .then(
        res => this.displayCommit(res),
        err => this.displayError(err)
      )
      .then(() => {
        // Clear the decks
        this.fetching = false;
      });
  }

  disconnect () {
    // Not quite abort, but at least don't randomly show
    this.fetching = false;
  }

  fetchCommit (commitUrl) {
    // console.log(`Fetching commit at ${commitUrl}`);
    return fetch(commitUrl)
      .then(res => {
        if (res.ok) {
          return res.json();
        }
        console.error(`GET ${commitUrl} returned status ${res.status}`);
        throw new Error(`Couldn't retrieve commit`);
      });
  }

  displayCommit (commit) {
    if (this.fetching) {
      requestAnimationFrame(() => {
        // Show text
        const textTarget = this.textTarget;
        if (textTarget) {
          textTarget.textContent = 'Last commit:';
        }
        // Show commit sha, set link
        const linkTarget = this.linkTarget;
        if (linkTarget) {
          linkTarget.setAttribute('href', commit.html_url);
          linkTarget.textContent = commit.sha.substr(0, 7);
        }
        // Show commit datetime
        const timeTarget = this.timeTarget;
        if (timeTarget) {
          timeTarget.textContent = dateFormat(new Date(commit.commit.author.date));
        }
      });
    }
  }

  displayError (err) {
    console.error(err);
    const errTarget = this.errTarget;
    if (errTarget) {
      errTarget.textContent = err.message || `${err}`;
    }
  }
}
