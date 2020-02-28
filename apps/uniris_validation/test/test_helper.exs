ExUnit.start()

Mox.defmock(MockElection, for: UnirisElection.Impl)
Mox.defmock(MockNetwork, for: UnirisNetwork.Impl)
Mox.defmock(MockChain, for: UnirisChain.Impl)

