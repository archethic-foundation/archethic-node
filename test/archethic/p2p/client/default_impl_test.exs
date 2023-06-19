defmodule Archethic.P2P.Client.DefaultImplTest do
  use ArchethicCase

  alias Archethic.Crypto

  alias Archethic.P2P.Client.DefaultImpl

  @table_name :connection_status

  describe "new_connection/5" do
    test "should not cancel connection if already connected even if infos are updated" do
      ip = {127, 0, 0, 1}
      port = 3002
      transport = :tcp
      node_public_key = Crypto.first_node_public_key()
      {:ok, pid} = DefaultImpl.new_connection(ip, port, transport, node_public_key, nil)

      # get_state to wait connection process finished
      :sys.get_state(pid)
      :ets.insert(@table_name, {node_public_key, true})

      assert {:ok, ^pid} = DefaultImpl.new_connection(ip, 3003, transport, node_public_key, nil)
    end

    test "should cancel connection and create new one if node not connected and infos are updated" do
      ip = {127, 0, 0, 1}
      port = 3002
      transport = :tcp
      node_public_key = Crypto.first_node_public_key()
      {:ok, pid1} = DefaultImpl.new_connection(ip, port, transport, node_public_key, nil)

      # get_state to wait connection process finished
      :sys.get_state(pid1)
      :ets.insert(@table_name, {node_public_key, false})

      {:ok, pid2} = DefaultImpl.new_connection(ip, 3003, transport, node_public_key, nil)

      assert pid1 != pid2
    end
  end
end
