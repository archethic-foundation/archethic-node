ExUnit.start()

Mox.defmock(MockSupervisedConnection, for: UnirisNetwork.P2P.SupervisedConnection.Impl)

Application.put_env(:uniris_network, :supervised_connection_impl, MockSupervisedConnection)

