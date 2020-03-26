defmodule Uniris.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        uniris: [
          include_executables_for: [:unix],
          applications: [
            uniris_chain: :permanent,
            uniris_crypto: :permanent,
            uniris_election: :permanent,
            uniris_interpreter: :permanent,
            uniris_p2p: :permanent,
            uniris_p2p_server: :permanent,
            uniris_shared_secrets: :permanent,
            uniris_beacon: :permanent,
            uniris_pubsub: :permanent,
            uniris_sync: :permanent,
            uniris_validation: :permanent,
            uniris_web: :permanent
          ]
        ]
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:ex_doc, "~> 0.21.2"},
      {:credo, "~> 1.1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
