use Mix.Config

import_config "../apps/*/config/config.exs"

config :logger,
  handle_otp_reports: true,
  handle_sasl_reports: true
