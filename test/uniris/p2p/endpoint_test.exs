defmodule Uniris.P2P.EndpointTest do
  use UnirisCase

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  @tcp_options [:binary, packet: 4, active: false]

  alias Uniris.Crypto

  alias Uniris.P2P.Endpoint

  alias Uniris.P2P.Message
  alias Uniris.P2P.Message.BootstrappingNodes
  alias Uniris.P2P.Message.GetBootstrappingNodes
  alias Uniris.P2P.Node

  alias Uniris.Storage.Memory.NetworkLedger

  setup do
    port = 10_000
    {:ok, _} = Endpoint.start_link(port: port)
    {:ok, %{port: port}}
  end

  test "send message node should retrieve data", %{port: port} do
    NetworkLedger.add_node_info(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: Crypto.node_public_key(),
      last_public_key: Crypto.node_public_key(),
      authorized?: true,
      ready?: true,
      available?: true,
      geo_patch: "CCC",
      network_patch: "CCC",
      enrollment_date: DateTime.utc_now(),
      authorization_date: DateTime.utc_now(),
      ready_date: DateTime.utc_now()
    })

    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, @tcp_options)
    :ok = :gen_tcp.send(socket, Message.encode(%GetBootstrappingNodes{patch: "AAA"}))

    {:ok, data} = :gen_tcp.recv(socket, 0)
    assert %BootstrappingNodes{} = Message.decode(data)
    :gen_tcp.close(socket)
  end
end
