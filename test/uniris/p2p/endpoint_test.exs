defmodule Uniris.P2P.EndpointTest do
  use UnirisCase

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  alias Uniris.P2P.Endpoint

  setup do
    me = self()

    MockTransport
    |> expect(:listen, fn _, _port -> {:ok, me} end)
    |> stub(:accept, fn _socket ->
      receive do
      end
    end)

    :ok
  end

  test "start_link/1 should setup a P2P endpoint" do
    assert {:ok, pid} = Endpoint.start_link(port: 13_030, transport: MockTransport)

    assert %{port: 13_030, listen_socket: _, transport: MockTransport, listener_sup: listener_sup} =
             :sys.get_state(pid)

    Process.sleep(500)

    assert Process.alive?(listener_sup)
  end
end
