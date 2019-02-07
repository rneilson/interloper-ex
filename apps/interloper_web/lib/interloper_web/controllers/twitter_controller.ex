defmodule InterloperWeb.TwitterController do
  use InterloperWeb, :controller

  alias InterloperWeb.SharedController
  alias InterloperWeb.CachingClient

  def recent(conn, _params) do
    # TODO: get URL from env
    url = "https://www.interloper.ca/twitter/recent.json"
    case CachingClient.fetch(url) do
      {:ok, recent} ->
        render(conn, :recent, recent: recent)
      {:error, reason} ->
        SharedController.loading_error(conn, %{reason: reason, loading: "recent tweets"})
    end
  end
end