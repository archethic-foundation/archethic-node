import Config

# Print only errors during test
config :logger, level: :error

config :uniris, :mut_dir, "data_test"

config :uniris, Uniris.Account.MemTablesLoader, enabled: false
config :uniris, Uniris.Account.MemTables.NFTLedger, enabled: false
config :uniris, Uniris.Account.MemTables.UCOLedger, enabled: false

config :uniris, Uniris.BeaconChain.Subset, enabled: false

config :uniris, Uniris.BeaconChain.SlotTimer,
  enabled: false,
  interval: "0 * * * * *"

config :uniris, Uniris.BeaconChain.SummaryTimer,
  enabled: false,
  interval: "0 * * * * *"

config :uniris, Uniris.Bootstrap, enabled: false

config :uniris, Uniris.Bootstrap.Sync, out_of_sync_date_threshold: 3

config :uniris, Uniris.Contracts.Loader, enabled: false

config :uniris, Uniris.Crypto.Keystore, impl: MockCrypto, enabled: false
config :uniris, Uniris.Crypto.KeystoreLoader, enabled: false
config :uniris, Uniris.Crypto.SoftwareKeystore, seed: "fake seed"

config :uniris, Uniris.DB, impl: MockDB
config :uniris, MockDB, enabled: false

config :uniris, Uniris.Election.Constraints, enabled: false

config :uniris, Uniris.Governance.Code.TestNet, impl: MockTestnet

config :uniris, Uniris.Governance.Pools,
  initial_members: [
    technical_council: [],
    ethical_council: [],
    foundation: [],
    uniris: []
  ]

config :uniris, Uniris.Governance.Pools.MemTable, enabled: false
config :uniris, Uniris.Governance.Pools.MemTableLoader, enabled: false

config :uniris, Uniris.OracleChain.MemTable, enabled: false
config :uniris, Uniris.OracleChain.MemTableLoader, enabled: false

config :uniris, Uniris.OracleChain.Scheduler,
  enabled: false,
  polling_interval: "0 0 * * * *",
  summary_interval: "0 0 0 * * *"

config :uniris, Uniris.OracleChain.Services.UCOPrice, provider: MockUCOPriceProvider

config :uniris, Uniris.Networking.IPLookup, impl: MockIPLookup
config :uniris, Uniris.Networking.PortForwarding, impl: MockPortForwarding

config :uniris, Uniris.P2P.Batcher, enabled: false
config :uniris, Uniris.P2P.Endpoint.Listener, enabled: false
config :uniris, Uniris.P2P.MemTableLoader, enabled: false
config :uniris, Uniris.P2P.MemTable, enabled: false
config :uniris, Uniris.P2P.Client, impl: MockClient
config :uniris, Uniris.P2P.Transport, impl: MockTransport

config :uniris, Uniris.P2P.BootstrappingSeeds, enabled: false

config :uniris, Uniris.SelfRepair.Scheduler,
  enabled: false,
  interval: 0

config :uniris, Uniris.SelfRepair.Sync,
  network_startup_date: DateTime.utc_now(),
  last_sync_file: "priv/p2p/last_sync_test"

config :uniris, Uniris.SelfRepair.Sync.BeaconSummaryHandler.NetworkStatistics,
  dump_dir: "priv/p2p/network_stats_test",
  enabled: false

config :uniris, Uniris.SharedSecrets.MemTablesLoader, enabled: false
config :uniris, Uniris.SharedSecrets.MemTables.OriginKeyLookup, enabled: false

config :uniris, Uniris.SharedSecrets.NodeRenewalScheduler,
  enabled: false,
  trigger_interval: 0,
  interval: 0

config :uniris, Uniris.TransactionChain.MemTables.ChainLookup, enabled: false
config :uniris, Uniris.TransactionChain.MemTables.PendingLedger, enabled: false
config :uniris, Uniris.TransactionChain.MemTables.KOLedger, enabled: false
config :uniris, Uniris.TransactionChain.MemTablesLoader, enabled: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :uniris, UnirisWeb.Endpoint,
  http: [port: 4002],
  server: false
