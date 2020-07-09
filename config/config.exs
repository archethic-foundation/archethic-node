use Mix.Config

import_config "../apps/*/config/config.exs"

config :logger, :console, format: "\n$time $metadata[$level] $levelpad$message\n"

config :logger,
  utc_log: true,
  handle_otp_reports: true,
  handle_sasl_reports: false

if Mix.env() != :prod do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          "mix format",
          "mix clean",
          "mix compile --warnings-as-errors",
          "mix xref deprecated --abort-if-any",
          "mix xref unreachable --abort-if-any",
          "mix format --check-formatted",
          "mix credo --strict",
          # "mix doctor --summary",
          "mix test"
        ]
      ]
    ]
end
