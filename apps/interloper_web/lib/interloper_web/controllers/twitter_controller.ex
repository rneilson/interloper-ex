defmodule InterloperWeb.TwitterController do
  use InterloperWeb, :controller

  alias InterloperWeb.SharedController
  alias InterloperWeb.CachingClient

  def recent(conn, %{username: username}) do
    # Get URL from env
    env = Application.fetch_env!(:interloper_web, __MODULE__)
    base_url = Keyword.fetch!(env, :base_url) |> Enum.random()
    path = Keyword.fetch!(env, :recent_path)
    # TODO: some provision for other usernames...
    url =
      cond do
        binary_part(path, 0, 1) == "/" -> base_url <> path
        path == "" -> base_url <> "/"
        true -> base_url <> "/" <> path
      end
    case CachingClient.fetch(url) do
      {:ok, recent} ->
        meta = %{ :description => "Recent tweets by @#{username}" }
        render(conn, :recent, recent: recent, meta: meta)
      {:error, reason} ->
        msg = if InterloperWeb.Endpoint.config(:debug_errors), do: reason, else: "Service unavailable"
        conn
        |> put_status(503)
        |> SharedController.loading_error(%{reason: msg, loading: "recent tweets"})
    end
  end

  # TODO: allow others from params?
  def recent(conn, _params) do
    username =
      Application.fetch_env!(:interloper_web, __MODULE__)
      |> Keyword.fetch!(:username)
    recent(conn, %{username: username})
  end
end