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
    # First fetch repo list
    case GithubClient.fetch("/users/#{username}/repos?sort=created") do
      {:ok, repo_list} ->
        # # Get latest commit for each, in series
        # stream = Stream.map(repo_list, &_get_commit/1)
        # Get latest commit for each, in parallel
        stream = Task.Supervisor.async_stream_nolink(
          InterloperWeb.TaskSupervisor, repo_list,
          &_get_commit/1, on_timeout: :kill_task)
        repos = Enum.map(stream, fn {:ok, val} -> val end)
        render(conn, "github.html", repos: repos)
      {:error, reason} ->
        # Let's call this not found
        conn
        |> put_status(404)
        |> render("load_error.html", loading: "Github repo list for #{username}", reason: reason)
    end
  end

  def github(conn, _params) do
    github(conn, %{username: GithubClient.get_default_user()})
  end

  ## Private/internal

  def _get_commit(repo) do
    with {:ok, commits_url} <- Map.fetch(repo, "commits_url"),
         branch_url <- UriTemplate.expand(commits_url, sha: Map.get(repo, "default_branch")),
         {:ok, commit_info} <- GithubClient.fetch(branch_url)
    do
      %{repo: repo, commit: commit_info}
    else
      {:error, reason} -> %{repo: repo, commit_err: reason}
      _ -> %{repo: repo}
    end
  end
end
