import Config

# Do not print debug messages in production
config :logger,
  level: System.get_env("ARCHETHIC_LOGGER_LEVEL", "info") |> String.to_atom(),
  handle_sasl_reports: true

config :archethic, :mut_dir, System.get_env("ARCHETHIC_MUT_DIR", "data")
config :archethic, :root_mut_dir, System.get_env("ARCHETHIC_ROOT_MUT_DIR", "~/aebot")

config :archethic, Archethic.Bootstrap,
  reward_address: System.get_env("ARCHETHIC_REWARD_ADDRESS", "") |> Base.decode16!(case: :mixed)

config :archethic, Archethic.TransactionChain.MemTables.PendingLedger, enabled: false
config :archethic, Archethic.TransactionChain.MemTablesLoader, enabled: false

config :archethic, Archethic.Bootstrap.NetworkInit,
  genesis_pools:
    [
      %{
        address:
          Base.decode16!("0000e0ef0c5a8242d7f743e452e3089b7acac43763a3f18c8f5dd38d22299b61ce0e",
            case: :mixed
          ),
        amount: 381_966_011 * 100_000_000
      },
      %{
        address:
          Base.decode16!("000047c827e93c4f1106906d3f43546eb09176f03dff15275759d47bf33d9b0d168a",
            case: :mixed
          ),
        amount: 236_067_977 * 100_000_000
      },
      %{
        address:
          Base.decode16!("000012023d76d65f4a20e563682522576963e36789897312cb6623fdf7914b60ecef",
            case: :mixed
          ),
        amount: 145_898_033 * 100_000_000
      },
      %{
        address:
          Base.decode16!("00004769c94199bca872ffafa7ce912f6de4dd8b2b1f4a41985cd25f3c4a190c72bb",
            case: :mixed
          ),
        amount: 90_169_943 * 100_000_000
      },
      %{
        address:
          Base.decode16!("0000dbe5d04070411325ba8254bc0ce005df30ebfdfeefadbc6659fa3d5fa3263dfd",
            case: :mixed
          ),
        amount: 55_728_090 * 100_000_000
      },
      %{
        address:
          Base.decode16!("0000bb90e7ec3051bf7be8d2bf766da8bed88afa696d282acf5ff8479ce787397e16",
            case: :mixed
          ),
        amount: 34_441_857 * 100_000_000
      },
      %{
        address:
          Base.decode16!("000050ceee9ceeb411fa027f1fb9247fe04297ff00358d87de4b7b8f2a7051df47f7",
            case: :mixed
          ),
        amount: 21_286_236 * 100_000_000
      },
      if(System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet",
        do: %{
          address:
            "00001259AE51A6E63A1E04E308C5E769E0E9D15BFFE4E7880266C8FA10C3ADD7B7A2"
            |> Base.decode16!(case: :mixed),
          amount: 1_000_000_000_000_000
        }
      )
    ]
    |> Enum.filter(& &1)

config :archethic, Archethic.Bootstrap.Sync,
  # 15 days
  out_of_sync_date_threshold:
    System.get_env("ARCHETHIC_BOOTSTRAP_OUT_OF_SYNC_THRESHOLD", "1296000") |> String.to_integer()

config :archethic, Archethic.BeaconChain.SlotTimer,
  # Every 10 minutes
  interval: System.get_env("ARCHETHIC_BEACON_CHAIN_SLOT_TIMER_INTERVAL", "0 */10 * * * * *")

config :archethic, Archethic.BeaconChain.SummaryTimer,
  # Every day at midnight
  interval: System.get_env("ARCHETHIC_BEACON_CHAIN_SUMMARY_TIMER_INTERVAL", "0 0 0 * * * *")

