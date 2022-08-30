defmodule Archethic.DB.EmbeddedImpl.ChainIndexTest do
  use ArchethicCase

  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  setup do
    db_path = Application.app_dir(:archethic, "data_test")
    File.mkdir_p!(db_path)

    :ets.new(:archethic_db_chain_writers, [:named_table, :public])
    {:ok, _} = ChainWriter.start_link(path: db_path)

    on_exit(fn ->
      File.rm_rf!(Application.app_dir(:archethic, "data_test"))
    end)

    %{db_path: db_path}
  end

  describe "start_link/1" do
    test "should start the chain index and fill transaction types", %{db_path: db_path} do
      {:ok, pid} = ChainIndex.start_link(path: db_path)

      node_tx_address1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      node_tx_address2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      oracle_address1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      ChainIndex.add_tx_type(:node, node_tx_address1, db_path)
      ChainIndex.add_tx_type(:node, node_tx_address2, db_path)
      ChainIndex.add_tx_type(:oracle, oracle_address1, db_path)

      GenServer.stop(pid)

      ChainIndex.start_link(path: db_path)
      assert 2 == ChainIndex.count_transactions_by_type(:node)
      assert 1 == ChainIndex.count_transactions_by_type(:oracle)
    end

    test "should load transactions tables", %{db_path: db_path} do
      {:ok, pid} = ChainIndex.start_link(path: db_path)
      tx_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      genesis_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      ChainIndex.add_tx(tx_address, genesis_address, 100, db_path)
      ChainIndex.set_last_chain_address(genesis_address, tx_address, DateTime.utc_now(), db_path)

      GenServer.stop(pid)

      ChainIndex.start_link(path: db_path)

      assert {:ok, %{genesis_address: ^genesis_address, size: 100}} =
               ChainIndex.get_tx_entry(tx_address, db_path)

      assert {100, 1} = ChainIndex.get_file_stats(genesis_address)

      assert {^tx_address, _} = ChainIndex.get_last_chain_address(genesis_address, db_path)

      # Remove the transaction from the cache and try to fetch from the file instead
      :ets.delete(:archethic_db_tx_index, tx_address)
      assert true == ChainIndex.transaction_exists?(tx_address, db_path)
      assert false == ChainIndex.transaction_exists?(:crypto.strong_rand_bytes(32), db_path)
    end
  end
end
