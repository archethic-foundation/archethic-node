defmodule Uniris.P2P.Endpoint.ListenerTest do
  use UnirisCase

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  alias Uniris.P2P.Endpoint.Listener

  setup do
    MockTransport
    |> expect(:listen, fn _, _port -> {:ok, make_ref()} end)

    :ok
  end

  test "start_link/1 should setup a P2P endpoint" do
    assert {:ok, pid} = Listener.start_link(port: 13_030, transport: MockTransport)
    assert %{listen_socket: _} = :sys.get_state(pid)
  end
end
