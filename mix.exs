defmodule Archethic.MixProject do
  use Mix.Project

  def project do
    [
      app: :archethic,
      version: "1.4.7",
      build_path: "_build",
      config_path: "config/config.exs",
      deps_path: "deps",
      lockfile: "mix.lock",
      aliases: aliases(),
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      dialyzer: dialyzer()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [
        :public_key,
        :crypto,
        :logger,
        :inets,
        :os_mon,
        :runtime_tools,
        :xmerl,
        :crypto
      ],
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
      {:phoenix, "~> 1.6"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_view, "~> 0.18"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.0"},
      {:plug_cowboy, "~> 2.3"},
      {:absinthe, "1.7.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:cors_plug, "~> 3.0"},
      {:mint, "~> 1.0"},
      {:ecto, "~> 3.9"},
      {:websockex, "~> 0.4"},
      {:plug_attack, "~> 0.4.3"},

      # Dev
      {:benchee, "~> 1.1"},
      {:benchee_html, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:git_hooks, "~> 0.7", runtime: false},
      {:credo, "~> 1.6", runtime: false},
      {:elixir_make, "~> 0.6", runtime: false},
      {:dialyxir, "~> 1.2", runtime: false},
      {:logger_file_backend, "~> 0.0.13", only: :dev},
      {:esbuild, "~> 0.2", runtime: Mix.env() == :dev},
      {:dart_sass, "~> 0.5", runtime: Mix.env() == :dev},

      # Security
      {:sobelow, "~> 0.11", runtime: false},

      # Test
      {:mox, "~> 1.0", only: [:test]},
      {:mock, "~> 0.3.7", only: [:test]},
      {:stream_data, "~> 0.6", only: [:test], runtime: false},

      # P2P
      {:ranch, "~> 2.1", override: true},
      {:mmdb2_decoder, "~> 3.0"},

      # Net
      {:inet_ext, "~> 1.0"},
      {:inet_cidr, "~> 1.1", hex: :erl_cidr, override: true},

      # Monitoring
      {:observer_cli, "~> 1.5"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_metrics_prometheus_core, "~> 1.1"},
      {:telemetry_poller, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.7"},

      # Utils
      {:crontab, "~> 1.1"},
      {:earmark, "~> 1.4"},
      {:sizeable, "~> 1.0"},
      {:distillery, github: "archethic-foundation/distillery"},
      {:exjsonpath, "~> 0.9"},
      {:rand_compat, "~> 0.0.3"},
      {:gen_state_machine, "~> 3.0"},
      {:retry, "~> 0.17"},
      {:knigge, "~> 1.4"},
      {:ex_json_schema, "~> 0.9", override: true},
      {:pathex, "~> 2.4"},
      {:easy_ssl, "~> 1.3"},
      {:castore, "~> 1.0", override: true},
      {:floki, "~> 0.33"},
      {:ex_cldr, "~> 2.7"},
      {:ex_cldr_numbers, "~> 2.29"},
      {:git_diff, "~> 0.6.4"},
      {:decimal, "~> 2.0"},
      {:plug_crypto, "~> 1.2"},
      {:ex_abi, "0.6.1"},

      # Numbering
      {:nx, "~> 0.5"},
      {:exla, "~> 0.5"},
      {:ex_keccak, "0.7.1"},
      {:ex_secp256k1, "~> 0.7.2"}
    ]
  end

  defp aliases do
    [
      "check.updates": ["cmd mix hex.outdated --within-requirements || echo 'Updates available!'"],
      compile: ["git_hooks.install", "compile"],
      "dev.update_deps": [
        "hex.outdated --within-requirements",
        "deps.update --all --only",
        "deps.clean --all --only",
        "deps.get",
        "deps.compile",
        "hex.outdated --within-requirements"
      ],
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
        " hex.outdated --within-requirements",
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
      dialyzer: ["cmd mkdir -p priv/plts", "dialyzer"],
      "assets.saas": ["sass default --no-source-map --style=compressed"],
      "assets.deploy": [
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
