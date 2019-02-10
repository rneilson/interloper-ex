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

import DatetimeController from "./controllers/datetime_controller";

const application = Application.start();
application.register("datetime", DatetimeController);

// Test hello
console.log("Uh, hi?");
