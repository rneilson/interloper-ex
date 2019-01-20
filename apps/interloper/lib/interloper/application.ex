defmodule Interloper.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Interloper.Worker
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Interloper.Supervisor)
  end
end
