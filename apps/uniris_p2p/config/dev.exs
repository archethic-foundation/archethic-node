import Mix.Config

config :uniris_p2p, :ip, System.get_env("UNIRIS_P2P_IP", "127.0.0.1")

config :uniris_p2p,
       :port,
       System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()
