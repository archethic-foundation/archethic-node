use Mix.Config

import_config "../apps/*/config/config.exs"

config :logger, :console, format: "\n$time $metadata[$level] $levelpad$message\n"

config :logger,
  utc_log: true,
  handle_otp_reports: true,
  handle_sasl_reports: false
