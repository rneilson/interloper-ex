defmodule InterloperWeb.CachingClient do
  @moduledoc """
  Interface to an external API, with persistent caching
  to reduce external calls and avoid rate limits.

  Each request path gets its own persistent process to
  cache the response (default 60s), send authorization
  and if-none-matches headers as appropriate in API
  calls, and otherwise deduplicate requests.

  The :base_url option is required; the :base_name,
  :cache_timeout, :expire_timeout, :use_registry,
  and :cache_supervisor options are not.
  """

  use GenServer, restart: :temporary
  require Logger

  @base_url ""
  @base_name __MODULE__
  @pretty_name "#{__MODULE__}"
  @cache_timeout 2 * 60 * 1000
  @expire_timeout 60 * 60 * 1000
  @use_registry InterloperWeb.Registry
  @task_supervisor InterloperWeb.TaskSupervisor
  @cache_supervisor InterloperWeb.DynamicSupervisor

  @doc false
  defmacro __using__(opts \\ []) do
    config_attrs = [
      :base_url,
      :base_name,
      :pretty_name,
      :cache_timeout,
      :expire_timeout,
      :use_registry,
      :cache_supervisor,
    ]
    config_overrides =
      opts
      |> Enum.into(%{})
      |> Map.take(config_attrs)

    quote do
      import unquote(__MODULE__)

      @config_overrides unquote(config_overrides)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    config_overrides = Module.get_attribute(env.module, :config_overrides) || %{}
    for {attr, val} <- config_overrides do
      Module.put_attribute(env.module, attr, val)
    end
  end

  ## Client

  # TODO: guard for path?
  def start_link(path) do
    GenServer.start_link(__MODULE__, path, name: get_via_tuple(path))
  end

  @doc """
  Returns default client username if configured, or
  raises otherwise.
  """
  def get_default_user() do
    Application.fetch_env!(:interloper_web, __MODULE__)
    |> Keyword.fetch!(:username)
  end

  @doc """
  Finds PID of existing cache process for `path`, if
  one exists.
  """
  @spec find_pid(path :: binary) :: pid | nil
  def find_pid(path) when is_binary(path) do
    # Try looking up existing process for this path
    case Registry.lookup(@use_registry, get_name(path)) do
      [{pid, _} | _] -> pid
      [] -> nil
    end
  end

  @doc """
  Retrives (possibly-cached) response from API at
  given `url`, creating new process and updating
  cached response as required.

  Returns {:ok, response} or {:error, reason}.
  """
  @spec fetch(url :: binary) :: {:ok, term} | {:error, term}
  def fetch(url) do
    # Ensure server started or get existing
    case get_or_create_server(url) do
      {:ok, pid} -> GenServer.call(pid, :fetch)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Makes HTTP request to specified API path.
  Primarily for use by async task spawned by caching
  process.

  Options:
  * `:auth` - value of `Authorization` header
  * `:etag` - value of `If-None-Match` header

  Returns raw HTTPoison response struct.
  """
  @spec fetch_raw(path :: binary, opts :: keyword) :: any
  def fetch_raw(path, opts \\ []) do
    # Actual request URL
    url = @base_url <> path
    # Headers
    # TODO: if-modified-since?
    headers =
      [{"Accept", "application/json"}]
      |> add_header("Authorization", Keyword.get(opts, :auth))
      |> add_header("If-None-Match", Keyword.get(opts, :etag))
    # Options
    # TODO: SSL options, possibly?
    options = [follow_redirect: true]
    # TEMP: remove this later?
    Logger.debug("Request url: #{url}")
    Logger.debug("Request headers: #{inspect(headers)}")
    # Make request
    # TODO: better way to indicate test/mock path?
    if binary_part(path, 0, 2) == "/_" do
      # Get fake response
      mock_response(%{ method: :get, url: url, headers: headers, options: options })
    else
      HTTPoison.request!(:get, url, "", headers, options)
    end
  end


  ## Server (callbacks)

  def init(path) do
    # Initial state
    state =
      path
      |> create_new_state
      |> reset_expiry_timer(@expire_timeout)
    Logger.debug("Started new cache process for #{path}")
    # TODO: continue?
    {:ok, state}
  end

  # TODO: handle_continue to send first timeout message?

  # Cache valid, return existing
  def handle_call(:fetch, _from, %{path: path, body: body, cache_valid: true} = state) do
    Logger.debug("Returning cached data for #{path}")
    {:reply, {:ok, body}, state}
  end

  # Cache not valid and no task dispatched, refetch
  def handle_call(:fetch, from, %{ref: nil, cache_valid: false} = state) do
    # Get auth, body, path, callers list (should be empty), and cache tag from state
    # (Separate just to keep it clean)
    %{auth: auth, body: old_body, path: path, callers: callers, cache_tag: cache_tag} = state
    # Only set etag header if body present
    etag = if is_nil(old_body), do: nil, else: cache_tag
    # Dispatch new task
    task = Task.Supervisor.async_nolink(
      @task_supervisor, __MODULE__, :fetch_raw, [path, [auth: auth, etag: etag]])
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
    %{body: old_body, callers: callers, expire_ref: expire_ref} = state
    # Demonitor task
    Process.demonitor(ref, [:flush])
    # TEMP: remove this later?
    Logger.debug("Response url: #{response.request_url}")
    Logger.debug("Response code: #{inspect(response.status_code)}")
    Logger.debug("Response headers: #{inspect(response.headers)}")
    # Parse response
    {success, headers, body} = parse_response(response, old_body)
    # Reply to previous callers
    reply_to_callers({success, body}, callers)
    # Update state
    new_state =
      case success do
        :ok ->
          # Send cache timeout message
          Process.send_after(self(), :invalidate_cache, @cache_timeout)
          # Update cached values and extend expiry
          new_tag = Map.get(headers, "etag")
          new_ref = reset_expiry_timer(expire_ref, @expire_timeout)
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
    %{path: path, callers: callers} = state
    # Reply to previous callers (obscure real error, though)
    reply_to_callers({:error, "Request failed for #{path}"}, callers)
    # Shut down, request failed
    {:stop, :request_failed, state}
  end

  # Cache timed out, update state
  def handle_info(:invalidate_cache, %{path: path, ref: nil, cache_valid: true} = state) do
    Logger.debug("Invalidating cache for #{path}")
    {:noreply, %{state | cache_valid: false}}
  end

  # Request in progress or cache already invalid, keep state
  def handle_info(:invalidate_cache, state) do
    {:noreply, state}
  end

  # Request in progress, don't terminate
  def handle_info(:timeout, %{path: path, ref: ref} = state) when is_reference(ref) do
    Logger.debug("Extending expiry timeout for #{path}")
    # TODO: pick a better extension time limit?
    {:noreply, reset_expiry_timer(state, @cache_timeout)}
  end

  # Cache process expired, terminate
  def handle_info(:timeout, %{path: path} = state) do
    Logger.debug("Shutting down cache for #{path}")
    {:stop, :normal, state}
  end


  ## Internal (utilities)

  # Fresh state
  # TODO: move to its own struct type?
  defp create_new_state(path, items \\ []) do
    # Get username/password, construct header
    auth =
      with config when is_list(config) <- Application.get_env(:interloper_web, __MODULE__),
           user when is_binary(user) <- Keyword.get(config, :username),
           pass when is_binary(pass) <- Keyword.get(config, :password)
      do
        "Basic " <> Base.encode64(user <> ":" <> pass)
      else
        _ -> nil
      end
    # New state map
    state = %{
      auth: auth,
      path: path,
      body: nil,
      ref: nil,
      callers: [],
      cache_tag: nil,
      cache_valid: false,
      expire_ref: nil,
    }
    # Merge additional items, if any
    Enum.into(items, state)
  end

  # Get name tuple for use with registries.
  @spec get_name(binary) :: {atom, binary}
  defp get_name(path) when is_binary(path) do
    {@base_name, path}
  end

  # Get the path portion of a given Github API URL.
  # Returns {:ok, path} or {:error, reason}.
  @spec get_path(binary) :: {:ok, binary} | {:error, term}
  defp get_path(url)

  defp get_path(path) when binary_part(path, 0, 1) == "/" do
    # TODO: less-simplistic check?
    {:ok, path}
  end

  defp get_path(@base_url <> path) when byte_size(path) > 0 do
    # TODO: less-simplistic extraction?
    {:ok, path}
  end

  defp get_path(url) do
    # Catch-other clause
    {:error, "Invalid #{@pretty_name} URL: #{url}"}
  end

  # Get via tuple for use with registries
  @spec get_via_tuple(binary) :: {:via, atom, term}
  defp get_via_tuple(path) when is_binary(path) do
    {:via, Registry, {@use_registry, get_name(path)}}
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
  @spec get_or_create_server(url :: binary) :: {:ok, pid} | {:error, any}
  defp get_or_create_server(url) do
    case get_path(url) do
      {:ok, path} ->
        # Try looking up existing process for this path
        case find_pid(path) do
          nil ->
            # Spawn a new process for this path
            Logger.debug("Spawning new cache process for #{path}")
            DynamicSupervisor.start_child(@cache_supervisor, {__MODULE__, path})
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
  # Current options include:
  # - {:raw, bool()}
  @spec parse_response(response :: term, old_body :: term) :: {atom, map, term}
  defp parse_response(response, old_body, opts \\ []) do
    # Get headers, attempt decoding response body
    # Lowercase header names for easier future use
    headers =
      response.headers
      |> Enum.map(fn {name, value} -> {String.downcase(name), value} end)
      |> Enum.into(%{})
    {decode_success, new_body} =
      case Keyword.get(opts, :raw) do
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
    {:ok, path} = get_path(url)
    etag = with {_, etag} <- List.keyfind(header_list, "If-None-Match", 0), do: etag
    # TEMP: fake delay with sleep
    Process.sleep(1000)
    # TEMP: fake values for testing
    {status_code, headers, body} =
      case {path, etag} do
        {"/_exit", _} ->
          raise "Fake failure"
        {"/_error", _} ->
          {502, [], "{\"error\": \"Fake error message\"}"}
        {"/_notfound", _} ->
          {404, [], "Fake not found"}
        {"/_cached", "0123456789"} ->
          Logger.debug("Pretending to respond with cached data")
          {304, [{"ETag", "0123456789"}], ""}
        {"/_cached", _} ->
          {200, [{"ETag", "0123456789"}], "{\"data\": \"Cached data\"}"}
        {"/_limit", "9876543210"} ->
          Logger.debug("Pretending to respond with rate-limit error")
          {429, [], ""}
        {"/_limit", _} ->
          {200, [{"ETag", "9876543210"}], "{\"data\": \"Rate-limited data\"}"}
        _ ->
          {200, [], "{\"path\": \"#{path}\", \"data\": \"Fresh data\"}"}
      end
    # TEMP: return fake HTTPoison response
    # TODO: return faked response struct
    %{ body: body, headers: headers, request: request, request_url: url, status_code: status_code }
  end

end
