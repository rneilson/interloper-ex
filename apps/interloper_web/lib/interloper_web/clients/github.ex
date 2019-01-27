defmodule InterloperWeb.GithubClient do
  @moduledoc """
  Interface to the Github API, with persistent caching
  to reduce external calls and avoid rate limits.

  Each request path gets its own persistent process to
  cache the response (default 60s), send authorization
  and if-none-matches headers as appropriate in API
  calls, and otherwise deduplicate requests.
  """

  use GenServer, restart: :temporary
  require Logger

  @base_url "https://api.github.com"

  @cache_timeout 60 * 1000  # 60s by default

  ## Client

  # TODO: guard for path?
  def start_link(path) do
    GenServer.start_link(__MODULE__, path, name: get_via_tuple(path))
  end

  @doc """
  Finds PID of existing cache process for `path`, if
  one exists.
  """
  @spec find_pid(path :: binary) :: pid | nil
  def find_pid(path) when is_binary(path) do
    # Try looking up existing process for this path
    case Registry.lookup(InterloperWeb.Registry, get_name(path)) do
      [{pid, _} | _] -> pid
      [] -> nil
    end
  end

  @doc """
  Retrives (possibly-cached) response from Github API
  at given `url`, creating new process and updating
  cached response as required.

  Returns {:ok, response} or {:error, reason}.
  """
  @spec fetch(url :: binary) :: {:ok, term} | {:error, term}
  def fetch(url)

  def fetch(path) when binary_part(path, 0, 1) == "/" do
    # Ensure server started or get existing
    case get_or_create_server(path) do
      {:ok, pid} -> GenServer.call(pid, :fetch)
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch(url) do
    case get_path(url) do
      {:ok, path} -> fetch(path)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Makes HTTP request to specified Github API path.
  Primarily for use by async task spawned by caching
  process. Will pass `If-None-Match` header with
  `etag` value if given.

  Returns raw HTTPoison response struct.
  """
  @spec fetch_raw(path :: binary, auth :: binary | nil, etag :: binary | nil) :: any
  def fetch_raw(path, auth \\ nil, etag \\ nil) do
    # Actual request URL
    url = get_base_url() <> path
    # Headers
    # TODO: if-modified-since?
    headers =
      [{"Accept", "application/json"}]
      |> add_header("Authorization", auth)
      |> add_header("If-None-Match", etag)
    # Options
    # TODO: SSL options, possibly?
    options = [follow_redirect: true]
    # Make request
    # TODO: actually use HTTPoison...
    request = %{ method: :get, url: url, headers: headers, options: options }
    Logger.debug("Request headers: #{inspect(headers)}")
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
          {304, [{"etag", "0123456789"}], ""}
        {"/_cached", _} ->
          {200, [{"etag", "0123456789"}], "{\"data\": \"Cached data\"}"}
        _ ->
          {200, [], "{\"data\": \"Fresh data\"}"}
      end
    # TEMP: return faked response struct
    %{ body: body, headers: headers, request: request, request_url: url, status_code: status_code }
  end


  ## Server (callbacks)

  def init(path) do
    # Initial state
    state = create_new_state(path)
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
      InterloperWeb.TaskSupervisor, __MODULE__, :fetch_raw, [path, auth, etag])
    # Add caller to list, keep task ref, wait for response
    {:noreply, %{state | ref: task.ref, callers: [from | callers]}}
  end

  # Cache not valid and task already dispatched, add caller
  def handle_call(:fetch, from, %{ref: _ref, callers: callers, cache_valid: false} = state) do
    # Save new caller for when task returns
    {:noreply, %{state | callers: [from | callers]}}
  end

  # Task complete, reply to callers and update cache
  def handle_info({ref, response}, %{path: path, body: old_body, ref: ref, callers: callers}) do
    # Demonitor task
    Process.demonitor(ref, [:flush])
    # TEMP: remove this later?
    Logger.debug("Response url: #{inspect(response.request_url)}")
    Logger.debug("Response code: #{inspect(response.status_code)}")
    Logger.debug("Response headers: #{inspect(response.headers)}")
    # Get headers
    headers = Enum.into(response.headers, %{})
    # Attempt decoding response body
    {decode_success, decoded} = Jason.decode(response.body, strings: :copy)
    # Check status code, plus decode success, for success/error
    # Return raw response body if not decoded
    # Return cached response body if not modified
    {status, body} =
      case {response.status_code, decode_success} do
        {304, _} when not is_nil(old_body) ->
          Logger.debug("Using cached response body for #{path}")
          {:ok, old_body}
        {status_code, :ok} when status_code >= 200 and status_code < 400 ->
          {:ok, decoded}
        {_status_code, :ok} ->
          {:error, decoded}
        _ ->
          {:error, response.body}
      end
    # Reply to previous callers
    reply_to_callers({status, body}, callers)
    # Only cache if request successful
    # TODO: set overall success including status code
    # TODO: any parsing of the ETag header value?
    {success, new_body, new_cache_tag} =
      case status do
        :ok -> {true, body, Map.get(headers, "etag")}
        _ -> {false, nil, nil}
      end
    # Send cache timeout message
    if success do
      Process.send_after(self(), :invalidate_cache, @cache_timeout)
    end
    # Update state
    new_state = create_new_state(path)
    {:noreply, %{new_state | body: new_body, cache_tag: new_cache_tag, cache_valid: success}}
  end

  # Task failed, reply to callers and clear cache
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{path: path, ref: ref, callers: callers}) do
    # Reply to previous callers (obscure real error, though)
    reply_to_callers({:error, "Request failed for #{path}"}, callers)
    # Reset state
    {:noreply, create_new_state(path)}
  end

  # Cache timed out, update state
  def handle_info(:invalidate_cache, %{path: path, ref: ref} = state) do
    case ref do
      nil ->
        Logger.debug("Invalidating cache for #{path}")
        {:noreply, %{state | cache_valid: false}}
      _ ->
        {:noreply, state}
    end
  end


  ## Internal (utilities)

  # Fresh state
  # TODO: move to its own struct type?
  defp create_new_state(path) do
    # Get username/password, construct header
    auth =
      with config when is_list(config) <- Application.get_env(:interloper_web, __MODULE__),
           user when is_binary(user) <- Keyword.get(config, :username),
           pass when is_binary(pass) <- Keyword.get(config, :password)
      do
        "Basic " <> Base.encode64(user <> ":" <> pass)
      else
        _ ->
          nil
      end
    %{
      auth: auth,
      path: path,
      body: nil,
      ref: nil,
      callers: [],
      cache_tag: nil,
      cache_valid: false,
    }
  end

  # Get currently-configured base URL
  @spec get_base_url() :: binary
  defp get_base_url() do
    # TODO: get from env for overriding during testing
    @base_url
  end

  # Get name tuple for use with registries.
  @spec get_name(binary) :: {atom, binary}
  defp get_name(path) when is_binary(path) do
    {__MODULE__, path}
  end

  # Get via tuple for use with registries
  @spec get_via_tuple(binary) :: {:via, atom, term}
  defp get_via_tuple(path) when is_binary(path) do
    {:via, Registry, {InterloperWeb.Registry, get_name(path)}}
  end

  # Get the path portion of a given Github API URL.
  # Returns {:ok, path} or {:error, reason}.
  @spec get_path(binary) :: {:ok, binary} | {:error, term}
  defp get_path(url)

  # TODO: less-simplistic check?
  defp get_path(path) when binary_part(path, 0, 1) == "/" do
    {:ok, path}
  end

  # TODO: less-simplistic extraction?
  defp get_path(@base_url <> path) when byte_size(path) > 0 do
    {:ok, path}
  end

  defp get_path(url) do
    {:error, "Invalid Github API URL: #{url}"}
  end

  # Finds the registered server for `path`, if
  # it exists, or creates one if not.
  # Returns {:ok, pid} or {:error, reason}.
  @spec get_or_create_server(path :: binary) :: {:ok, pid} | {:error, any}
  defp get_or_create_server(path) do
    # Try looking up existing process for this path
    case find_pid(path) do
      nil ->
        # Spawn a new process for this path
        Logger.debug("Spawning new cache process for #{path}")
        DynamicSupervisor.start_child(InterloperWeb.DynamicSupervisor, {__MODULE__, path})
      pid ->
        # Return first found -- shouldn't be an issue with unique keys
        {:ok, pid}
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

end
