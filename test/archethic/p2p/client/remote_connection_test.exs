defmodule ArchEthic.P2P.Client.RemoteConnectionTest do
  use ArchEthicCase

  alias ArchEthic.P2P.Client.RemoteConnection

  import Mox

  test "start_link/1 should open a socket and a connection worker" do
    MockTransport
    |> expect(:connect, fn _, _, _ -> {:ok, make_ref()} end)
    |> expect(:read_from_socket, fn _, _, _ ->
      public_key = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      {:ok, <<0::32, 0::8, public_key::binary, 24::8>>}
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
