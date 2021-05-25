defmodule Uniris.P2P.Client.RemoteConnectionTest do
  use UnirisCase

  alias Uniris.P2P.Client.RemoteConnection

  import Mox

  test "start_link/1 should open a socket and a connection worker" do
    MockTransport
    |> expect(:connect, fn _, _, _ -> {:ok, make_ref()} end)
    |> expect(:read_from_socket, fn _, _, _ ->
      {:ok, <<0::32, 0::8>>}
    end)
    |> expect(:read_from_socket, fn _, _, _ -> {:error, :closed} end)

    {:ok, pid} =
      RemoteConnection.start_link(
        ip: {127, 0, 0, 1},
        port: 3000,
        transport: MockTransport,
        node_public_key: "key1"
      )

    assert %{socket: _, connection_pid: _} = :sys.get_state(pid)

    Process.sleep(200)
  end
end
