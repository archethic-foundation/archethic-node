ExUnit.start()

Mox.defmock(MockElection, for: UnirisElection.Impl)
Mox.defmock(MockP2P, for: UnirisP2P.Impl)
Mox.defmock(MockChain, for: UnirisChain.Impl)
Mox.defmock(MockSharedSecrets, for: UnirisSharedSecrets.Impl)
