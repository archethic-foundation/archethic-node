defmodule Archethic.MixProject do
  use Mix.Project

  def project do
    [
      app: :archethic,
      version: "0.25.0",
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
      {:phoenix, "~> 1.6.0"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_view, "~> 0.18.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.3"},
      {:absinthe, "~> 1.7.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:cors_plug, "~> 1.5"},
      {:mint, "~> 1.0"},
      {:ecto, "~> 3.9"},
      {:websockex, "~> 0.4.3"},

      # Dev
      {:benchee, "~> 1.1"},
      {:benchee_html, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:git_hooks, "~> 0.7.0", runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.6.0", runtime: false},
      {:dialyxir, "~> 1.2", runtime: false},
      {:logger_file_backend, "~> 0.0.13", only: :dev},

      # Security
      {:sobelow, ">= 0.11.1", only: [:test, :dev], runtime: false},

      # Test
      {:mox, "~> 1.0.2", only: [:test]},
      {:stream_data, "~> 0.5.0", only: [:test], runtime: false},
      {:floki, ">= 0.33.0", only: :test},

      # P2P
      {:ranch, "~> 2.1", override: true},
      {:mmdb2_decoder, "~> 3.0"},

      # Net
      {:inet_ext, "~> 1.0"},
      {:inet_cidr, "~> 1.1", hex: :erl_cidr, override: true},

      # Monitoring
      {:observer_cli, "~> 1.5"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_metrics_prometheus_core, "~> 1.1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.7"},

      # Utils
      {:crontab, "~> 1.1"},
      {:earmark, "~> 1.4"},
      {:sizeable, "~> 1.0"},
      {:distillery, github: "bitwalker/distillery", ref: "6700edb"},
      {:exjsonpath, "~> 0.9.0"},
      {:rand_compat, "~> 0.0.3"},
      {:gen_state_machine, "~> 3.0"},
      {:retry, "~> 0.17.0"},
      {:gen_stage, "~> 1.1"},
      {:flow, "~> 1.2"},
      {:knigge, "~> 1.4"},
      {:ex_json_schema, "~> 0.9.2", override: true},
      {:pathex, "~> 2.4"},
      {:easy_ssl, "~> 1.3.0"},
      {:castore, "~> 0.1.18"}
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
      "dev.checks": [
        "clean",
        "format",
        "compile",
        "credo",
        "sobelow",
        "cmd mix test --trace",
        "dialyzer"
      ],
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
      "dev.lbench": ["cmd mix archethic.regression --bench localhost"],
      # production aliases
      "prod.run": ["cmd  MIX_ENV=prod ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL=SOFTWARE
      ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS=SOFTWARE ARCHETHIC_NODE_IP_VALIDATION='true' iex -S mix"],
      # dry-run,
      "run.dry": ["cmd iex -S mix run --no-start"],
      # Make sure the plts folder is created
      dialyzer: ["cmd mkdir -p priv/plts", "dialyzer"]
    ]
  end
end
