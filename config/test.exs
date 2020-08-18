use Mix.Config

# Print only warnings and errors during test
config :logger, level: :warning

config :uniris, Uniris.Crypto, keystore: MockCrypto

config :uniris, Uniris.Crypto.SoftwareKeystore, seed: "fake seed"

config :uniris, Uniris.Crypto.Keystore, enabled: false
config :uniris, Uniris.Crypto.TransactionLoader, enabled: false

config :uniris, Uniris.Storage, backend: MockStorage
config :uniris, Uniris.Storage.KeyValueBackend, enabled: false
config :uniris, Uniris.Storage.CassandraBackend, enabled: false
config :uniris, MockStorage, enabled: false
config :uniris, Uniris.Storage.Cache, enabled: false

config :uniris, Uniris.P2P, node_client: MockNodeClient

config :uniris, Uniris.P2P.Endpoint, enabled: false

config :uniris, Uniris.P2P.TransactionLoader, enabled: false

config :uniris, Uniris.BeaconSubset, enabled: false

config :uniris, Uniris.BeaconSlotTimer,
  enabled: false,
  interval: 0,
  trigger_offset: 0

config :uniris, Uniris.SharedSecrets.TransactionLoader, enabled: false

config :uniris, Uniris.SharedSecrets.NodeRenewal,
  enabled: false,
  trigger_interval: 0,
  interval: 0

config :uniris, Uniris.SelfRepair,
  enabled: false,
  interval: 0,
  last_sync_file: "priv/p2p/last_sync",
  network_startup_date: DateTime.utc_now()

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

config :uniris, Uniris.Interpreter.TransactionLoader, enabled: false

config :uniris, Uniris.P2P.BootstrapingSeeds, enabled: false

config :uniris, Uniris.Governance.Testnet, impl: MockTestnet

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :uniris, UnirisWeb.Endpoint,
  http: [port: 4002],
  server: false
