import Config

config :uniris_core, UnirisCore.Crypto,
  seed: System.fetch_env!("UNIRIS_CRYPTO_SEED")

config :uniris_core, UnirisCore.P2P,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()

config :uniris_web, UnirisWeb.Endpoint,
  https: [
    port: System.get_env("UNIRIS_WEB_PORT", "443") |> String.to_integer(),
    keyfile: System.fetch_env!("UNIRIS_WEB_SSL_KEY_PATH"),
    certfile: System.fetch_env!("UNIRIS_WEB_SSL_CERT_PATH")
  ],
  url: [port: System.get_env("UNIRIS_WEB_PORT", "443") |> String.to_integer()]
