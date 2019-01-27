defmodule InterloperWeb.GithubClient do
  @moduledoc """
  Interface to the Github API, with persistent caching
  to reduce external calls and avoid rate limits.

  Each request path gets its own persistent process to
  cache the response (default 60s), send authorization
  and if-none-matches headers as appropriate in API
  calls, and otherwise deduplicate requests.
  """

  use GenServer

  @base_url "https://api.github.com"

  ## Client

  # TODO: guard for path?
  def start_link(path) do
    GenServer.start_link(__MODULE__, path, name: get_via_tuple(path))
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
  @spec fetch_raw(path :: binary, etag :: binary | nil) :: any
  def fetch_raw(path, etag \\ nil) do
    # Actual request URL
    url = get_base_url() <> path

    # Headers
    headers = [{"Accept", "application/json"}]
    # Add if-none-match if etag given
    headers = add_etag_header(headers, etag)
    # TODO: authorization
    # TODO: if-modified-since?

    # Options, if any even make sense?
    # TODO: SSL options, possibly?
    options = []

    # TODO: actually use HTTPoison...
    request = %{ method: :get, url: url, headers: headers, options: options }
    # TEMP: Fake delay with sleep
    Process.sleep(1000)
    # Return faked response struct
    %{ body: "{}", headers: [], request: request, request_url: url, status_code: 200 }
  end


  ## Server (callbacks)

  def init(path) do
    # Initial state
    # TODO: make this into a struct?
    state = %{ path: path, body: nil, ref: nil, callers: [], cache_tag: nil, cache_valid: false }
    # TODO: continue?
    {:ok, state}
  end

  # TODO: handle_continue to send first timeout message?

  # Cache valid, return existing
  def handle_call(:fetch, %{body: body, cache_valid: true} = state) do
    {:reply, {:ok, body}, state}
  end

  # Cache not valid and no task dispatched, refetch
  # TODO: handle_call/3

  # Cache not valid and task already dispatched, add caller
  # TODO: handle_call/3

  # Task complete, reply to callers and update cache
  # TODO: handle_info/2

  # Task failed, reply to callers and keep cache
  # TODO: handle_info/2


  ## Internal (utilities)

  # Get currently-configured base URL
  @spec get_base_url() :: binary
  defp get_base_url() do
    # TODO: get from env for overriding during testing
    @base_url
  end

  # Get name tuple for use with registries.
  @spec get_name(binary) :: {atom, binary}
  defp get_name(path) when is_binary(path) do
    {:github, path}
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
    case Registry.lookup(InterloperWeb.Registry, get_name(path)) do
      [] ->
        # Spawn a new process for this path
        DynamicSupervisor.start_child(InterloperWeb.DynamicSupervisor, {__MODULE__, path})
      [{pid, _} | _] ->
        # Return first found -- shouldn't be an issue with unique keys
        {:ok, pid}
    end
  end

  # Conditionally adds `If-None-Match` header if
  # `etag` value given
  defp add_etag_header(headers, nil) do
    headers
  end
  defp add_etag_header(headers, etag) when byte_size(etag) > 0 do
    headers ++ [{"If-None-Match", etag}]
  end

end
