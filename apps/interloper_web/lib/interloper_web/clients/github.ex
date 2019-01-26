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


  ## Server (callbacks)

  def init(path) do
    # Initial state
    # TODO: make this into a struct
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

  # Get name tuple for use with registries.
  @spec get_name(binary) :: {atom, binary}
  defp get_name(path) when is_binary(path) do
    {:github, path}
  end

  # Get via tuple for use with registries
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

end
