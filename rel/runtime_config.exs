import Config

config :uniris_core, UnirisCore.P2P,
  port: 3002

config :uniris_web, UnirisWeb.Endpoint,
  https: [
    keyfile: System.fetch_env!("UNIRIS_WEB_SSL_KEY_PATH"),
    certfile: System.fetch_env!("UNIRIS_WEB_SSL_CERT_PATH")
  ]
