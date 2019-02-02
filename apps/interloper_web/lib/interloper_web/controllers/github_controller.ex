defmodule InterloperWeb.GithubController do
  use InterloperWeb, :controller

  alias InterloperWeb.GithubClient

  def index(conn, %{username: username}) do
    # First fetch repo list
    case GithubClient.fetch("/users/#{username}/repos?sort=created") do
      {:ok, repo_list} ->
        repos = get_repo_details(repo_list)
        render(conn, "repo_list.html", repos: repos)
      {:error, reason_raw} ->
        reason =
          case Jason.encode(reason_raw) do
            {:ok, reason_str} -> reason_str
            {:error, _reason} -> "unknown"
          end
        conn
        |> put_view(InterloperWeb.PageView)
        |> render("load_error.html", loading: "Github repo list for #{username}", reason: reason)
    end
  end

  def index(conn, _params) do
    index(conn, %{username: GithubClient.get_default_user()})
  end


  ## Private/internal

  defp get_repo_details(repo_list) do
    num_repos = Enum.count(repo_list)
    # Get latest commit for each, in parallel, then extract
    # task result and merge with repo info
    Task.Supervisor.async_stream_nolink(
      InterloperWeb.TaskSupervisor, repo_list,
      &get_commit_map/1, on_timeout: :kill_task, max_concurrency: num_repos)
    |> Stream.zip(repo_list)
    |> Enum.map(&get_repo_map/1)
  end

  defp get_commit_map(repo) do
    with {:ok, commits_url} <- Map.fetch(repo, "commits_url"),
         branch_url <- UriTemplate.expand(commits_url, sha: Map.get(repo, "default_branch")),
         {:ok, commit} <- GithubClient.fetch(branch_url)
    do
      %{commit: commit}
    else
      {:error, reason} -> %{commit_err: reason}
      _ -> %{}
    end
  end

  defp get_repo_map({{:ok, commit_map}, repo}) when is_map(commit_map) do
    Map.merge(%{repo: repo}, commit_map)
  end

  defp get_repo_map({_, repo}) do
    # Log error if {:exit, _reason}?
    %{repo: repo}
  end

end
