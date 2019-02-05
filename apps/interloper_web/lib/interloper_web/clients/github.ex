defmodule InterloperWeb.GithubClient do
  @moduledoc """
  Interface to the Github API, with persistent caching
  to reduce external calls and avoid rate limits.

  Each request path gets its own persistent process to
  cache the response (default 60s), send authorization
  and if-none-matches headers as appropriate in API
  calls, and otherwise deduplicate requests.
  """

  use InterloperWeb.CachingClient,
    base_url: "https://api.github.com"
    # cache_timeout: 120000

  @doc """
  Returns default Github username if configured, or
  raises otherwise.
  """
  def get_default_user() do
    Application.fetch_env!(:interloper_web, __MODULE__)
    |> Keyword.fetch!(:username)
  end

  @doc """
  Returns HTTP Basic authorization header based on
  configured username/password.
  """
  def get_auth_header(_url) do
    with env <- Application.get_env(:interloper_web, __MODULE__),
         user when is_binary(user) <- env[:username],
         pass when is_binary(pass) <- env[:password]
    do
      "Basic " <> Base.encode64(user <> ":" <> pass)
    else
      _ -> nil
    end
  end

end
