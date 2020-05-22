use Mix.Config

config :uniris_core, UnirisCore.Crypto,
  seed: System.get_env("UNIRIS_CRYPTO_SEED", :crypto.strong_rand_bytes(32)),
  keystore: UnirisCore.Crypto.SoftwareKeystore

config :uniris_core, UnirisCore.BeaconSlotTimer, slot_interval: 58_000

config :uniris_core, UnirisCore.SharedSecrets.NodeRenewal,
  interval: 60_000,
  trigger_interval: 50_000

config :uniris_core, UnirisCore.SelfRepair,
  interval: 60_000,
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

config :uniris_core, UnirisCore.Bootstrap,
  # First node crypto seed is "node1"
  seeds: "127.0.0.1:3002:00682FF302BFA84702A00D81D5F97610E02573C0487FBCD6D00A66CCBC0E0656E8",
  ip_lookup_provider: UnirisCore.Bootstrap.IPLookup.LocalImpl,
  interface: "lo"
