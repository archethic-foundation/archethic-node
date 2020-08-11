defmodule Uniris.MixProject do
  use Mix.Project

  def project do
    [
      app: :uniris,
      version: "0.7.1",
      build_path: "_build",
      config_path: "config/config.exs",
      deps_path: "deps",
      lockfile: "mix.lock",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make, :phoenix] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :os_mon, :runtime_tools],
      mod: {Uniris.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:flow, "~> 1.0"},
      {:xandra, "~> 0.11"},
      {:phoenix, "~> 1.5"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_live_view, "~> 0.14.0"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.3"},
      {:absinthe, "~> 1.5.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:cors_plug, "~> 1.5"},
      {:phoenix_live_dashboard, "~> 0.2.7"},
      {:ex_doc, "~> 0.21.2", only: :dev},
      {:observer_cli, "~> 1.5"},
      {:distillery, "~> 2.0"},
      {:crontab, "~> 1.1"},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:git_hooks, "~> 0.4.0", only: [:test, :dev], runtime: false},
      {:mox, "~> 0.5.2", only: [:test]},
      {:stream_data, "~> 0.4.3", only: [:test]},
      {:elixir_make, "~> 0.6.0", only: [:dev, :test], runtime: false},
      {:logger_file_backend, "~> 0.0.11", only: [:dev]}
    ]
  end
end
