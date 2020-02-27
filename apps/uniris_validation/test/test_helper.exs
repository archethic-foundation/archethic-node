ExUnit.start()

Mox.defmock(MockElection, for: UnirisElection.Impl)
Mox.defmock(MockNetwork, for: UnirisNetwork.Impl)
Mox.defmock(MockChain, for: UnirisChain.Impl)

Application.put_env(:uniris_network, :impl, MockNetwork)
Application.put_env(:uniris_election, :impl, MockElection)
Application.put_env(:uniris_chain, :impl, MockChain)
