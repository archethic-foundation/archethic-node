defmodule Archethic.MixProject do
  use Mix.Project

  def project do
    [
      app: :archethic,
      version: "0.14.0",
      build_path: "_build",
      config_path: "config/config.exs",
      deps_path: "deps",
      lockfile: "mix.lock",
      aliases: aliases(),
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make, :phoenix] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :os_mon, :runtime_tools, :xmerl],
      mod: {Archethic.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specify dialyzer path
  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Web
      {:phoenix, ">= 1.5.4"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_live_view, "~> 0.15.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.3"},
      {:absinthe, "~> 1.5.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:cors_plug, "~> 1.5"},
      {:mint, "~> 1.0"},
      {:ecto, "~> 3.5"},
      {:websockex, "~> 0.4.3"},

      # Dev
      {:benchee, "~> 1.0"},
      {:benchee_html, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:git_hooks, "~> 0.4.0", runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.6.0", runtime: false},
      {:dialyxir, "~> 1.0", runtime: false},
      # {:broadway_dashboard, "~> 0.2.0", only: :dev},

      # Test
      {:mox, "~> 0.5.2", only: [:test]},
      {:stream_data, "~> 0.5.0", only: [:test], runtime: false},
      {:floki, ">= 0.30.0", only: :test},

      # P2P
      {:ranch, "~> 2.1", override: true},
      {:connection, "~> 1.1"},

      # Net
      {:inet_ext, "~> 1.0"},
      {:inet_cidr, "~> 1.1", hex: :erl_cidr, override: true},

      # Monitoring
      {:observer_cli, "~> 1.5"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_metrics_prometheus_core, "~> 1.0.0"},
      {:telemetry_poller, "~> 0.5.1"},
      {:phoenix_live_dashboard, "~> 0.3"},

      # Utils
      {:crontab, "~> 1.1"},
      {:earmark, "~> 1.4"},
      {:sizeable, "~> 1.0"},
      {:distillery, github: "bitwalker/distillery", ref: "6700edb"},
      {:exjsonpath, "~> 0.9.0"},
      {:rand_compat, "~> 0.0.3"},
      {:gen_state_machine, "~> 3.0"},
      {:retry, "~> 0.14.1"},
      {:gen_stage, "~> 1.1"},
      {:flow, "~> 1.0"},
      {:broadway, "~> 1.0"},
      {:knigge, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      # Intial developer Setup
      "dev.setup": ["deps.get", "cmd npm install --prefix assets"],
      # When Changes are not registered by compiler | any()
      "dev.clean": ["cmd make clean", "clean", "format", "compile"],
      # run single node
      "dev.run": ["deps.get", "cmd mix dev.clean", "cmd iex -S mix"],
      # Must be run before git push --no-verify | any(dialyzer issue)
      "dev.checks": ["clean", "format", "compile", "credo", "cmd mix test", "dialyzer"],
      # paralele checks
      "dev.pchecks": ["  clean &   format &    compile &   credo &   test &   dialyzer"],
      # docker test-net with 3 nodes
      "dev.docker": [
        "cmd docker-compose down",
        "cmd docker build -t archethic-node .",
        "cmd docker-compose up"
      ],
      # benchmark
      "dev.bench": ["cmd docker-compose up bench"],
      # Cleans docker
      "dev.debug_docker": ["cmd docker-compose down", "cmd docker system prune -a"],
      # bench local
      "dev.lbench": ["cmd mix archethic.regression --bench localhost"]
    ]
  end
end
