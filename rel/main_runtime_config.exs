import Config

config :uniris, Uniris.P2P.Endpoint,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()

config :uniris, UnirisWeb.Endpoint,
  http: [:inet6, port: System.get_env("UNIRIS_WEB_PORT", "80") |> String.to_integer()],
  url: [host: "*", port: 443],
  https: [
    keyfile: System.get_env("UNIRIS_WEB_SSL_KEY_PATH", ""),
    certfile: System.get_env("UNIRIS_WEB_SSL_CERT_PATH", "")
  ]

config :uniris, Uniris.Crypto.SoftwareKeystore, seed: System.fetch_env!("UNIRIS_CRYPTO_SEED")
