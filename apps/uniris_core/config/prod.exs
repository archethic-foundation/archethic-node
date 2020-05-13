use Mix.Config

config :uniris_core, UnirisCore.Bootstrap,
  ip_lookup_provider: UnirisCore.Bootstrap.IPLookup.IPFYImpl

config :uniris_core, UnirisCore.BeaconSlotTimer,
  # TODO: change to day when the ready
  slot_interval: 58_000

config :uniris_core, UnirisCore.SharedSecrets.NodeRenewal,
  # TODO: change to day when the ready
  interval: 60_000,
  trigger_interval: 50_000

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

# TODO: specify the crypto implementation using hardware when developed
config :uniris_core, UnirisCore.Crypto,
  keystore: UnirisCore.Crypto.SoftwareKeystore