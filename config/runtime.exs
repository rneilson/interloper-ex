import Config

# TODO: move any other runtime secrets here

# Phoenix config
if System.get_env("SERVE_ENDPOINTS") != "false" do
  config :phoenix, :serve_endpoints, true
end

# Github config
if github_user = System.get_env("GITHUB_USER") do
  config :interloper_web, InterloperWeb.GithubClient,
    username: github_user
end
if github_pass = System.get_env("GITHUB_PASS") do
  config :interloper_web, InterloperWeb.GithubClient,
    password: github_pass
end

# Twitter (proxy) config
if twitter_base_url = System.get_env("TWITTER_BASE_URL") do
  config :interloper_web, InterloperWeb.TwitterController,
    base_url: String.split(twitter_base_url)
end
if twitter_recent_path = System.get_env("TWITTER_RECENT_PATH") do
  config :interloper_web, InterloperWeb.TwitterController,
    recent_path: twitter_recent_path
end
