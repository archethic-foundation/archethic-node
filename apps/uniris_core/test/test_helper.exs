ExUnit.start()

Mox.defmock(MockNodeClient, for: UnirisCore.P2P.NodeClientImpl)
Mox.defmock(MockCrypto, for: UnirisCore.Crypto.KeystoreImpl)
Mox.defmock(MockStorage, for: UnirisCore.Storage.BackendImpl)
