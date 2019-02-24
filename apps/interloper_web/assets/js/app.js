// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import css from "../css/app.css"

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import dependencies
//
// // TODO: see if there's anything from this to crib
// import "phoenix_html"

// Import local files
//
// Local files can be imported directly using relative paths, for example:
// import socket from "./socket"

// import { Application } from "stimulus";
import { Application } from "../vendor/stimulus.umd.js";

import PageController from "./controllers/page_controller";
import SelectController from "./controllers/select_controller";
import StatusController from "./controllers/status_controller";
import OutputController from "./controllers/output_controller";
import GithubCommitController from "./controllers/github_commit_controller";

const application = Application.start();
application.register("page", PageController);
application.register("select", SelectController);
application.register("status", StatusController);
application.register("output", OutputController);
application.register("github-commit", GithubCommitController);

// Test hello
console.log("Uh, hi?");

// Intro
if (document.body.classList.contains('intro-sequence')) {
  let timeoutMs = 250;
  for (let cls of ['inactive-x', 'inactive-y', 'intro-sequence']) {
    setTimeout(() => {
      document.querySelectorAll('.' + cls).forEach(el => el.classList.remove(cls));
    }, timeoutMs);
    timeoutMs += 500;
  }
}
