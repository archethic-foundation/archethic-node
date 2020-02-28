import Mix.Config

config :uniris_p2p, :port, 3001
config :uniris_network, :impl, MockNetwork
config :uniris_network, :p2p_impl, MockP2P
config :uniris_chain, :impl, MockChain
config :uniris_election, :impl, MockElection
config :uniris_validation, :impl, MockValidation
