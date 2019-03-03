defmodule Interloper.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # Connect to any configured peer nodes
    connect_to_cluster()

    # List all child processes to be supervised
    children = [
      # Interloper.Worker
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Interloper.Supervisor)
  end

  def get_configured_nodes() do
    case System.get_env("CONNECT_NODES") do
      nodes when is_binary(nodes) ->
        nodes
        |> String.split()
        |> Enum.map(fn n -> String.to_atom(n) end)
      _ ->
        []
    end
  end

  def connect_to_cluster() do
    this_node = Node.self()

    get_configured_nodes()
    |> Enum.reject(fn n -> n == this_node end)
    |> Enum.map(fn n -> {n, Node.connect(n)} end)
  end
end
