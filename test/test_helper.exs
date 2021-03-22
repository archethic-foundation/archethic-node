File.rm_rf!(Uniris.Utils.mut_dir())

ExUnit.start(
  exclude: [:infrastructure, :CI, :oracle_provider],
  timeout: :infinity,
  max_failures: 1
)

Mox.defmock(MockClient, for: Uniris.P2P.ClientImpl)
Mox.defmock(MockTransport, for: Uniris.P2P.TransportImpl)
Mox.defmock(MockCrypto, for: Uniris.Crypto.KeystoreImpl)
Mox.defmock(MockDB, for: Uniris.DBImpl)
Mox.defmock(MockGeoIP, for: Uniris.P2P.GeoPatch.GeoIPImpl)
Mox.defmock(MockUCOPriceProvider, for: Uniris.OracleChain.Services.UCOPrice.Providers.Impl)
