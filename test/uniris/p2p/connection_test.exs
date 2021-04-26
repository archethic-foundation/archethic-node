defmodule Uniris.P2P.ConnectionTest do
  use UnirisCase

  alias Uniris.P2P.Connection

  alias Uniris.P2P.Message
  alias Uniris.P2P.Message.Balance
  alias Uniris.P2P.Message.GetBalance

  import Mox

  describe "send_message/2" do
    test "should send a locally if the no socket is provided" do
    end

    test "should send data remotly and get response" do
      {:ok, pid} =
        Connection.start_link(socket: make_ref(), transport: MockTransport, initiator?: true)

      address = <<0::8, :crypto.strong_rand_bytes(32)::binary>>

      MockTransport
      |> stub(:read_from_socket, fn _, _, _ ->
        {:ok, <<0::32, Message.encode(%Balance{uco: 10.0})::binary>>}
      end)
      |> expect(:send_message, fn _, _ ->
        send(pid, {:data, <<0::32, Message.encode(%Balance{uco: 10.0})::binary>>})
        :ok
      end)

      assert {:ok, %Balance{uco: 10.0}} =
               Connection.send_message(pid, %GetBalance{
                 address: address
               })
    end
  end
end
