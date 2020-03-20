import Mix.Config

Application.put_env(:uniris_shared_secrets, :impl, MockSharedSecrets)
Application.put_env(:uniris_p2p, :impl, MockP2P)
Application.put_env(:uniris_election, :impl, MockElection)
Application.put_env(:uniris_chain, :impl, MockChain)

config :logger, level: :error
