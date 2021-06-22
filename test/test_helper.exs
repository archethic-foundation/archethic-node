File.rm_rf!(ArchEthic.Utils.mut_dir())

ExUnit.start(
  exclude: [:infrastructure, :CI, :CD, :oracle_provider],
  timeout: :infinity,
  max_failures: 1
)

Mox.defmock(MockClient, for: ArchEthic.P2P.Client)
Mox.defmock(MockTransport, for: ArchEthic.P2P.TransportImpl)

Mox.defmock(MockCrypto,
  for: [ArchEthic.Crypto.NodeKeystore, ArchEthic.Crypto.SharedSecretsKeystore]
)

Mox.defmock(MockDB, for: ArchEthic.DB)
Mox.defmock(MockGeoIP, for: ArchEthic.P2P.GeoPatch.GeoIP)
Mox.defmock(MockUCOPriceProvider, for: ArchEthic.OracleChain.Services.UCOPrice.Providers.Impl)
