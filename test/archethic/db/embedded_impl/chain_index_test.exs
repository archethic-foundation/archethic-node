defmodule Archethic.DB.EmbeddedImpl.ChainIndexTest do
  use ArchethicCase

  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.ChainWriter
  alias ArchethicCache.LRU

  import ArchethicCase

  setup do
    db_path = Application.app_dir(:archethic, "data_test")
    ChainWriter.setup_folders!(db_path)

    {:ok, _} = ChainWriter.start_link(path: db_path)

    on_exit(fn ->
      File.rm_rf!(Application.app_dir(:archethic, "data_test"))
    end)

    ArchethicCache.LRU.start_link(:chain_index_cache, 10_000)
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
      {:ok, _pid} = ChainIndex.start_link(path: db_path)
      LRU.start_link(:chain_index_cache, 30_000_000)
      tx_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      genesis_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      ChainIndex.add_tx(tx_address, genesis_address, 100, db_path)
      ChainIndex.set_last_chain_address(genesis_address, tx_address, DateTime.utc_now(), db_path)

      # GenServer.stop(pid)

      # ChainIndex.start_link(path: db_path)

      assert {:ok, %{genesis_address: ^genesis_address, size: 100}} =
               ChainIndex.get_tx_entry(tx_address, db_path)

      assert {100, 1} = ChainIndex.get_file_stats(genesis_address)

      assert {^tx_address, _} = ChainIndex.get_last_chain_address(genesis_address, db_path)

      # Remove the transaction from the cache and try to fetch from the file instead
      LRU.purge(:chain_index_cache)
      assert true == ChainIndex.transaction_exists?(tx_address, db_path)
      assert false == ChainIndex.transaction_exists?(:crypto.strong_rand_bytes(32), db_path)
    end
  end

  describe "set_last_chain_address/4" do
    test "should not update last transaction only if timestamp is lesser", %{db_path: db_path} do
      {:ok, _pid} = ChainIndex.start_link(path: db_path)

      tx_address_1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      tx_address_2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      genesis_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      today = DateTime.utc_now()
      yesterday = DateTime.add(today, -1, :day)

      ChainIndex.add_tx(tx_address_1, genesis_address, 100, db_path)
      ChainIndex.set_last_chain_address(genesis_address, tx_address_1, today, db_path)
      ChainIndex.set_last_chain_address(genesis_address, tx_address_2, yesterday, db_path)

      assert {^tx_address_1, _} = ChainIndex.get_last_chain_address(genesis_address, db_path)
    end

    test "should update last transaction if timestamp is greater", %{db_path: db_path} do
      {:ok, _pid} = ChainIndex.start_link(path: db_path)

      tx_address_1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      tx_address_2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
      genesis_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>

      today = DateTime.utc_now()
      tomorrow = DateTime.add(today, 1, :day)

      ChainIndex.add_tx(tx_address_1, genesis_address, 100, db_path)
      ChainIndex.set_last_chain_address(genesis_address, tx_address_1, today, db_path)
      ChainIndex.set_last_chain_address(genesis_address, tx_address_2, tomorrow, db_path)

      assert {^tx_address_2, _} = ChainIndex.get_last_chain_address(genesis_address, db_path)
    end
  end

  describe "set_last_chain_address_stored" do
    test "should write a new index containing the address", %{db_path: db_path} do
      genesis_address = random_address()
      last_address = random_address()

      assert nil == ChainIndex.get_last_chain_address_stored(genesis_address, db_path)

      ChainIndex.set_last_chain_address_stored(genesis_address, last_address, db_path)

      assert last_address == ChainIndex.get_last_chain_address_stored(genesis_address, db_path)
    end
  end
end
