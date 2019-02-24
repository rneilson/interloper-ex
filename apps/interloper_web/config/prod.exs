# Since configuration is shared in umbrella projects, this file
# should only configure the :interloper_web application itself
# and only for organization purposes. All other config goes to
# the umbrella root.
use Mix.Config

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.
#
# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix phx.digest` task,
# which you should run after static files are built and
# before starting your production server.
config :interloper_web, InterloperWeb.Endpoint,
  http: [:inet6, port: System.get_env("PORT") || 4000],
  url: [host: "www.interloper.ca", port: 80]#,
  # cache_static_manifest: "priv/static/cache_manifest.json"

# ## SSL Support
#
# To get SSL working, you will need to add the `https` key
# to the previous section and set your `:url` port to 443:
#
#     config :interloper, InterloperWeb.Endpoint,
#       ...
#       url: [host: "example.com", port: 443],
#       https: [
#         :inet6,
#         port: 443,
#         cipher_suite: :strong,
#         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
#         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
#       ]
#
# The `cipher_suite` is set to `:strong` to support only the
# latest and more secure SSL ciphers. This means old browsers
# and clients may not be supported. You can set it to
# `:compatible` for wider support.
#
# `:keyfile` and `:certfile` expect an absolute path to the key
# and cert in disk or a relative path inside priv, for example
# "priv/ssl/server.key". For all supported SSL configuration
# options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
#
# We also recommend setting `force_ssl` in your endpoint, ensuring
# no data is ever sent via http, always redirecting to https:
#
#     config :interloper, InterloperWeb.Endpoint,
#       force_ssl: [hsts: true]
#
# Check `Plug.SSL` for all available options in `force_ssl`.

tls_crt = System.get_env("SITE_TLS_CRT")
cond do
  # No HSTS for now until we're stable
  is_binary(tls_crt) and tls_crt != "" ->
    # HTTPS, assume redirect
    config :interloper_web, InterloperWeb.Endpoint,
      force_ssl: [
        hsts: false,
        host: {InterloperWeb.Endpoint, :redirect_host, []},
      ]
  System.get_env("SITE_SCHEME") == "https" ->
    # Behind TLS-terminating proxy
    config :interloper_web, InterloperWeb.Endpoint,
      force_ssl: [
        hsts: false,
        host: {InterloperWeb.Endpoint, :redirect_host, []},
        rewrite_on: [:x_forwarded_proto],
      ]
end

# ## Using releases (distillery)
#
# If you are doing OTP releases, you need to instruct Phoenix
# to start the server for all endpoints:
#
#     config :phoenix, :serve_endpoints, true
#
# Alternatively, you can configure exactly which server to
# start per endpoint:
#
#     config :interloper, InterloperWeb.Endpoint, server: true
#
# Note you can't rely on `System.get_env/1` when using releases.
# See the releases documentation accordingly.

# Finally import the config/prod.secret.exs which should be versioned
# separately.
if System.get_env("INCLUDE_SECRETS") != "false" do
  import_config "prod.secret.exs"
end
