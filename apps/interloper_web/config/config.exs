# Since configuration is shared in umbrella projects, this file
# should only configure the :interloper_web application itself
# and only for organization purposes. All other config goes to
# the umbrella root.
use Mix.Config

# General application configuration
config :interloper_web,
  generators: [context_app: :interloper]

# Configures the endpoint
config :interloper_web, InterloperWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "JvBFy2NnlcJ7SbDc4pu6u89g5T1HtcPU/s+jB7Ws9w2qr2xKOMhTF2tdZ931H8/Y",
  render_errors: [view: InterloperWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: InterloperWeb.PubSub

# Github defaults
config :interloper_web, InterloperWeb.GithubController,
  fetch_repo_commits: false

# Github client defaults
config :interloper_web, InterloperWeb.GithubClient,
  username: "rneilson"

# Twitter defaults
config :interloper_web, InterloperWeb.TwitterController,
  base_url: ["https://www.interloper.ca"],
  recent_path: "/api/twitter/recent",
  username: "delta_vee"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
