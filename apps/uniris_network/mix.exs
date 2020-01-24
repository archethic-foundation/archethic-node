defmodule UnirisNetwork.MixProject do
  use Mix.Project

  def project do
    [
      app: :uniris_network,
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
      mod: {UnirisNetwork.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ranch, "~> 1.7"},
      {:uniris_crypto, in_umbrella: true},
      {:uniris_chain, in_umbrella: true},
      {:mox, "~> 0.5.1", only: [:test]},
      {:stream_data, "~> 0.4.3", only: [:test]} 
    ]
  end
end
