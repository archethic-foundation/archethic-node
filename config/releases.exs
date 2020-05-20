import Config

config :uniris_core, UnirisCore.Crypto,
  seed: System.fetch_env!("UNIRIS_CRYPTO_SEED")

config :uniris_core, UnirisCore.P2P,
  port: System.fetch_env!("UNIRIS_P2P_PORT") || 3002

config :uniris_web, UnirisWeb.Endpoint,
  http: [port: System.get_env("UNIRIS_WEB_PORT") || 80],
  url: [port: System.get_env("UNIRIS_WEB_PORT") || 80]