config :archethic, Archethic.Crypto,
  root_ca_public_keys: [
    software:
      case System.get_env("ARCHETHIC_NETWORK_TYPE") do
        "testnet" ->
          []

        _ ->
          [
            secp256r1:
              System.get_env(
                "ARCHETHIC_CRYPTO_ROOT_CA_SOFTWARE_PUBKEY",
                "04F0FE701A03CE375A6E57ADBE0255808812036571C1424DB2779C77E8B4A9BA80A15B118E8E7465EE2E94094E59C4B3F7177E99063AF1B19BFCC4D7E1AC3F89DD"
              )
              |> Base.decode16!(case: :mixed)
          ]
      end,
    tpm: [
      secp256r1:
        System.get_env(
          "ARCHETHIC_CRYPTO_ROOT_CA_TPM_PUBKEY",
          "04F0FE701A03CE375A6E57ADBE0255808812036571C1424DB2779C77E8B4A9BA80A15B118E8E7465EE2E94094E59C4B3F7177E99063AF1B19BFCC4D7E1AC3F89DD"
        )
        |> Base.decode16!(case: :mixed)
    ]
  ],
  key_certificates_dir: System.get_env("ARCHETHIC_CRYPTO_CERT_DIR", "~/aebot/key_certificates")

config :archethic,
       Archethic.Crypto.NodeKeystore.Origin.SoftwareImpl,
       node_seed: System.get_env("ARCHETHIC_CRYPTO_SEED")

config :archethic,
       Archethic.Crypto.NodeKeystore.Origin,
       (case(System.get_env("ARCHETHIC_CRYPTO_NODE_KEYSTORE_IMPL", "TPM") |> String.upcase()) do
          "TPM" ->
            Archethic.Crypto.NodeKeystore.Origin.TPMImpl

          "SOFTWARE" ->
            Archethic.Crypto.NodeKeystore.Origin.SoftwareImpl
        end)

# TODO: to remove when the implementation will be detected
config :archethic,
       Archethic.Crypto.SharedSecretsKeystore,
       Archethic.Crypto.SharedSecretsKeystore.SoftwareImpl

config :archethic, Archethic.Governance.Pools,
  # TODO: provide the true addresses of the members
  initial_members: [
    technical_council: [],
    ethical_council: [],
    foundation: [],
    uniris: []
  ]

config :archethic, Archethic.Mining.PendingTransactionValidation,
  allowed_node_key_origins:
    System.get_env("ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS", "tpm;software")
    |> String.upcase()
    |> String.split(";", trim: true)
    |> Enum.map(fn
      "TPM" ->
        :tpm

      "SOFTWARE" ->
        :software
    end)

# -----Start-of-Networking-prod-configs-----

config :archethic, Archethic.Networking,
  validate_node_ip: System.get_env("ARCHETHIC_NODE_IP_VALIDATION", "true") == "true"

config :archethic,
       Archethic.Networking.IPLookup,
       (case(System.get_env("ARCHETHIC_NETWORKING_IMPL", "NAT") |> String.upcase()) do
          "NAT" ->
            Archethic.Networking.IPLookup.NATDiscovery

          "STATIC" ->
            Archethic.Networking.IPLookup.Static

          "REMOTE" ->
            Archethic.Networking.IPLookup.RemoteDiscovery
        end)

config :archethic, Archethic.Networking.PortForwarding,
  enabled:
    (case(System.get_env("ARCHETHIC_NETWORKING_PORT_FORWARDING", "true")) do
       "true" ->
         true

       _ ->
         false
     end)

config :archethic, Archethic.Networking.IPLookup.Static,
  hostname: System.get_env("ARCHETHIC_STATIC_IP")

# -----end-of-Networking-prod-configs-----

config :archethic, Archethic.Networking.Scheduler,
  # Every 5 minutes
  interval: System.get_env("ARCHETHIC_NETWORKING_UPDATE_SCHEDULER", "0 */5 * * * * *")

config :archethic, Archethic.OracleChain.Scheduler,
  # Poll new changes every minute
  polling_interval: System.get_env("ARCHETHIC_ORACLE_CHAIN_POLLING_INTERVAL", "0 * * * * * *"),
  # Aggregate chain every day at midnight
  summary_interval: System.get_env("ARCHETHIC_ORACLE_CHAIN_SUMMARY_INTERVAL", "0 0 0 * * * *")

config :archethic, Archethic.Reward.Scheduler,
  # Every day at 02:00:00
  interval: System.get_env("ARCHETHIC_REWARD_SCHEDULER_INTERVAL", "0 0 2 * * * *")

