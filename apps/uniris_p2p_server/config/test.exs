import Mix.Config

config :uniris_p2p_server,
       :port,
       3003

config :uniris_p2p, :impl, MockP2P
config :uniris_election, :impl, MockElection
config :uniris_validation, :impl, MockValidation
config :uniris_chain, :impl, MockChain
