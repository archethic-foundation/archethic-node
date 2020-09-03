Mix.Tasks.CleanPrivDir.run([])

ExUnit.start(
  exclude: [:time_based, :infrastructure],
  timeout: :infinity,
  max_failures: 1
)

Mox.defmock(MockNodeClient, for: Uniris.P2P.ClientImpl)
Mox.defmock(MockCrypto, for: Uniris.Crypto.KeystoreImpl)
Mox.defmock(MockStorage, for: Uniris.Storage.BackendImpl)
Mox.defmock(MockTestnet, for: Uniris.Governance.Testnet.Impl)
Mox.defmock(MockGeoIP, for: Uniris.P2P.GeoPatch.GeoIPImpl)
