import Mix.Config

Application.put_env(:uniris_network, :impl, MockNetwork)
Application.put_env(:uniris_election, :impl, MockElection)
Application.put_env(:uniris_chain, :impl, MockChain)
