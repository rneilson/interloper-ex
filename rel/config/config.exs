## Runtime configuration
use Mix.Config

# Internal config
secret_key_base = System.get_env("SECRET_KEY_BASE")
# External config
github_user = System.get_env("GITHUB_USER")
github_pass = System.get_env("GITHUB_PASS")
twitter_base_url = System.get_env("TWITTER_BASE_URL")
twitter_recent_path = System.get_env("TWITTER_RECENT_PATH")

if secret_key_base do
  config :interloper_web, InterloperWeb.Endpoint,
    secret_key_base: secret_key_base
end

if github_user do
  config :interloper_web, InterloperWeb.GithubClient,
    username: github_user
end

if github_pass do
  config :interloper_web, InterloperWeb.GithubClient,
    password: github_pass
end

if twitter_base_url do
  config :interloper_web, InterloperWeb.TwitterController,
    base_url: String.split(twitter_base_url)
end

if twitter_recent_path do
  config :interloper_web, InterloperWeb.TwitterController,
    recent_path: twitter_recent_path
end
