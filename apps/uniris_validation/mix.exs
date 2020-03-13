defmodule UnirisValidation.MixProject do
  use Mix.Project

  def project do
    [
      app: :uniris_validation,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {UnirisValidation.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:uniris_chain, in_umbrella: true},
      {:uniris_election, in_umbrella: true},
      {:uniris_p2p, in_umbrella: true},
      {:uniris_shared_secrets, in_umbrella: true},
      {:uniris_sync, in_umbrella: true},
      {:mox, "~> 0.5.1"}
    ]
  end
end
