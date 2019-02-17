defmodule InterloperWeb.Router do
  use InterloperWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]

    # TODO: reenable if/when we find some use for sessions
    # plug :fetch_session
    # plug :fetch_flash

    # TODO: reenable if/when any forms are set up
    # plug :protect_from_forgery

    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", InterloperWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/games", PageController, :games
    get "/github", GithubController, :repo_list
    get "/twitter", TwitterController, :recent
    get "/rampant", PageController, :rampant
  end

  scope "/api", InterloperWeb, as: :api do
    pipe_through :api

    get "/twitter/recent", TwitterController, :recent
  end
end
