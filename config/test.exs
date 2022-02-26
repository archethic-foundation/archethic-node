import Config

# Print only errors during test
config :logger, level: :error

config :archethic, :mut_dir, "data_test"

config :archethic, ArchEthic.Account.MemTablesLoader, enabled: false
config :archethic, ArchEthic.Account.MemTables.NFTLedger, enabled: false
config :archethic, ArchEthic.Account.MemTables.UCOLedger, enabled: false

config :archethic, ArchEthic.BeaconChain.Subset, enabled: false

config :archethic, ArchEthic.BeaconChain.SlotTimer,
  enabled: false,
  interval: "0 * * * * *"

config :archethic, ArchEthic.BeaconChain.SummaryTimer,
  enabled: false,
  interval: "0 * * * * *"

config :archethic, ArchEthic.Bootstrap, enabled: false

config :archethic, ArchEthic.Bootstrap.Sync, out_of_sync_date_threshold: 3

config :archethic, ArchEthic.Bootstrap.NetworkInit,
  genesis_pools: [
    %{
      address:
        "000073bdaf847037115914ff5ca15e52d162db57b5089d5e4bf2005d825592c9c945"
        |> Base.decode16!(case: :mixed),
      amount: 1_000_000_000_000_000
    }
  ]

config :archethic, ArchEthic.Contracts.Loader, enabled: false

config :archethic, ArchEthic.Crypto,
  root_ca_public_keys: [
    #  From `:crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")`
    software:
      <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
        194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
        186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
        70, 95, 28, 35, 233, 21, 230>>,
    tpm:
      <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
        194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
        186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
        70, 95, 28, 35, 233, 21, 230>>
  ],
  software_root_ca_key: :crypto.generate_key(:ecdh, :secp256r1, "ca_root_key") |> elem(1)

config :archethic, ArchEthic.Crypto.NodeKeystore, MockCrypto
config :archethic, ArchEthic.Crypto.NodeKeystore.SoftwareImpl, seed: "fake seed"
config :archethic, ArchEthic.Crypto.SharedSecretsKeystore, MockCrypto
config :archethic, ArchEthic.Crypto.KeystoreCounter, enabled: false
config :archethic, ArchEthic.Crypto.KeystoreLoader, enabled: false

config :archethic, MockCrypto, enabled: false

config :archethic, ArchEthic.DB, MockDB

config :archethic, ArchEthic.DB.CassandraImpl, host: "127.0.0.1:9042"

config :archethic, MockDB, enabled: false

config :archethic, ArchEthic.Election.Constraints, enabled: false

config :archethic, ArchEthic.Governance.Code.TestNet, MockTestnet

config :archethic, ArchEthic.Governance.Pools,
  initial_members: [
    technical_council: [],
    ethical_council: [],
    foundation: [],
    archethic: []
  ]

config :archethic, ArchEthic.Governance.Pools.MemTable, enabled: false
config :archethic, ArchEthic.Governance.Pools.MemTableLoader, enabled: false

config :archethic, ArchEthic.OracleChain.MemTable, enabled: false
config :archethic, ArchEthic.OracleChain.MemTableLoader, enabled: false

config :archethic, ArchEthic.OracleChain.Scheduler,
  enabled: false,
  polling_interval: "0 0 * * * *",
  summary_interval: "0 0 0 * * *"

config :archethic, ArchEthic.OracleChain.Services.UCOPrice, provider: MockUCOPriceProvider

config :archethic, ArchEthic.Networking.IPLookup, MockIPLookup
config :archethic, ArchEthic.Networking.PortForwarding, MockPortForwarding
config :archethic, ArchEthic.Networking.Scheduler, enabled: false

config :archethic, ArchEthic.P2P.Listener, enabled: false
config :archethic, ArchEthic.P2P.MemTableLoader, enabled: false
config :archethic, ArchEthic.P2P.MemTable, enabled: false
config :archethic, ArchEthic.P2P.Client, MockClient

config :archethic, ArchEthic.P2P.BootstrappingSeeds, enabled: false

config :archethic, ArchEthic.Mining.PendingTransactionValidation, validate_node_ip: true

config :archethic, ArchEthic.Reward.NetworkPoolScheduler, enabled: false
config :archethic, ArchEthic.Reward.WithdrawScheduler, enabled: false

config :archethic, ArchEthic.SelfRepair.Scheduler,
  enabled: false,
  interval: 0

config :archethic, ArchEthic.SelfRepair.Notifier, enabled: false

config :archethic, ArchEthic.SelfRepair.Sync,
  network_startup_date: DateTime.utc_now(),
  last_sync_file: "p2p/last_sync_test"

config :archethic, ArchEthic.SharedSecrets.MemTablesLoader, enabled: false
config :archethic, ArchEthic.SharedSecrets.MemTables.NetworkLookup, enabled: false
config :archethic, ArchEthic.SharedSecrets.MemTables.OriginKeyLookup, enabled: false

config :archethic, ArchEthic.SharedSecrets.NodeRenewalScheduler,
  enabled: false,
  interval: "0 0 * * * * *",
  application_interval: "0 0 * * * * *"

config :archethic, ArchEthic.TransactionChain.MemTables.PendingLedger, enabled: false
config :archethic, ArchEthic.TransactionChain.MemTables.KOLedger, enabled: false
config :archethic, ArchEthic.TransactionChain.MemTablesLoader, enabled: false

config :archethic, ArchEthicWeb.FaucetController, enabled: true

# MetricsModule test config
# ------------------------------------------------------------------------------
config :archethic, :metrics_endpoint, MockMetrics
# ------------------------------------------------------------------------------

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :archethic, ArchEthicWeb.Endpoint,
  http: [port: 4002],
  server: false
