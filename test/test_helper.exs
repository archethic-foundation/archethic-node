Mix.Tasks.CleanPrivDir.run([])

ExUnit.start(
  exclude: [:infrastructure, :CI],
  timeout: :infinity,
  max_failures: 1
)

Mox.defmock(MockClient, for: Uniris.P2P.ClientImpl)
Mox.defmock(MockTransport, for: Uniris.P2P.TransportImpl)
Mox.defmock(MockCrypto, for: Uniris.Crypto.KeystoreImpl)
Mox.defmock(MockDB, for: Uniris.DBImpl)
Mox.defmock(MockGeoIP, for: Uniris.P2P.GeoPatch.GeoIPImpl)
