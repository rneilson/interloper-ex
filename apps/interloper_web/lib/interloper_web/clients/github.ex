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

  ## Client

  # TODO: guard for path?
  def start_link(path) do
    GenServer.start_link(__MODULE__, path, name: {:via, InterloperWeb.Registry, get_name(path)})
  end

  # TODO: fetch/1

  ## Server (callbacks)

  def init(path) do
    # Initial state
    # TODO: make this into a struct
    state = %{ path: path, body: nil, callers: [], cache_tag: nil, cache_valid: false }
    {:ok, state}
  end

  ## Internal (utils)

  @doc """
  Get name tuple for use with registry.
  """
  def get_name(path) do
    {:github, path}
  end

  # TODO: get_or_create_server/1

end
