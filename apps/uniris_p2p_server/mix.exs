defmodule UnirisP2PServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :uniris_p2p_server,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {UnirisP2PServer.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:uniris_p2p, in_umbrella: true},
      {:uniris_chain, in_umbrella: true},
      {:uniris_election, in_umbrella: true},
      {:uniris_validation, in_umbrella: true},
      {:uniris_pubsub, in_umbrella: true},
      {:mox, "~> 0.5.2"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      # {:sibling_app_in_umbrella, in_umbrella: true}
    ]
  end
end
