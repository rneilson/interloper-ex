defmodule InterloperWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :interloper_web

  # # TODO: reenable once we're ready to do websocket stuff
  # socket "/socket", InterloperWeb.UserSocket,
  #   websocket: true,
  #   longpoll: false

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :interloper_web,
    gzip: true,
    only_matching: ~w(css fonts images js rampant favicon pubkey)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # # TODO: reenable if/when we ever use sessions
  # # (probably via Redis instead of cookies, too)
  # # The session will be stored in the cookie and signed,
  # # this means its contents can be read but not tampered with.
  # # Set :encryption_salt if you would also like to encrypt it.
  # plug Plug.Session,
  #   store: :cookie,
  #   key: "_interloper_web_key",
  #   signing_salt: "VpTe81l8"

  plug InterloperWeb.Router

  # Conditional configuration via OS env vars
  def init(_key, config) do
    # URL and port config -- note, assumes base config already in env
    port =
      case System.get_env("PORT") do
        nil -> (Keyword.get(config, :http) || []) |> Keyword.get(:port, 4000)
        port_str -> String.to_integer(port_str)
      end
    port_https =
      case System.get_env("PORT_HTTPS") do
        nil -> (Keyword.get(config, :https) || []) |> Keyword.get(:port, 4040)
        port_str -> String.to_integer(port_str)
      end
    site_host =
      case System.get_env("SITE_NAME") do
        nil -> Keyword.get(config, :url, []) |> Keyword.get(:host, "localhost")
        site_name -> site_name
      end
    site_port =
      case System.get_env("SITE_PORT") do
        nil -> nil
        port_ -> String.to_integer(port_)
      end
    site_scheme = System.get_env("SITE_SCHEME")
    # HTTP/S config
    tls_crt = System.get_env("SITE_TLS_CRT")
    tls_cacrt = System.get_env("SITE_TLS_CA") || nil
    tls_key = System.get_env("SITE_TLS_KEY") || tls_crt
    # Return either TLS-enabled or HTTP-only
    overrides =
      cond do
        is_binary(tls_crt) and tls_crt != "" ->
          ca_opts =
            case tls_cacrt do
              nil -> []
              cacertfile -> [cacertfile: cacertfile]
            end
          # HTTPS, assume redirect
          # Set HTTP and HTTPS listeners, force redirect
          [
            url: [host: site_host, port: site_port || port_https, scheme: "https"],
            http: [:inet6, port: port, compress: true],
            https: [
              :inet6,
              port: port_https,
              cipher_suite: :strong,
              certfile: tls_crt,
              keyfile: tls_key,
            ] ++ ca_opts,
          ]
        site_scheme == "https" ->
          # Behind TLS-terminating proxy
          # Set HTTP, force scheme
          [
            url: [host: site_host, port: site_port || port, scheme: "https"],
            http: [:inet6, port: port],
            https: false,
          ]
        true ->
          # HTTP-only, direct (probably local)
          [
            url: [host: site_host, port: port],
            http: [:inet6, port: port, compress: true],
            https: false,
          ]
      end
    # Possibly override secret key
    new_config = 
      case System.get_env("SECRET_KEY_BASE") do
        nil ->
          overrides
        secret_key_base ->
          Keyword.put(overrides, :secret_key_base, secret_key_base)
      end
    # Merge with provided config
    {:ok, Keyword.merge(config, new_config)}
  end

  # Get configured HTTPS redirect URL
  # Done as a callback so we can pass it to Plug.SSL at compile time
  def redirect_host do
    url = config(:url)
    host = url[:host]
    port = url[:port]
    # Sneak in nonstandard port if cfg'd
    if port == 443, do: host, else: "#{host}:#{port}"
  end
end
