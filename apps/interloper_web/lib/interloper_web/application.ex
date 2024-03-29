defmodule InterloperWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start a registry
      {Registry, keys: :unique, name: InterloperWeb.Registry},
      # Dynamic supervisor for fetcher processes (etc)
      {DynamicSupervisor, strategy: :one_for_one, name: InterloperWeb.DynamicSupervisor},
      # Task supervisor for fetch tasks (etc)
      {Task.Supervisor, name: InterloperWeb.TaskSupervisor},
      # Phoenix Pubsub
      {Phoenix.PubSub, name: InterloperWeb.PubSub},
      # Start the endpoint when the application starts
      InterloperWeb.Endpoint,
      # Starts a worker by calling: InterloperWeb.Worker.start_link(arg)
      # {InterloperWeb.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: InterloperWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    InterloperWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
