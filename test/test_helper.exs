File.rm_rf!(Archethic.Utils.mut_dir())

ExUnit.start(
  exclude: [:infrastructure, :CI, :CD, :oracle_provider, :benchmark, :ratelimit],
  timeout: :infinity,
  max_failures: 1,
  capture_log: true
)

Mox.defmock(MockClient, for: Archethic.P2P.Client)

# Mox.defmock(MockCrypto,
#   for: [
#     Archethic.Crypto.NodeKeystore,
#     Archethic.Crypto.NodeKeystore.Origin,
#     Archethic.Crypto.SharedSecretsKeystore
#   ]
# )

Mox.defmock(MockCrypto.NodeKeystore, for: Archethic.Crypto.NodeKeystore)
Mox.defmock(MockCrypto.NodeKeystore.Origin, for: Archethic.Crypto.NodeKeystore.Origin)
Mox.defmock(MockCrypto.SharedSecretsKeystore, for: Archethic.Crypto.SharedSecretsKeystore)

Mox.defmock(MockDB, for: Archethic.DB)
Mox.defmock(MockGeoIP, for: Archethic.P2P.GeoPatch.GeoIP)

Mox.defmock(MockUCOPriceProvider1, for: Archethic.OracleChain.Services.UCOPrice.Providers.Impl)
Mox.defmock(MockUCOPriceProvider2, for: Archethic.OracleChain.Services.UCOPrice.Providers.Impl)
Mox.defmock(MockUCOPriceProvider3, for: Archethic.OracleChain.Services.UCOPrice.Providers.Impl)

Mox.defmock(MockMetricsCollector, for: Archethic.Metrics.Collector)

# -----Start-of-Networking-Mocks-----

Mox.defmock(MockStatic, for: Archethic.Networking.IPLookup.Impl)
Mox.defmock(MockIPLookup, for: Archethic.Networking.IPLookup.Impl)
Mox.defmock(MockRemoteDiscovery, for: Archethic.Networking.IPLookup.Impl)
Mox.defmock(MockNATDiscovery, for: Archethic.Networking.IPLookup.Impl)

# -----End-of-Networking-Mocks ------
