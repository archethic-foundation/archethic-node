use Mix.Config

# config :logger, handle_sasl_reports: true

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Networking module configuration:
# ip_provider(module) options: Uniris.Networking.IPLookup.Static, Uniris.Networking.IPLookup.Ipify, Uniris.Networking.Nat 
# hostname(string) - (for Static) provides a constant IP address for Static (ex. "127.0.0.1")
# port(pos_int) - (for Static) provides a P2P port number (ex. 3002)
#
config :uniris, Uniris.Networking, 
  # ip_provider: Uniris.Networking.IPLookup.Static,
  # hostname: "127.0.0.1",
  port: 5454
  
config :uniris, Uniris.BeaconChain.SlotTimer,
  interval: "0 * * * * * *",
  # Trigger it 5 seconds before
  trigger_offset: 5

config :uniris, Uniris.Bootstrap, ip_lookup_provider: Uniris.Bootstrap.IPLookup.EnvImpl
config :uniris, Uniris.Bootstrap.Sync, out_of_sync_date_threshold: 60

config :uniris, Uniris.P2P.BootstrappingSeeds,
  # First node crypto seed is "node1"
  seeds:
    System.get_env(
      "UNIRIS_P2P_SEEDS",
      "127.0.0.1:3002:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"
    )

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

config :uniris, Uniris.Crypto.Keystore, impl: Uniris.Crypto.SoftwareKeystore

config :uniris, Uniris.Crypto.SoftwareKeystore,
  seed: System.get_env("UNIRIS_CRYPTO_SEED", "node1")

config :uniris, Uniris.DB, impl: Uniris.DB.KeyValueImpl

config :uniris, Uniris.DB.KeyValueImpl,
  root_dir: "priv/storage/#{System.get_env("UNIRIS_CRYPTO_SEED", "node1")}"

config :uniris, Uniris.Governance.Pools,
  initial_members: [
    technical_council: [{"00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8", 1}],
    ethical_council: ["00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"],
    foundation: ["00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"],
    uniris: ["00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8"]
  ]

config :uniris, Uniris.SelfRepair.Scheduler, interval: "0 * * * * * *"

config :uniris, Uniris.SelfRepair.Sync,
  last_sync_file: "priv/p2p/last_sync_#{System.get_env("UNIRIS_CRYPTO_SEED")}",
  network_startup_date: %DateTime{
    year: DateTime.utc_now().year,
    month: DateTime.utc_now().month,
    day: DateTime.utc_now().day,
    hour: DateTime.add(DateTime.utc_now(), -3600).hour,
    minute: 0,
    second: 0,
    microsecond: {0, 0},
    utc_offset: 0,
    std_offset: 0,
    time_zone: "Etc/UTC",
    zone_abbr: "UTC"
  }

config :uniris, Uniris.SharedSecrets.NodeRenewalScheduler,
  interval: "0 * * * * * *",
  # Trigger it 20 seconds before
  trigger_offset: 20

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :uniris, UnirisWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    node: [
      "node_modules/webpack/bin/webpack.js",
      "--mode",
      "development",
      "--watch-stdin",
      cd: Path.expand("../assets", __DIR__)
    ]
  ]
