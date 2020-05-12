defmodule Uniris.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_options: [warnings_as_errors: true],

      releases: [
        uniris_node: [
          include_executables_for: [:unix],
          applications: [
            runtime_tools: :permanent,
            uniris_core: :permanent,
            uniris_web: :temporary
          ]
        ],
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
