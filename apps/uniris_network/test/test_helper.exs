ExUnit.start()

Mox.defmock(MockRequest, for: UnirisNetwork.P2P.Request.Impl)

Mox.defmock(MockClient, for: UnirisNetwork.P2P.Client.Impl)

Application.put_env(:uniris_network, :request_handler, MockRequest)

Application.put_env(:uniris_network, :client, MockClient)
