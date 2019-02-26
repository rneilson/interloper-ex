defmodule InterloperWeb.GithubController do
  use InterloperWeb, :controller

  alias InterloperWeb.SharedController
  alias InterloperWeb.GithubClient

  def repo_list(conn, %{username: username}) do
    # First fetch repo list
    case GithubClient.fetch("/users/#{username}/repos?sort=created") do
      {:ok, repos} ->
        repo_list = get_repo_details(repos)
        render(conn, "repo_list.html", repo_list: repo_list)
      {:error, reason} ->
        loading = "Github repo list for #{username}"
        msg = if InterloperWeb.Endpoint.config(:debug_errors), do: reason, else: "Service unavailable"
        conn
        |> put_status(503)
        |> SharedController.loading_error(%{reason: msg, loading: loading})
    end
  end

  # # If we ever decide to allow viewing other users...
  # def index(conn, %{"username" => username}) do
  #   index(conn, %{username: username})
  # end

  def repo_list(conn, _params) do
    repo_list(conn, %{username: GithubClient.get_default_user()})
  end


  ## Public, technically, but really private

  def get_repo_details(repo_list) do
    repos =
      cond do
        fetch_repo_commits?() ->
          num_repos = Enum.count(repo_list)
          # Get latest commit for each, in parallel, then extract
          # task result and merge with repo info
          Task.Supervisor.async_stream_nolink(
            InterloperWeb.TaskSupervisor, repo_list, __MODULE__,
            :get_commit_map, [], on_timeout: :kill_task, max_concurrency: num_repos)
        true ->
          # Just extract commit URL and let frontend deal with it
          Stream.map(repo_list, &get_commit_url/1)
      end
    repos
    |> Stream.zip(repo_list)
    |> Stream.map(&get_repo_map/1)
    |> Enum.to_list()
  end

  def get_commit_map(repo) do
    with {:ok, branch_url} <- get_commit_url(repo),
         {:ok, commit} <- GithubClient.fetch(branch_url)
    do
      %{commit: commit}
    else
      {:error, reason} -> %{commit_err: reason}
      _ -> %{}
    end
  end


  ## Private/internal

  defp fetch_repo_commits?() do
    Application.get_env(:interloper_web, __MODULE__, [])
    |> Keyword.get(:fetch_repo_commits, false)
  end

  defp get_commit_url(repo) do
    with {:ok, commits_url} <- Map.fetch(repo, "commits_url"),
         branch_url <- UriTemplate.expand(commits_url, sha: Map.get(repo, "default_branch"))
    do
      {:ok, branch_url}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, "Couldn't determine commit URL"}
      _ -> nil
    end
  end

  defp get_repo_map({{:ok, commit_map}, repo}) when is_map(commit_map) do
    Map.merge(%{repo: repo}, commit_map)
  end

  defp get_repo_map({{:ok, commit_url}, repo}) when is_binary(commit_url) do
    %{repo: repo, commit_url: commit_url}
  end

  defp get_repo_map({_, repo}) do
    # Log error if {:exit, _reason}?
    %{repo: repo}
  end

end
