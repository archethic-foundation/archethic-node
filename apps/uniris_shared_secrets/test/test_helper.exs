ExUnit.start()

Mox.defmock(MockP2P, for: UnirisP2P.Impl)
Mox.defmock(MockSharedSecrets, for: UnirisSharedSecrets.Impl)
