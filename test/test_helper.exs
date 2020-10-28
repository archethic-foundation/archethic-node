Mix.Tasks.CleanPrivDir.run([])

ExUnit.start(
  exclude: [:infrastructure, :CI],
  timeout: :infinity,
  max_failures: 1
)

Mox.defmock(MockTransport, for: Uniris.P2P.TransportImpl)
Mox.defmock(MockCrypto, for: Uniris.Crypto.KeystoreImpl)
Mox.defmock(MockDB, for: Uniris.DBImpl)
Mox.defmock(MockTestNet, for: Uniris.Governance.Code.TestNetImpl)
Mox.defmock(MockGeoIP, for: Uniris.P2P.GeoPatch.GeoIPImpl)
