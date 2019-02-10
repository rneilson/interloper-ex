defmodule InterloperWeb.TwitterController do
  use InterloperWeb, :controller

  alias InterloperWeb.SharedController
  alias InterloperWeb.CachingClient

  def recent(conn, _params) do
    # Get URL from env
    env = Application.fetch_env!(:interloper_web, __MODULE__)
    base_url = Keyword.fetch!(env, :base_url) |> Enum.random()
    url = base_url <> "/" <> Keyword.fetch!(env, :recent_path)
    case CachingClient.fetch(url) do
      {:ok, recent} ->
        render(conn, :recent, recent: recent)
      {:error, reason} ->
        SharedController.loading_error(conn, %{reason: reason, loading: "recent tweets"})
    end
  end
end