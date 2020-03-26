import Mix.Config

config :uniris_p2p_server,
       :port,
       System.get_env("UNIRIS_P2P_PORT", "3002") |> String.to_integer()
