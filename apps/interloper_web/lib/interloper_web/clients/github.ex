defmodule InterloperWeb.Github do
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

  # TODO: start_link/3

  # TODO: fetch/1

  ## Server (callbacks)

  def init(path) do
    # Initial state
    # TODO: make this into a struct
    state = %{ path: path, body: nil, callers: [], cache_tag: nil, cache_valid: false }
    {:ok, state}
  end

  ## Internal (utils)

  # TODO: get_or_create_server/1

end