config :archethic,
       Archethic.Crypto.SharedSecretsKeystore,
       Archethic.Crypto.SharedSecretsKeystore.SoftwareImpl

config :archethic, Archethic.SharedSecrets.NodeRenewalScheduler,
  # Every day at 23:50:00
  interval:
    System.get_env("ARCHETHIC_SHARED_SECRETS_RENEWAL_SCHEDULER_INTERVAL", "0 50 23 * * * *"),
  # Every day at midnight
  application_interval:
    System.get_env("ARCHETHIC_SHARED_SECRETS_APPLICATION_INTERVAL", "0 0 0 * * * *")

config :archethic, Archethic.SelfRepair.Scheduler,
  # Every day at 00:05:00
  # To give time for the beacon chain to produce summary
  interval: System.get_env("ARCHETHIC_SELF_REPAIR_SCHEDULER_INTRERVAL", "0 5 0 * * * *"),
  # Availability application date 15 minutes after beacon summary time
  availability_application: 900

config :archethic, Archethic.P2P.Listener,
  port: System.get_env("ARCHETHIC_P2P_PORT", "30002") |> String.to_integer()

config :archethic, Archethic.P2P.BootstrappingSeeds,
  backup_file: System.get_env("ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS_FILE", "p2p/seeds"),
  # TODO: define the default list of P2P seeds once the network will be more open to new miners
  genesis_seeds: System.get_env("ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS")

config :archethic, Archethic.Utils.DetectNodeResponsiveness, timeout: 10_000

config :archethic, ArchethicWeb.Explorer.FaucetController,
  enabled: System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet"

config :archethic, ArchethicWeb.Explorer.FaucetRateLimiter,
  enabled: System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet"

# For production, don't forget to configure the url host
# to something meaningful, Phoenix uses this information
# when generating URLs.
#
# Note we also include the path to a cache manifest
# containing the digested version of static files. This
# manifest is generated by the `mix phx.digest` task,
# which you should run after static files are built and
# before starting your production server.
config :archethic, ArchethicWeb.Endpoint,
  explorer_url:
    URI.to_string(%URI{
      scheme: "https",
      host:
        case(System.get_env("ARCHETHIC_NETWORK_TYPE") == "testnet") do
          true ->
            System.get_env("ARCHETHIC_DOMAIN_NAME", "testnet.archethic.net")

          false ->
            System.get_env("ARCHETHIC_DOMAIN_NAME", "mainnet.archethic.net")
        end,
      path: "/explorer"
    }),
  http: [:inet6, port: System.get_env("ARCHETHIC_HTTP_PORT", "40000") |> String.to_integer()],
  url: [host: nil, port: System.get_env("ARCHETHIC_HTTP_PORT", "40000") |> String.to_integer()],
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true,
  root: ".",
  version: Application.spec(:archethic, :vsn),
  check_origin: false,
  https: [
    cipher_suite: :strong,
    otp_app: :archethic,
    port: System.get_env("ARCHETHIC_HTTPS_PORT", "50000") |> String.to_integer(),
    sni_fun: &ArchethicWeb.AEWeb.Domain.sni/1,
    keyfile: System.get_env("ARCHETHIC_WEB_SSL_KEYFILE", "priv/cert/selfsigned_key.pem"),
    certfile: System.get_env("ARCHETHIC_WEB_SSL_CERTFILE", "priv/cert/selfsigned.pem")
  ]

config :archethic, :throttle,
  by_ip_high: [
    period: 1000,
    limit: System.get_env("ARCHETHIC_THROTTLE_IP_HIGH", "500") |> String.to_integer()
  ],
  by_ip_low: [
    period: 1000,
    limit: System.get_env("ARCHETHIC_THROTTLE_IP_LOW", "20") |> String.to_integer()
  ],
  by_ip_and_path: [
    period: 1000,
    limit: System.get_env("ARCHETHIC_THROTTLE_IP_AND_PATH", "20") |> String.to_integer()
  ]

if System.get_env("ARCHETHIC_OTLP_ENDPOINT") do
  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: System.fetch("ARCHETHIC_OTLP_ENDPOINT")
end
