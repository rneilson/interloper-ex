defmodule InterloperWeb.CachingClient do
  @moduledoc """
  Interface to an external API, with persistent caching
  to reduce external calls and avoid rate limits.

  Each request URL gets its own persistent process to
  cache the response (default 60s), send authorization
  and if-none-matches headers as appropriate in API
  calls, and otherwise deduplicate requests.

  The :base_url option is required; the :base_name,
  :cache_timeout, :expire_timeout, :use_registry,
  and :cache_supervisor options are not.
  """

  use GenServer, restart: :temporary
  require Logger

  @config %{
    raw: false,                     # Return decoded JSON
    base_url: "",                   # Allow all URLs
    base_name: __MODULE__,          # Use module name
    cache_timeout: 1 * 60 * 1000,   # Cache valid for 1m
    expire_timeout: 60 * 60 * 1000, # Expire after 60m
  }

  @callback get_auth_header(url :: binary) :: binary | nil
  @callback get_config() :: map
  @optional_callbacks get_auth_header: 1, get_config: 0

  @doc false
  defmacro __using__(opts \\ []) do
    %{module: module} = __CALLER__
    config_overrides =
      opts
      |> Enum.into(%{})
      |> Map.take(Map.keys(@config))
    config =
      @config
      |> Map.merge(config_overrides)
      |> Map.put(:base_name, module)

    quote location: :keep do
      @behaviour InterloperWeb.CachingClient

      @config unquote(Macro.escape(config))

      @spec fetch(url :: binary) :: {:ok, term} | {:error, term}
      def fetch(url) when is_binary(url) do
        InterloperWeb.CachingClient.fetch(url, @config)
      end

      @spec find_pid(url :: binary) :: pid | nil
      def find_pid(url) when is_binary(url) do
        InterloperWeb.CachingClient.find_pid(url, @config)
      end

      @spec find_pid(url :: binary) :: binary | nil
      def get_auth_header(url), do: nil
      defoverridable get_auth_header: 1

      @spec get_config() :: map
      def get_config(), do: @config
      defoverridable get_config: 0
    end
  end


  ## Client

  @doc """
  Retrives (possibly-cached) response from API at
  given `url`, creating new process and updating
  cached response as required.

  Returns {:ok, response} or {:error, reason}.
  """
  @spec fetch(url :: binary, config :: map) :: {:ok, term} | {:error, term}
  def fetch(url, config \\ nil) when is_binary(url) do
    # Ensure server started or get existing
    case get_or_create_server(url, get_config(config)) do
      {:ok, pid} -> GenServer.call(pid, :fetch)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Makes HTTP request to specified URL.
  Primarily for use by async tasks spawned by caching
  processes.

  Options:
  * `:auth` - value of `Authorization` header
  * `:etag` - value of `If-None-Match` header

  Returns raw HTTPoison response struct.
  """
  @spec fetch_raw(url :: binary, opts :: keyword) :: any
  def fetch_raw(url, opts \\ []) when is_binary(url) do
    # Headers
    # TODO: if-modified-since?
    headers =
      [{"Accept", "application/json"}]
      |> add_header("Authorization", opts[:auth])
      |> add_header("If-None-Match", opts[:etag])
    # Options
    options = [ follow_redirect: true, ssl: [{:versions, [:'tlsv1.2']}] ]
    # TEMP: remove this later?
    Logger.debug("Request url: #{url}")
    Logger.debug("Request headers: #{inspect(headers)}")
    # Make request
    # TODO: better way to indicate test/mock url?
    if binary_part(url, 0, 2) == "_/" do
      # Get fake response
      mock_response(%{ method: :get, url: url, headers: headers, options: options })
    else
      HTTPoison.request!(:get, url, "", headers, options)
    end
  end

  @doc """
  Finds PID of existing cache process for `url`, if
  one exists.
  """
  @spec find_pid(url :: binary, config :: map) :: pid | nil
  def find_pid(url, config \\ nil) when is_binary(url) do
    # May raise
    name = get_name(url, get_config(config))
    # Try looking up existing process for this url
    case Registry.lookup(InterloperWeb.Registry, name) do
      [{pid, _} | _] -> pid
      [] -> nil
    end
  end

  # TODO: guard for url? Check config?
  def start_link({url, config}) do
    GenServer.start_link(__MODULE__, {url, config}, name: get_via_tuple(url, config))
  end


  ## Server (callbacks)

  def init({url, config}) do
    # Initial state
    state =
      create_new_state(url, config)
      |> reset_expiry_timer(config[:expire_timeout])
    Logger.debug("Started new cache process for #{url} (#{config[:base_name]})")
    # TODO: continue?
    {:ok, state}
  end

  def code_change(_old_vsn, %{config: %{base_name: __MODULE__}} = state, _extra) do
    Logger.debug("Code change callback for #{__MODULE__}")
    {:ok, %{state | config: @config}}
  end

  def code_change(_old_vsn, %{config: %{base_name: base_name}} = state, _extra) do
    Logger.debug("Code change callback for #{base_name}")
    config = apply(base_name, :get_config, [])
    {:ok, %{state | config: config}}
  end

  # TODO: handle_continue to send first timeout message?

  # Cache valid, return existing
  def handle_call(:fetch, _from, %{url: url, body: body, cache_valid: true} = state) do
    Logger.debug("Returning cached data for #{url}")
    {:reply, {:ok, body}, state}
  end

  # Cache not valid and no task dispatched, refetch
  def handle_call(:fetch, from, %{ref: nil, callers: callers, cache_valid: false} = state) do
    # Get auth, body, url, config, and cache tag from state
    # (Separate just to keep it clean)
    %{url: url, body: old_body, auth: auth, cache_tag: cache_tag} = state
    # Only set etag header if body present
    etag = if is_nil(old_body), do: nil, else: cache_tag
    # Dispatch new task
    task = Task.Supervisor.async_nolink(
      InterloperWeb.TaskSupervisor, __MODULE__, :fetch_raw, [url, [auth: auth, etag: etag]])
    # Add caller to list, keep task ref, wait for response
    {:noreply, %{state | ref: task.ref, callers: [from | callers]}}
  end

  # Cache not valid and task already dispatched, add caller
  def handle_call(:fetch, from, %{ref: _ref, callers: callers, cache_valid: false} = state) do
    # Save new caller for when task returns
    {:noreply, %{state | callers: [from | callers]}}
  end

  # Task complete, reply to callers and update cache
  def handle_info({ref, response}, %{ref: ref} = state) do
    %{body: old_body, callers: callers, expire_ref: expire_ref, config: config} = state
    # Demonitor task
    Process.demonitor(ref, [:flush])
    # TEMP: remove this later?
    Logger.debug("Response url: #{response.request_url}")
    Logger.debug("Response code: #{inspect(response.status_code)}")
    Logger.debug("Response headers: #{inspect(response.headers)}")
    # Parse response
    {success, headers, body} = parse_response(response, old_body, config)
    # Reply to previous callers
    reply_to_callers({success, body}, callers)
    # Update state
    new_state =
      case success do
        :ok ->
          # Send cache timeout message
          if config[:cache_timeout] do
            Process.send_after(self(), :invalidate_cache, config[:cache_timeout])
          end
          # Update cached values and extend expiry
          new_tag = Map.get(headers, "etag")
          new_ref = reset_expiry_timer(expire_ref, config[:expire_timeout])
          %{state | body: body, cache_tag: new_tag, cache_valid: true, expire_ref: new_ref}
        _ ->
          # Clear cached values on any error, keep expiry
          %{state | body: nil, cache_tag: nil, cache_valid: false}
      end
    # Clear task ref and callers list regardless
    {:noreply, %{new_state | ref: nil, callers: []}}
  end

  # Task failed, reply to callers and clear cache
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{ref: ref} = state) do
    %{url: url, callers: callers} = state
    # Reply to previous callers (obscure real error, though)
    reply_to_callers({:error, "Request failed for #{url}"}, callers)
    # Shut down, request failed
    {:stop, :request_failed, state}
  end

  # Cache timed out, update state
  def handle_info(:invalidate_cache, %{url: url, ref: nil, cache_valid: true} = state) do
    Logger.debug("Invalidating cache for #{url}")
    {:noreply, %{state | cache_valid: false}}
  end

  # Request in progress or cache already invalid, keep state
  def handle_info(:invalidate_cache, state) do
    {:noreply, state}
  end

  # Request in progress, don't terminate
  def handle_info(:timeout, %{url: url, ref: ref, config: config} = state) when is_reference(ref) do
    timeout = config[:cache_timeout] || 1000
    Logger.debug("Extending expiry timeout for #{url} by #{timeout} ms")
    # TODO: pick a better extension time limit?
    {:noreply, reset_expiry_timer(state, timeout)}
  end

  # Cache process expired, terminate
  def handle_info(:timeout, %{url: url} = state) do
    Logger.debug("Shutting down cache for #{url}")
    {:stop, :normal, state}
  end


  ## Internal (utilities)

  # Get (possibly-composite) configuration
  # Maps will be used as-is
  # Keyword lists will be merged with defaults
  defp get_config(config) do
    # TODO: allow functions and {module, function} tuples
    cond do
      !config -> @config
      is_map(config) -> config
      is_list(config) -> Map.merge(@config, Enum.into(config, %{}))
      true -> raise ArgumentError, "Invalid config: #{inspect(config)}"
    end
  end

  # Get auth header via callback
  defp get_auth_header(_url, %{base_name: __MODULE__} = _config), do: nil

  defp get_auth_header(url, %{base_name: module} = _config) when is_atom(module) do
    apply(module, :get_auth_header, [url])
  end

  # Fresh state
  # TODO: move to its own struct type?
  defp create_new_state(url, config) do
    # Get username/password, construct header
    auth = get_auth_header(url, config)
      # with user when is_binary(user) <- config[:username],
      #      pass when is_binary(pass) <- config[:password]
      # do
      #   "Basic " <> Base.encode64(user <> ":" <> pass)
      # else
      #   _ -> nil
      # end
    # New state map
    # TODO: make struct
    %{
      url: url,
      body: nil,
      auth: auth,
      ref: nil,
      callers: [],
      cache_tag: nil,
      cache_valid: false,
      expire_ref: nil,
      config: config,
    }
  end

  # Get name tuple for use with registries.
  @spec get_name(url :: binary, config :: map) :: {term, binary}
  defp get_name(url, config) when is_binary(url) do
    unless config[:base_name] do
      raise ArgumentError, "Invalid base name: #{inspect(config[:base_name])}"
    end
    case get_full_url(url, config) do
      {:ok, full_url} -> {config[:base_name], full_url}
      {:error, reason} -> raise ArgumentError, "#{reason}"
    end
  end

  # Get the full URL for given URL or path, validating against base URL
  # Returns {:ok, url} or {:error, reason}
  @spec get_full_url(url :: binary, config :: map) :: {:ok, binary} | {:error, term}
  defp get_full_url(url, config) do
    cond do
      binary_part(url, 0, 1) == "/" ->
        # TODO: less-simplistic check?
        {:ok, config[:base_url] <> url}
      String.starts_with?(url, config[:base_url]) ->
        # TODO: less-simplistic check?
        {:ok, url}
      !config[:base_url] ->
        # Misconfigured
        {:error, "Invalid base URL: #{config[:base_url]}"}
      true ->
        # Catch-else clause
        {:error, "Invalid URL: #{url}"}
    end
  end

  # Get via tuple for use with registries
  @spec get_via_tuple(url :: binary, config :: map) :: {:via, atom, term}
  defp get_via_tuple(url, config) when is_binary(url) do
    {:via, Registry, {InterloperWeb.Registry, get_name(url, config)}}
  end

  # Cancels existing expiry timeout, if any, and starts new one
  @spec reset_expiry_timer(current :: map | reference | nil, timeout :: integer) :: reference
  defp reset_expiry_timer(current, timeout)

  defp reset_expiry_timer(state, timeout) when is_map(state) do
    %{state | expire_ref: reset_expiry_timer(Map.get(state, :expire_ref), timeout)}
  end

  defp reset_expiry_timer(expire_ref, timeout) when is_reference(expire_ref) do
    Process.cancel_timer(expire_ref)
    reset_expiry_timer(nil, timeout)
  end

  defp reset_expiry_timer(expire_ref, timeout) when is_nil(expire_ref) do
    Logger.debug("Expiry in #{timeout} ms")
    Process.send_after(self(), :timeout, timeout)
  end

  # Finds the registered server for `url`, if
  # it exists, or creates one if not.
  # Returns {:ok, pid} or {:error, reason}.
  @spec get_or_create_server(url :: binary, config :: map) :: {:ok, pid} | {:error, any}
  defp get_or_create_server(url, config) do
    case get_full_url(url, config) do
      {:ok, url} ->
        # Try looking up existing process for this url
        case find_pid(url, config) do
          nil ->
            # Spawn a new process for this url
            Logger.debug("Spawning new cache process for #{url}")
            # TODO: parameterize supervisor name?
            DynamicSupervisor.start_child(
              InterloperWeb.DynamicSupervisor, {__MODULE__, {url, config}})
          pid ->
            # Return first found -- shouldn't be an issue with unique keys
            {:ok, pid}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Conditionally returns header if `value` given
  defp add_header(headers, name, value) when byte_size(value) > 0 do
    headers ++ [{name, value}]
  end
  defp add_header(headers, _name, _value) do
    headers
  end

  # Reply to all stored callers
  defp reply_to_callers(response, callers) do
    # TODO: some error handling?
    Enum.map(callers, fn from -> GenServer.reply(from, response) end)
  end

  # Parse HTTP response
  # Returns {success, headers, body}, where `success` is
  # one of :ok or :error, and `body` may be the given
  # `old_body` on status code 304 or 429
  # Current config options include:
  # - {:raw, bool()}
  @spec parse_response(response :: term, old_body :: term, config :: map) :: {atom, map, term}
  defp parse_response(response, old_body, config) do
    # Get headers, attempt decoding response body
    # Lowercase header names for easier future use
    headers =
      response.headers
      |> Enum.map(fn {name, value} -> {String.downcase(name), value} end)
      |> Enum.into(%{})
    {decode_success, new_body} =
      case config[:raw] do
        true -> {:ok, {:raw, response.body}}
        _ -> Jason.decode(response.body, strings: :copy)
      end
    # Check status code, plus decode success, for overall success/error
    case {response.status_code, decode_success} do
      # Return cached response body if rate-limited
      {429, _} when not is_nil(old_body) ->
        Logger.warn("Rate limit hit for #{response.request_url}, using cached response body")
        {:ok, headers, old_body}
      # Return cached response body if not modified
      {304, _} when not is_nil(old_body) ->
        Logger.debug("Using cached response body for #{response.request_url}")
        {:ok, headers, old_body}
      # Normal successful response
      {status_code, :ok} when status_code >= 200 and status_code < 400 ->
        {:ok, headers, new_body}
      # Unsuccessful response, body decoded
      {_status_code, :ok} ->
        {:error, headers, new_body}
      # Couldn't parse otherwise-successful response
      {status_code, :error} when status_code >= 200 and status_code < 400 ->
        msg = "Couldn't parse response body"
        Logger.debug(msg <> " for #{response.request_url}")
        {:error, headers, {:raw, msg}}
      # Any other scenario, return raw response body if not decoded
      _ ->
        {:error, headers, {:raw, response.body}}
    end
  end


  ## Testing (mocks)

  # Fake testing responses, full request
  defp mock_response(%{ url: url, headers: header_list } = request) do
    etag = with {_, etag} <- List.keyfind(header_list, "If-None-Match", 0), do: etag
    # TEMP: fake delay with sleep
    Process.sleep(1000)
    # TEMP: fake values for testing
    {status_code, headers, body} =
      case {url, etag} do
        {"_/exit", _} ->
          raise "Fake failure"
        {"_/error", _} ->
          {502, [], "{\"error\": \"Fake error message\"}"}
        {"_/notfound", _} ->
          {404, [], "Fake not found"}
        {"_/cached", "0123456789"} ->
          Logger.debug("Pretending to respond with cached data")
          {304, [{"ETag", "0123456789"}], ""}
        {"_/cached", _} ->
          {200, [{"ETag", "0123456789"}], "{\"data\": \"Cached data\"}"}
        {"_/limit", "9876543210"} ->
          Logger.debug("Pretending to respond with rate-limit error")
          {429, [], ""}
        {"_/limit", _} ->
          {200, [{"ETag", "9876543210"}], "{\"data\": \"Rate-limited data\"}"}
        {"_/" <> path, _} ->
          {200, [], "{\"path\": \"/#{path}\", \"data\": \"Fresh data\"}"}
        _ ->
          {404, [], "Really not found"}
      end
    # TEMP: return fake HTTPoison response
    # TODO: return faked response struct
    %{ body: body, headers: headers, request: request, request_url: url, status_code: status_code }
  end

end
