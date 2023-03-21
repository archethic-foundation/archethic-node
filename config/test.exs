import Config

# Print only errors during test
config :logger, level: :error

config :archethic, :mut_dir, "data_test"

config :archethic, Archethic.Account.MemTablesLoader, enabled: false
config :archethic, Archethic.Account.MemTables.TokenLedger, enabled: false
config :archethic, Archethic.Account.MemTables.UCOLedger, enabled: false

config :archethic, Archethic.BeaconChain.Subset, enabled: false

config :archethic, Archethic.BeaconChain.SlotTimer,
  enabled: false,
  interval: "0 * * * * *"

config :archethic, Archethic.BeaconChain.SummaryTimer,
  enabled: false,
  interval: "0 * * * * *"

config :archethic, Archethic.BeaconChain.Subset.SummaryCache, enabled: false

config :archethic, Archethic.Bootstrap, enabled: false

config :archethic, Archethic.Bootstrap.Sync, out_of_sync_date_threshold: 3

config :archethic, Archethic.Bootstrap.NetworkInit,
  genesis_pools: [
    %{
      address:
        "000073bdaf847037115914ff5ca15e52d162db57b5089d5e4bf2005d825592c9c945"
        |> Base.decode16!(case: :mixed),
      amount: 1_000_000_000_000_000
    }
  ]

config :archethic, Archethic.Contracts.Loader, enabled: false

config :archethic, Archethic.Crypto,
  root_ca_public_keys: [
    tpm: [
      #  From `:crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")`
      secp256r1:
        <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
          194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
          186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
          70, 95, 28, 35, 233, 21, 230>>
    ],
    software: [
      secp256r1:
        <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
          194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
          186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
          70, 95, 28, 35, 233, 21, 230>>
    ]
  ]

config :archethic, MockCrypto.NodeKeystore, enabled: false
config :archethic, MockCrypto.NodeKeystore.Origin, enabled: false
config :archethic, MockCrypto.SharedSecretsKeystore, enabled: false

config :archethic, Archethic.Crypto.NodeKeystore, MockCrypto.NodeKeystore
config :archethic, Archethic.Crypto.NodeKeystore.Origin, MockCrypto.NodeKeystore.Origin
config :archethic, Archethic.Crypto.SharedSecretsKeystore, MockCrypto.SharedSecretsKeystore

config :archethic, Archethic.DB, MockDB
config :archethic, MockDB, enabled: false

config :archethic, Archethic.Election.Constraints, enabled: false

config :archethic, Archethic.Governance.Code.TestNet, MockTestnet

config :archethic, Archethic.Governance.Pools,
  initial_members: [
    technical_council: [],
    ethical_council: [],
    foundation: [],
    archethic: []
  ]

config :archethic, Archethic.Governance.Pools.MemTable, enabled: false
config :archethic, Archethic.Governance.Pools.MemTableLoader, enabled: false

config :archethic, Archethic.OracleChain.MemTable, enabled: false
config :archethic, Archethic.OracleChain.MemTableLoader, enabled: false

config :archethic, Archethic.OracleChain.Scheduler,
  enabled: false,
  polling_interval: "0 0 * * * *",
  summary_interval: "0 0 0 * * *"

config :archethic, Archethic.OracleChain.Services.UCOPrice,
  providers: [MockUCOPriceProvider1, MockUCOPriceProvider2, MockUCOPriceProvider3]

# -----Start-of-Networking-tests-configs-----

config :archethic, Archethic.Networking, validate_node_ip: false

config :archethic, Archethic.Networking.IPLookup, MockIPLookup
config :archethic, Archethic.Networking.IPLookup.Static, MockStatic

# Regardless of default upnpV1 use MockNATDiscovery
config :archethic, Archethic.Networking.IPLookup.NATDiscovery, provider: MockNATDiscovery
# Regardless of default IPIFY use MockRemoteDiscovery
config :archethic, Archethic.Networking.IPLookup.RemoteDiscovery, provider: MockRemoteDiscovery

config :archethic, Archethic.Networking.Scheduler, enabled: false

# -----End-of-Networking-tests-configs ------

config :archethic, Archethic.P2P.Listener, enabled: false
config :archethic, Archethic.P2P.MemTableLoader, enabled: false
config :archethic, Archethic.P2P.MemTable, enabled: false
config :archethic, Archethic.P2P.Client, MockClient
config :archethic, Archethic.P2P.GeoPatch.GeoIP, MockGeoIP

config :archethic, Archethic.P2P.BootstrappingSeeds, enabled: false

config :archethic, Archethic.Mining.PendingTransactionValidation, validate_node_ip: true

config :archethic, Archethic.Metrics.Poller, enabled: false
config :archethic, Archethic.Metrics.Collector, MockMetricsCollector

config :archethic, Archethic.Reward.Scheduler, enabled: false, interval: "0 0 * * * * *"
config :archethic, Archethic.Reward.MemTables.RewardTokens, enabled: false
config :archethic, Archethic.Reward.MemTablesLoader, enabled: false

config :archethic, Archethic.SelfRepair.Scheduler,
  enabled: false,
  interval: "0 0 * * * * *",
  availability_application: 1

config :archethic, Archethic.SelfRepair.NetworkView, enabled: false
config :archethic, Archethic.SelfRepair.Notifier, enabled: false

config :archethic, Archethic.SelfRepair.Sync,
  network_startup_date: DateTime.utc_now(),
  last_sync_file: "p2p/last_sync_test"

config :archethic, Archethic.SharedSecrets.MemTablesLoader, enabled: false
config :archethic, Archethic.SharedSecrets.MemTables.NetworkLookup, enabled: false
config :archethic, Archethic.SharedSecrets.MemTables.OriginKeyLookup, enabled: false

config :archethic, Archethic.SharedSecrets.NodeRenewalScheduler,
  enabled: false,
  interval: "0 0 * * * * *",
  application_interval: "0 0 * * * * *"

config :archethic, Archethic.TransactionChain.MemTables.PendingLedger, enabled: false
config :archethic, Archethic.TransactionChain.MemTables.KOLedger, enabled: false
config :archethic, Archethic.TransactionChain.MemTablesLoader, enabled: false

config :archethic, Archethic.Utils.DetectNodeResponsiveness, timeout: 1_000

config :archethic, ArchethicWeb.FaucetController, enabled: true
config :archethic, ArchethicWeb.FaucetRateLimiter, enabled: false
config :archethic, ArchethicWeb.TransactionSubscriber, enabled: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :archethic, ArchethicWeb.Endpoint,
  explorer_url: "",
  http: [port: 4002],
  server: false

config :archethic, :throttle,
  by_ip_high: [
    period: 1000,
    limit: 5_000
  ],
  by_ip_low: [
    period: 1000,
    limit: 5_000
  ],
  by_ip_and_path: [
    period: 1000,
    limit: 5_000
  ]
