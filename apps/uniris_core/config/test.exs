use Mix.Config

config :uniris_core, UnirisCore.Crypto, keystore: MockCrypto

config :uniris_core, UnirisCore.Crypto.SoftwareKeystore, seed: "fake seed"

config :uniris_core, UnirisCore.Crypto.Keystore, enabled: false
config :uniris_core, UnirisCore.Crypto.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.Storage, backend: MockStorage
config :uniris_core, UnirisCore.Storage.FileBackend, enabled: false
config :uniris_core, UnirisCore.Storage.CassandraBackend, enabled: false
config :uniris_core, MockStorage, enabled: false
config :uniris_core, UnirisCore.Storage.Cache, enabled: false

config :uniris_core, UnirisCore.P2P,
  port: 10_000,
  node_client: MockNodeClient

config :uniris_core, UnirisCore.P2P.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.BeaconSubset, enabled: false

config :uniris_core, UnirisCore.BeaconSlotTimer,
  enabled: false,
  interval: 0,
  trigger_offset: 0

config :uniris_core, UnirisCore.SharedSecrets.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.SharedSecrets.NodeRenewal,
  enabled: false,
  trigger_interval: 0,
  interval: 0

config :uniris_core, UnirisCore.SelfRepair,
  enabled: false,
  interval: 0,
  network_startup_date: DateTime.utc_now()

config :uniris_core, UnirisCore.Bootstrap,
  ip_lookup_provider: MockIPLookup,
  enabled: false

config :uniris_core, UnirisCore.Bootstrap.NetworkInit,
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

config :uniris_core, UnirisCore.Interpreter.TransactionLoader, enabled: false

config :uniris_core, UnirisCore.P2P.BootstrapingSeeds, enabled: false
