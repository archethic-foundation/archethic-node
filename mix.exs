defmodule Uniris.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_options: [warnings_as_errors: true]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:ex_doc, "~> 0.21.2", only: :dev},
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:observer_cli, "~> 1.5"},
      {:distillery, "~> 2.0"},
      {:git_hooks, "~> 0.4.0", only: [:test, :dev], runtime: false}
    ]
  end
end
