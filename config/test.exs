import Config

# Print only errors during test
config :logger, level: :error

config :uniris, :mut_dir, "data_test"

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

config :uniris, Uniris.Bootstrap, enabled: false

config :uniris, Uniris.Bootstrap.Sync, out_of_sync_date_threshold: 3

config :uniris, Uniris.Contracts.Loader, enabled: false

config :uniris, Uniris.Crypto,
  root_ca_public_keys: [
    #  From `:crypto.generate_key(:ecdh, :secp256r1, "ca_root_key")`
    software:
      <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
        194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
        186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
        70, 95, 28, 35, 233, 21, 230>>,
    tpm:
      <<4, 210, 136, 107, 189, 140, 118, 86, 124, 217, 244, 69, 111, 61, 56, 224, 56, 150, 230,
        194, 203, 81, 213, 212, 220, 19, 1, 180, 114, 44, 230, 149, 21, 125, 69, 206, 32, 173,
        186, 81, 243, 58, 13, 198, 129, 169, 33, 179, 201, 50, 49, 67, 38, 156, 38, 199, 97, 59,
        70, 95, 28, 35, 233, 21, 230>>
  ],
  software_root_ca_key: :crypto.generate_key(:ecdh, :secp256r1, "ca_root_key") |> elem(1)

config :uniris, Uniris.Crypto.NodeKeystore, impl: MockCrypto, enabled: false
config :uniris, Uniris.Crypto.NodeKeystore.SoftwareImpl, seed: "fake seed"
config :uniris, Uniris.Crypto.SharedSecretsKeystore, impl: MockCrypto, enabled: false
config :uniris, Uniris.Crypto.KeystoreCounter, enabled: false
config :uniris, Uniris.Crypto.KeystoreLoader, enabled: false

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

config :uniris, Uniris.OracleChain.MemTable, enabled: false
config :uniris, Uniris.OracleChain.MemTableLoader, enabled: false

config :uniris, Uniris.OracleChain.Scheduler,
  enabled: false,
  polling_interval: "0 0 * * * *",
  summary_interval: "0 0 0 * * *"

config :uniris, Uniris.OracleChain.Services.UCOPrice, provider: MockUCOPriceProvider

config :uniris, Uniris.Networking.IPLookup, impl: MockIPLookup
config :uniris, Uniris.Networking.PortForwarding, impl: MockPortForwarding

config :uniris, Uniris.P2P.Endpoint.Listener, enabled: false
config :uniris, Uniris.P2P.MemTableLoader, enabled: false
config :uniris, Uniris.P2P.MemTable, enabled: false
config :uniris, Uniris.P2P.Client, impl: MockClient
config :uniris, Uniris.P2P.Transport, impl: MockTransport

config :uniris, Uniris.P2P.BootstrappingSeeds, enabled: false

config :uniris, Uniris.Reward.NetworkPoolScheduler, enabled: false
config :uniris, Uniris.Reward.WithdrawScheduler, enabled: false

config :uniris, Uniris.SelfRepair.Scheduler,
  enabled: false,
  interval: 0

config :uniris, Uniris.SelfRepair.Notifier, enabled: false

config :uniris, Uniris.SelfRepair.Sync,
  network_startup_date: DateTime.utc_now(),
  last_sync_file: "p2p/last_sync_test"

config :uniris, Uniris.SharedSecrets.MemTablesLoader, enabled: false
config :uniris, Uniris.SharedSecrets.MemTables.NetworkLookup, enabled: false
config :uniris, Uniris.SharedSecrets.MemTables.OriginKeyLookup, enabled: false

config :uniris, Uniris.SharedSecrets.NodeRenewalScheduler,
  enabled: false,
  interval: "0 0 * * * * *",
  application_interval: "0 0 * * * * *"

config :uniris, Uniris.TransactionChain.MemTables.PendingLedger, enabled: false
config :uniris, Uniris.TransactionChain.MemTables.KOLedger, enabled: false
config :uniris, Uniris.TransactionChain.MemTablesLoader, enabled: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :uniris, UnirisWeb.Endpoint,
  http: [port: 4002],
  server: false
