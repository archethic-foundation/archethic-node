use Mix.Config

# Print only warnings and errors during test
config :logger, level: :warning

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

config :uniris, Uniris.Bootstrap,
  ip_lookup_provider: MockIPLookup,
  enabled: false

config :uniris, Uniris.Bootstrap.NetworkInit,
  genesis_pools: [
    funding: [
      public_key: "002E354A95241E867C836E8BBBBF6F9BF2450860BA28B1CF24B734EF67FF49169E",
      amount: 3.82e9
    ],
    deliverable: [
      public_key: "00AD439F0CD4048576D4AFB812DCB1815C57EFC303BFF03696436B157C69547128",
      amount: 2.36e9
    ],
    enhancement: [
      public_key: "008C9309535A3853379D6367F67AB93E3DAF5BFAA41C68BD7C3C1F00AA8D5822FD",
      amount: 9.0e8
    ],
    team: [
      public_key: "00B1F862FF9E534DAC6A0AD32528E08F7BB0F3DD0DCB253B119900F4CE447C5CC4",
      amount: 5.6e8
    ],
    exchange: [
      public_key: "004CD06F40D2F75DA02B29D559A3CBD5E07580B1E65163A4F3256CDC8781B280E3",
      amount: 3.4e8
    ],
    marketing: [
      public_key: "00783510644E885FFAC82FE22FB3F33C5B0936B79B7A3D3A78D5D612341A0B3B9A",
      amount: 3.4e8
    ],
    foundation: [
      public_key: "00CD534224DE5AE2584163D69A8A99F36E6FAE506373B619736B511A58B804E311",
      amount: 2.2e8
    ]
  ]

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

config :uniris, Uniris.P2P.Endpoint, enabled: false
config :uniris, Uniris.P2P.MemTableLoader, enabled: false
config :uniris, Uniris.P2P.MemTable, enabled: false
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
