use Mix.Config

# TODO: specify the crypto implementation using hardware when developed
config :uniris_core, UnirisCore.Crypto, keystore: UnirisCore.Crypto.SoftwareKeystore

config :uniris_core, UnirisCore.Storage, backend: UnirisCore.Storage.CassandraBackend

config :uniris_core, UnirisCore.Storage.CassandraBackend, nodes: ["127.0.0.1:9042"]

config :uniris_core, UnirisCore.Bootstrap,
  ip_lookup_provider: UnirisCore.Bootstrap.IPLookup.IPFYImpl,
  # seeds_file: "priv/p2p/seeds",
  seeds: "127.0.0.1:3002:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"

config :uniris_core, UnirisCore.Bootstrap.NetworkInit,
  # TODO: provide the true addresses for the genesis UCO distribution
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

config :uniris_core, UnirisCore.BeaconSlotTimer,
  # TODO: change to 10 minute when the ready and beacon day summary implemented
  interval: 60_000,
  trigger_offset: 2_000

config :uniris_core, UnirisCore.SharedSecrets.NodeRenewal,
  # TODO: change to day when the ready
  interval: 60_000,
  trigger_offset: 10_000

config :uniris_core, UnirisCore.SelfRepair,
  # TODO: change to day when the ready
  interval: 60_000,
  # TODO: specify the real network startup date
  network_startup_date: %DateTime{
    year: DateTime.utc_now().year,
    month: DateTime.utc_now().month,
    day: DateTime.utc_now().day,
    hour: DateTime.utc_now().hour - 1,
    minute: 0,
    second: 0,
    microsecond: {0, 0},
    utc_offset: 0,
    std_offset: 0,
    time_zone: "Etc/UTC",
    zone_abbr: "UTC"
  }
