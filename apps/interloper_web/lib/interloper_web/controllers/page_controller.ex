defmodule InterloperWeb.PageController do
  use InterloperWeb, :controller

  alias InterloperWeb.GithubClient

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def games(conn, _params) do
    render(conn, "games.html")
  end

  def github(conn, %{username: username}) do
    case GithubClient.fetch("/users/#{username}/repos?sort=created") do
      {:ok, repos} ->
        render(conn, "github.html", repos: repos)
      {:error, reason} ->
        render(conn, "load_error.html", loading: "Github repo list", reason: reason)
    end
  end

  def github(conn, _params) do
    github(conn, %{username: GithubClient.get_default_user()})
  end
end
