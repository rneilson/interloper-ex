defmodule Interloper.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps()
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    [
      # {:distillery, "~> 2.1"},
    ]
  end

  # Elixir releases config
  defp releases() do
    [
      interloper_ex: [
        version: "0.2.8",
        applications: [
          interloper: :permanent,
          interloper_web: :permanent
        ],
        include_executables_for: [:unix]
      ]
    ]
  end
end
