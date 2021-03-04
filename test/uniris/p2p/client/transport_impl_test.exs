defmodule Uniris.P2P.Client.TransportImplTest do
  use UnirisCase

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Client.TransportImpl
  alias Uniris.P2P.Message
  alias Uniris.P2P.Message.GetTransaction
  alias Uniris.P2P.Message.NotFound
  alias Uniris.P2P.Node

  import Mox

  @moduletag capture_log: true

  setup do
    Application.put_env(:uniris, Uniris.P2P.Client, impl: Uniris.P2P.Client.TransportImpl)

    on_exit(fn ->
      Application.put_env(:uniris, Uniris.P2P.Client, impl: MockClient)
    end)

    :ok
  end

  describe "send_message/2" do
    test "should send the message and increase availability when succeed" do
      MockTransport
      |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)
      |> stub(:send_message, fn _, _ -> :ok end)
      |> stub(:read_from_socket, fn _, _, _, _ -> {:ok, Message.encode(%NotFound{})} end)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: Crypto.node_public_key(),
        last_public_key: Crypto.node_public_key(),
        transport: MockTransport
      }

      P2P.add_node(node)

      assert {:ok, %NotFound{}} =
               TransportImpl.send_message(node, %GetTransaction{
                 address: :crypto.strong_rand_bytes(32)
               })

      {:ok, %Node{availability_history: <<1::1, _::bitstring>>}} =
        P2P.get_node_info(Crypto.node_public_key())
    end

    test "should send the message and decrease availability when an error occurs" do
      MockTransport
      |> stub(:connect, fn _, _, _, _ -> {:ok, self()} end)
      |> stub(:send_message, fn _, _ -> {:error, :closed} end)
      |> stub(:read_from_socket, fn _, _, _, _ -> :ok end)

      node_key = :crypto.strong_rand_bytes(32)

      node = %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: node_key,
        last_public_key: node_key,
        transport: MockTransport
      }

      P2P.add_node(node)

      assert {:error, :disconnected} =
               TransportImpl.send_message(node, %GetTransaction{
                 address: :crypto.strong_rand_bytes(32)
               })

      {:ok, %Node{availability_history: <<0::1, _::bitstring>>}} = P2P.get_node_info(node_key)
    end
  end
end
