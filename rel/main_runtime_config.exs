import Config

config :uniris, UnirisCore.P2P.Endpoint,
  port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()

config :uniris, UnirisWeb.Endpoint,
  http: [:inet6, port: System.get_env("UNIRIS_WEB_PORT", "80") |> String.to_integer()],
  url: [host: "*", port: 443],
  https: [
    keyfile: System.fetch_env!("UNIRIS_WEB_SSL_KEY_PATH"),
    certfile: System.fetch_env!("UNIRIS_WEB_SSL_CERT_PATH")
  ]

config :uniris, Uniris.P2P.BootstrapingSeeds,
  seeds: "127.0.0.1:3002:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"

config :uniris, Uniris.Crypto.SoftwareKeystore,
  seed: System.get_env("UNIRIS_CRYPTO_SEED")
  import Config

  config :uniris, UnirisCore.P2P.Endpoint,
    port: System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()
  
  config :uniris, UnirisWeb.Endpoint,
    http: [:inet6, port: System.get_env("UNIRIS_WEB_PORT", "80") |> String.to_integer()],
    url: [host: "*", port: 443],
    https: [
      keyfile: System.get_env("UNIRIS_WEB_SSL_KEY_PATH", ""),
      certfile: System.get_env("UNIRIS_WEB_SSL_CERT_PATH", "")
    ]
  
  config :uniris, Uniris.P2P.BootstrapingSeeds,
    seeds: System.get_env("UNIRIS_P2P_SEEDS")
  
  config :uniris, Uniris.Crypto.SoftwareKeystore,
    seed: System.get_env("UNIRIS_CRYPTO_SEED")