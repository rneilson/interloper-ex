defmodule InterloperWeb.GithubController do
  use InterloperWeb, :controller
  require Logger

  alias InterloperWeb.SharedController
  alias InterloperWeb.GithubClient

  def index(conn, %{username: username}) do
    loading = "Github repo list for #{username}"
    # First fetch repo list
    case GithubClient.fetch("/users/#{username}/repos?sort=created") do
      {:ok, body} ->
        case Jason.decode(body, strings: :copy) do
          {:ok, repo_list} ->
            # TODO: skip prefetching commit details, leave to client-side
            repos = get_repo_details(repo_list)
            render(conn, "repo_list.html", repos: repos)
          _ ->
            # TODO: log error internally?
            SharedController.render_loading_error(conn, "Couldn't parse repo list", loading: loading)
        end
      {:error, reason} ->
        # TODO: log error internally?
        SharedController.render_loading_error(conn, reason, loading: loading)
    end
  end

  # # If we ever decide to allow viewing other users...
  # def index(conn, %{"username" => username}) do
  #   index(conn, %{username: username})
  # end

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
      &get_commit/1, on_timeout: :kill_task, max_concurrency: num_repos)
    |> Stream.zip(repo_list)
    |> Enum.map(&get_repo_map/1)
  end

  # Dispatched to async task
  defp get_commit(repo) do
    with {:ok, commits_url} <- Map.fetch(repo, "commits_url"),
         branch_url <- UriTemplate.expand(commits_url, sha: Map.get(repo, "default_branch")),
         {:ok, commit} <- GithubClient.fetch(branch_url)
    do
      commit
    else
      # TODO: log error internally?
      {:error, _reason} -> :fetch_error
      _ -> :fetch_error
    end
  end

  # On return from async task (zipped with original repo)
  defp get_repo_map({{:ok, commit}, repo}) when is_binary(commit) do
    get_repo_map({Jason.decode(commit), repo})
  end

  defp get_repo_map({{:ok, commit_map}, repo}) when is_map(commit_map) do
    %{repo: repo, commit: commit_map}
  end

  defp get_repo_map({{:ok, :fetch_error}, repo}) do
    %{repo: repo, commit_err: "Couldn't retrieve commit details"}
  end

  defp get_repo_map({{:error, _reason}, repo}) do
    # TODO: log error internally?
    %{repo: repo, commit_err: "Invalid response"}
  end

  defp get_repo_map({_, repo}) do
    # Log error if {:exit, _reason}?
    %{repo: repo}
  end

end
