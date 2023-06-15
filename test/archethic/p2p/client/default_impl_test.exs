defmodule Archethic.P2P.Client.DefaultImplTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P.Client.ConnectionSupervisor
  alias Archethic.P2P.Client.DefaultImpl

  describe "new_connection/4" do
    test "should not cancel connection if already connected even if infos are updated" do
      ip = {127, 0, 0, 1}
      port = 3002
      transport = :tcp
      node_public_key = Crypto.first_node_public_key()
      {:ok, pid} = DefaultImpl.new_connection(ip, port, transport, node_public_key)

      # get_state to wait connection process finished
      :sys.get_state(pid)
      ConnectionSupervisor.set_node_connected(node_public_key)

      assert {:ok, ^pid} = DefaultImpl.new_connection(ip, 3003, transport, node_public_key)
    end

    test "should cancel connection and create new one if node not connected and infos are updated" do
      ip = {127, 0, 0, 1}
      port = 3002
      transport = :tcp
      node_public_key = Crypto.first_node_public_key()
      {:ok, pid1} = DefaultImpl.new_connection(ip, port, transport, node_public_key)

      # get_state to wait connection process finished
      :sys.get_state(pid1)
      ConnectionSupervisor.set_node_disconnected(node_public_key)

      {:ok, pid2} = DefaultImpl.new_connection(ip, 3003, transport, node_public_key)

      assert pid1 != pid2
    end
  end
end
