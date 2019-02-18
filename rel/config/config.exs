## Runtime configuration
use Mix.Config

# HTTP/S config
host = System.get_env("SITE_NAME") || "www.interloper.ca"
http_port = String.to_integer(System.get_env("SITE_PORT") || "80")
https_port = String.to_integer(System.get_env("SITE_PORT_HTTPS") || "443")
tls_crt = System.get_env("SITE_TLS_CRT")
tls_key = System.get_env("SITE_TLS_KEY") || tls_crt
# Creds config
github_user = System.get_env("GITHUB_USER")
github_pass = System.get_env("GITHUB_PASS")
# Other config
secret_key_base = System.get_env("SECRET_KEY_BASE")
twitter_base_url = System.get_env("TWITTER_BASE_URL")
twitter_recent_path = System.get_env("TWITTER_RECENT_PATH")

if tls_crt do
  # TLS-based setup
  config :interloper_web, InterloperWeb.Endpoint,
    url: [host: host, port: https_port],
    http: [:inet6, port: http_port],
    https: [
      :inet6,
      port: https_port,
      cipher_suite: :strong,
      certfile: tls_crt,
      keyfile: tls_key,
    ],
    force_ssl: [hsts: false]  # No HSTS for now until we're stable
else
  # HTTP-only setup
  config :interloper_web, InterloperWeb.Endpoint,
    http: [:inet6, port: http_port],
    url: [host: host, port: http_port]
end

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
