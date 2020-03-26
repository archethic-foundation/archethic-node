import Mix.Config

config :uniris_sync, :self_repair_interval, 0
config :uniris_sync, :last_sync_date, DateTime.utc_now()

config :uniris_p2p, :impl, MockP2P
config :uniris_validation, :impl, MockValidation
config :uniris_chain, :impl, MockChain
config :uniris_election, :impl, MockElection
