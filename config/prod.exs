import Config

# Do not print debug messages in production
config :logger,
  level: System.get_env("ARCHETHIC_LOGGER_LEVEL", "info") |> String.to_atom(),
  handle_sasl_reports: true

config :archethic, :mut_dir, System.get_env("ARCHETHIC_MUT_DIR", "data")
config :archethic, :root_mut_dir, System.get_env("ARCHETHIC_ROOT_MUT_DIR", "~/aebot")

config :archethic, Archethic.Bootstrap,
  reward_address: System.get_env("ARCHETHIC_REWARD_ADDRESS", "") |> Base.decode16!(case: :mixed)

config :archethic, Archethic.Bootstrap.NetworkInit,
  genesis_pools:
    [
      %{
        address:
          Base.decode16!("00001847ce435fed8e0b280f9be54415b32488cb5057d623ead786737033d86cc6aa",
            case: :mixed
          ),
        amount: 382_000_000 * 100_000_000
      },
      %{
        address:
          Base.decode16!("00000ba09619268f8c821ee612408c383440ed9c6e2b7ffa96baf75cb02748406a8f",
            case: :mixed
          ),
        amount: 236_000_000 * 100_000_000
      },
      %{
        address:
          Base.decode16!("0000782de47562bb18ae3f19a26744996fc43b01b5ef0d66243eb5ea78dcc120191d",
            case: :mixed
          ),
        amount: 145_000_000 * 100_000_000
      },
      %{
        address:
          Base.decode16!("0000df4a467af8d5ff755c00b08a2f338cacffd54f3dfd1b95107b2538c92ab1db56",
            case: :mixed
          ),
        amount: 90_000_000 * 100_000_000
      },
      %{
        address:
          Base.decode16!("00008b0966702f4e1b99e44b7f3bc34a36dfbe41b54925454eada7c51358e516c4da",
            case: :mixed
          ),
        amount: 55_700_000 * 100_000_000
      },
      %{
        address:
          Base.decode16!("00000690b958706f2f5f54a3c3487e9bb49009e9cf00a3e1ec547deadca0790d2363",
            case: :mixed
          ),
        amount: 34_400_000 * 100_000_000
      },
      %{
        address:
          Base.decode16!("00002b339e4cfcd9883303a57192bec6e78c064cfe8bf879ec185b7a23686d4d7da9",
            case: :mixed
          ),
        amount: 21_300_000 * 100_000_000
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
    System.get_env("ARCHETHIC_BOOTSTRAP_OUT_OF_SYNC_THRESHOLD", "54000") |> String.to_integer()

config :archethic, Archethic.BeaconChain.SlotTimer,
  # Every 10 minutes
  interval: System.get_env("ARCHETHIC_BEACON_CHAIN_SLOT_TIMER_INTERVAL", "0 */10 * * * * *")

config :archethic, Archethic.BeaconChain.SummaryTimer,
  # Every day at midnight
  interval: System.get_env("ARCHETHIC_BEACON_CHAIN_SUMMARY_TIMER_INTERVAL", "0 0 0 * * * *")

config :archethic, Archethic.Crypto,
  root_ca_public_keys: [
    tpm:
      System.get_env(
        "ARCHETHIC_CRYPTO_ROOT_CA_TPM_PUBKEY",
        "3059301306072a8648ce3d020106082a8648ce3d03010703420004f0fe701a03ce375a6e57adbe0255808812036571c1424db2779c77e8b4a9ba80a15b118e8e7465ee2e94094e59c4b3f7177e99063af1b19bfcc4d7e1ac3f89dd"
      )
      |> Base.decode16!(case: :mixed)
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
    System.get_env("ARCHETHIC_NODE_ALLOWED_KEY_ORIGINS", "tpm")
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
  # Availability application date 10 minutes after self repair
  availability_application: 900

config :archethic, Archethic.P2P.Listener,
  port: System.get_env("ARCHETHIC_P2P_PORT", "30002") |> String.to_integer()

config :archethic, Archethic.P2P.BootstrappingSeeds,
  backup_file: System.get_env("ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS_FILE", "p2p/seeds"),
  # TODO: define the default list of P2P seeds once the network will be more open to new miners
  genesis_seeds: System.get_env("ARCHETHIC_P2P_BOOTSTRAPPING_SEEDS")

config :archethic, Archethic.Utils.DetectNodeResponsiveness, timeout: 10_000

config :archethic, ArchethicWeb.FaucetController,
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
    sni_fun: &ArchethicWeb.Domain.sni/1,
    keyfile: System.get_env("ARCHETHIC_WEB_SSL_KEYFILE", "priv/cert/selfsigned_key.pem"),
    certfile: System.get_env("ARCHETHIC_WEB_SSL_CERTFILE", "priv/cert/selfsigned.pem")
  ]
