ExUnit.start()

Mox.defmock(MockElection, for: UnirisElection.Impl)
Mox.defmock(MockNetwork, for: UnirisNetwork.Impl)
Mox.defmock(MockP2P, for: UnirisNetwork.P2P.ClientImpl)
Mox.defmock(MockChain, for: UnirisChain.Impl)
Mox.defmock(MockValidation, for: UnirisValidation.Impl)
