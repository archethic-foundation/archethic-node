defmodule Archethic.DB.EmbeddedTest do
  use ArchethicCase, async: false

  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.Encoding
  alias Archethic.DB.EmbeddedImpl.ChainIndex
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionFactory

  setup do
    EmbeddedImpl.Supervisor.start_link()

    db_path = EmbeddedImpl.db_path()

    on_exit(fn ->
      File.rm_rf!(Application.app_dir(:archethic, "data_test"))
    end)

    %{db_path: db_path}
  end

  describe "write_transaction_chain/1" do
    test "should persist a transaction chain in the dedicated file", %{db_path: db_path} do
      tx = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx])

      genesis_address = Transaction.previous_address(tx)

      filename = ChainWriter.chain_path(db_path, genesis_address)
      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx)
      filesize = byte_size(contents)

      assert {:ok, %{size: ^filesize, offset: 0, genesis_address: ^genesis_address}} =
               ChainIndex.get_tx_entry(tx.address, db_path)
    end

    test "should append transaction to an existing chain", %{db_path: db_path} do
      tx1 = TransactionFactory.create_valid_transaction([], index: 0)
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      genesis_address = Transaction.previous_address(tx1)

      tx2 = TransactionFactory.create_valid_transaction([], index: 1)
      :ok = EmbeddedImpl.write_transaction_chain([tx1, tx2])

      filename = ChainWriter.chain_path(db_path, genesis_address)
      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx1) <> Encoding.encode(tx2)

      size_tx1 = Encoding.encode(tx1) |> byte_size()
      size_tx2 = Encoding.encode(tx2) |> byte_size()

      assert {:ok, %{size: ^size_tx1, offset: 0, genesis_address: ^genesis_address}} =
               ChainIndex.get_tx_entry(tx1.address, db_path)

      assert {:ok,
              %{
                size: ^size_tx2,
                offset: ^size_tx1,
                genesis_address: ^genesis_address
              }} = ChainIndex.get_tx_entry(tx2.address, db_path)
    end
  end

  describe "write_transaction/1" do
    test "should write single transaction to non existing chain", %{db_path: db_path} do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction(tx1)

      genesis_address = Transaction.previous_address(tx1)
      filename = ChainWriter.chain_path(db_path, genesis_address)

      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx1)
      size_tx1 = Encoding.encode(tx1) |> byte_size()

      assert {:ok, %{size: ^size_tx1, offset: 0, genesis_address: ^genesis_address}} =
               ChainIndex.get_tx_entry(tx1.address, db_path)
    end

    test "should write single transaction and append to an existing chain", %{db_path: db_path} do
      tx1 = TransactionFactory.create_valid_transaction([], index: 0)
      :ok = EmbeddedImpl.write_transaction(tx1)

      tx2 = TransactionFactory.create_valid_transaction([], index: 1)
      :ok = EmbeddedImpl.write_transaction(tx2)

      genesis_address = Transaction.previous_address(tx1)
      filename = ChainWriter.chain_path(db_path, genesis_address)

      assert File.exists?(filename)

      contents = File.read!(filename)

      assert contents == Encoding.encode(tx1) <> Encoding.encode(tx2)

      size_tx1 = Encoding.encode(tx1) |> byte_size
      size_tx2 = Encoding.encode(tx2) |> byte_size

      assert {:ok,
              %{
                size: ^size_tx2,
                offset: ^size_tx1,
                genesis_address: ^genesis_address
              }} = ChainIndex.get_tx_entry(tx2.address, db_path)
    end
  end

  describe "transaction_exists?/1" do
    test "should return true when the transaction is present" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert EmbeddedImpl.transaction_exists?(tx1.address)
    end

    test "should return false when the transaction is present" do
      assert !EmbeddedImpl.transaction_exists?(:crypto.strong_rand_bytes(32))
    end
  end

  describe "get_transaction/2" do
    test "should an error when the transaction does not exists" do
      assert {:error, :transaction_not_exists} =
               EmbeddedImpl.get_transaction(:crypto.strong_rand_bytes(32))
    end

    test "should retrieve a transaction" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert {:ok, ^tx1} = EmbeddedImpl.get_transaction(tx1.address)
    end

    test "should filter with the given fields" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert {:ok, %Transaction{type: :transfer, address: nil}} =
               EmbeddedImpl.get_transaction(tx1.address, [:type])
    end

    test "should filter with nested fields" do
      tx1 = TransactionFactory.create_valid_transaction()
      :ok = EmbeddedImpl.write_transaction_chain([tx1])

      assert {:ok,
              %Transaction{
                validation_stamp: %ValidationStamp{
                  timestamp: %DateTime{},
                  ledger_operations: %LedgerOperations{fee: fee}
                }
              }} =
               EmbeddedImpl.get_transaction(tx1.address,
                 validation_stamp: [:timestamp, ledger_operations: :fee]
               )

      assert fee != 0.0
    end
  end

  describe "get_transaction_chain/2" do
    test "should return an empty list when the transaction chain is not found" do
      assert {[], false, ""} = EmbeddedImpl.get_transaction_chain(:crypto.strong_rand_bytes(32))
    end

    test "should return the list of all the transactions related to transaction's address chain" do
      tx1 = TransactionFactory.create_valid_transaction([], index: 0)

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1,
          timestamp: DateTime.add(DateTime.utc_now(), 100)
        )

      :ok = EmbeddedImpl.write_transaction_chain([tx1, tx2])

      assert {[^tx1, ^tx2], false, nil} = EmbeddedImpl.get_transaction_chain(tx2.address)
    end

    test "should return a page and its paging state" do
      transactions =
        Enum.map(1..20, fn i ->
          TransactionFactory.create_valid_transaction([],
            index: i,
            timestamp: DateTime.utc_now() |> DateTime.add(i * 60)
          )
        end)

      EmbeddedImpl.write_transaction_chain(transactions)

      {page, true, paging_state} =
        EmbeddedImpl.get_transaction_chain(List.last(transactions).address)

      assert length(page) == 10
      assert page == Enum.take(transactions, 10)
      assert paging_state == List.last(page).address

      {page2, false, nil} =
        EmbeddedImpl.get_transaction_chain(List.last(transactions).address, [],
          paging_state: paging_state
        )

      assert length(page2) == 10
      assert page2 == Enum.slice(transactions, 10, 10)
    end
  end

  describe "chain_size/1" do
    test "should return 0 when there are not transactions" do
      assert 0 == EmbeddedImpl.chain_size(:crypto.strong_rand_bytes(32))
    end

    test "should return the number of transaction in a chain" do
      transactions =
        Enum.map(1..20, fn i ->
          TransactionFactory.create_valid_transaction([],
            index: i,
            timestamp: DateTime.utc_now() |> DateTime.add(i * 60)
          )
        end)

      EmbeddedImpl.write_transaction_chain(transactions)

      Enum.each(1..20, fn i ->
        assert 20 == EmbeddedImpl.chain_size(Enum.at(transactions, i - 1).address)
      end)
    end
  end

  describe "list_transactions_by_type/2" do
    test "should return the transactions for a given type" do
      tx_node =
        TransactionFactory.create_valid_transaction([],
          type: :node,
          seed: "seed1"
        )

      tx_transfer =
        TransactionFactory.create_valid_transaction([],
          type: :transfer,
          seed: "seed2"
        )

      EmbeddedImpl.write_transaction(tx_node)
      EmbeddedImpl.write_transaction(tx_transfer)

      assert [^tx_node] = EmbeddedImpl.list_transactions_by_type(:node) |> Enum.to_list()
      assert [^tx_transfer] = EmbeddedImpl.list_transactions_by_type(:transfer) |> Enum.to_list()
    end
  end

  describe "count_transactions_by_type/1" do
    test "should return 0 when there are no transactions for a given type" do
      assert 0 == EmbeddedImpl.count_transactions_by_type(:transfer)
    end

    test "should return the nb of transactions for a given type" do
      tx_node1 =
        TransactionFactory.create_valid_transaction([],
          type: :node,
          seed: "seed1"
        )

      tx_node2 =
        TransactionFactory.create_valid_transaction([],
          type: :node,
          seed: "seed2"
        )

      EmbeddedImpl.write_transaction(tx_node1)
      EmbeddedImpl.write_transaction(tx_node2)

      assert 2 == EmbeddedImpl.count_transactions_by_type(:node)
    end
  end

  describe "get_last_chain_address/1" do
    test "should get the last address of chain" do
      tx1 =
        TransactionFactory.create_valid_transaction([],
          index: 0,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1,
          timestamp: ~U[2020-04-02 10:13:00Z]
        )

      tx3 =
        TransactionFactory.create_valid_transaction([],
          index: 2,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      EmbeddedImpl.write_transaction_chain([tx1, tx2, tx3])

      assert tx3.address == EmbeddedImpl.get_last_chain_address(tx1.address)
      assert tx3.address == EmbeddedImpl.get_last_chain_address(tx2.address)
      assert tx3.address == EmbeddedImpl.get_last_chain_address(tx3.address)
      assert tx3.address == EmbeddedImpl.get_last_chain_address(Transaction.previous_address(tx1))
    end
  end

  describe "get_last_chain_address/2" do
    test "should return the same given address if not previous chain" do
      address = :crypto.strong_rand_bytes(32)
      assert ^address = EmbeddedImpl.get_last_chain_address(address)
    end

    test "should get the last address of chain for the exact time of last address timestamp" do
      tx1 =
        TransactionFactory.create_valid_transaction([],
          index: 0,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1,
          timestamp: ~U[2020-04-02 10:13:00Z]
        )

      tx3 =
        TransactionFactory.create_valid_transaction([],
          index: 2,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      EmbeddedImpl.write_transaction_chain([tx1, tx2, tx3])

      assert tx3.address ==
               EmbeddedImpl.get_last_chain_address(tx3.address, tx3.validation_stamp.timestamp)

      assert tx2.address ==
               EmbeddedImpl.get_last_chain_address(tx2.address, tx2.validation_stamp.timestamp)

      assert tx1.address ==
               EmbeddedImpl.get_last_chain_address(tx1.address, tx1.validation_stamp.timestamp)

      assert tx1.address ==
               EmbeddedImpl.get_last_chain_address(
                 Transaction.previous_address(tx1),
                 tx1.validation_stamp.timestamp
               )
    end

    test "should get the last address of a chain before given date" do
      tx1 =
        TransactionFactory.create_valid_transaction([],
          index: 0,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1,
          timestamp: ~U[2020-04-02 10:13:00Z]
        )

      tx3 =
        TransactionFactory.create_valid_transaction([],
          index: 2,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      EmbeddedImpl.write_transaction_chain([tx1, tx2, tx3])

      assert tx3.address ==
               EmbeddedImpl.get_last_chain_address(tx2.address, tx3.validation_stamp.timestamp)

      assert tx3.address ==
               EmbeddedImpl.get_last_chain_address(tx1.address, tx3.validation_stamp.timestamp)

      assert tx2.address ==
               EmbeddedImpl.get_last_chain_address(
                 tx1.address,
                 DateTime.add(tx2.validation_stamp.timestamp, 100)
               )

      assert tx2.address ==
               EmbeddedImpl.get_last_chain_address(tx1.address, tx2.validation_stamp.timestamp)

      assert tx1.address ==
               EmbeddedImpl.get_last_chain_address(
                 tx1.address,
                 DateTime.add(tx1.validation_stamp.timestamp, 100)
               )
    end
  end

  describe "get_first_chain_address" do
    test "should return the same given address if not previous chain" do
      address = :crypto.strong_rand_bytes(32)
      assert ^address = EmbeddedImpl.get_first_chain_address(address)
    end

    test "should return the first address of a chain" do
      tx1 =
        TransactionFactory.create_valid_transaction([],
          index: 0,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1,
          timestamp: ~U[2020-04-02 10:13:00Z]
        )

      tx3 =
        TransactionFactory.create_valid_transaction([],
          index: 2,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      EmbeddedImpl.write_transaction_chain([tx1, tx2, tx3])

      genesis_address = Transaction.previous_address(tx1)

      assert ^genesis_address = EmbeddedImpl.get_first_chain_address(tx3.address)
      assert ^genesis_address = EmbeddedImpl.get_first_chain_address(tx2.address)
      assert ^genesis_address = EmbeddedImpl.get_first_chain_address(tx1.address)
    end
  end

  describe "get_first_public_key" do
    test "should return the same given public key if not previous chain" do
      public_key = :crypto.strong_rand_bytes(32)
      assert ^public_key = EmbeddedImpl.get_first_public_key(public_key)
    end

    test "should return the public key of a chain" do
      tx1 =
        TransactionFactory.create_valid_transaction([],
          index: 0,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1,
          timestamp: ~U[2020-04-02 10:13:00Z]
        )

      tx3 =
        TransactionFactory.create_valid_transaction([],
          index: 2,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      EmbeddedImpl.write_transaction_chain([tx1, tx2, tx3])

      assert tx1.previous_public_key == EmbeddedImpl.get_first_public_key(tx3.previous_public_key)
      assert tx1.previous_public_key == EmbeddedImpl.get_first_public_key(tx2.previous_public_key)
      assert tx1.previous_public_key == EmbeddedImpl.get_first_public_key(tx1.previous_public_key)
    end
  end

  describe "list_transactions" do
    test "should stream all the transactions" do
      tx1 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed1",
          type: :node,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx2 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed2",
          type: :transfer,
          timestamp: ~U[2020-04-02 10:13:00Z]
        )

      tx3 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed3",
          type: :oracle,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      EmbeddedImpl.write_transaction(tx1)
      EmbeddedImpl.write_transaction(tx2)
      EmbeddedImpl.write_transaction(tx3)

      types = EmbeddedImpl.list_transactions([:type]) |> Enum.map(& &1.type)
      assert Enum.all?(types, &(&1 in [:node, :transfer, :oracle]))
    end
  end

  describe "list_last_transaction_addresses" do
    test "should return all the last transaction addresses" do
      tx1_1 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed1",
          type: :node,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx1_2 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed1",
          index: 1,
          type: :node,
          timestamp: ~U[2020-04-30 10:13:00Z]
        )

      tx2_1 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed2",
          type: :transfer,
          timestamp: ~U[2020-04-02 10:13:00Z]
        )

      tx2_2 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed2",
          index: 1,
          type: :transfer,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      tx3_1 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed3",
          type: :oracle,
          timestamp: ~U[2020-04-10 10:13:00Z]
        )

      tx3_2 =
        TransactionFactory.create_valid_transaction([],
          seed: "seed3",
          type: :oracle,
          index: 1,
          timestamp: ~U[2020-04-11 10:13:00Z]
        )

      EmbeddedImpl.write_transaction_chain([tx1_1, tx1_2])
      EmbeddedImpl.write_transaction_chain([tx2_1, tx2_2])
      EmbeddedImpl.write_transaction_chain([tx3_1, tx3_2])

      last_addresses = EmbeddedImpl.list_last_transaction_addresses()
      assert Enum.all?(last_addresses, &(&1 in [tx1_2.address, tx2_2.address, tx3_2.address]))
    end
  end

  describe "Stats info" do
    test "should get the latest tps from the stats file" do
      date = DateTime.utc_now()

      :ok = EmbeddedImpl.register_tps(date, 10.0, 10_000)
      assert 10.0 == EmbeddedImpl.get_latest_tps()

      :ok = EmbeddedImpl.register_tps(DateTime.add(date, 86_400), 5.0, 5_000)

      assert 5.0 == EmbeddedImpl.get_latest_tps()
    end

    test "should get the latest nb of transactions" do
      :ok = EmbeddedImpl.register_tps(DateTime.utc_now(), 10.0, 10_000)
      assert 10_000 = EmbeddedImpl.get_nb_transactions()

      :ok = EmbeddedImpl.register_tps(DateTime.utc_now() |> DateTime.add(86_400), 5.0, 5_000)
      assert 15_000 = EmbeddedImpl.get_nb_transactions()
    end
  end

  describe "Bootstrap info" do
    test "should get bootstrap info" do
      EmbeddedImpl.set_bootstrap_info("hello", "world")
      assert "world" == EmbeddedImpl.get_bootstrap_info("hello")
    end
  end

  describe "P2P summaries listing" do
    test "should register new P2P summary " do
      node_public_key = :crypto.strong_rand_bytes(32)
      EmbeddedImpl.register_p2p_summary(node_public_key, DateTime.utc_now(), true, 0.8)
      assert %{^node_public_key => {true, 0.8}} = EmbeddedImpl.get_last_p2p_summaries()

      node_public_key2 = :crypto.strong_rand_bytes(32)
      EmbeddedImpl.register_p2p_summary(node_public_key2, DateTime.utc_now(), true, 0.5)
      summaries = EmbeddedImpl.get_last_p2p_summaries()

      assert node_public_key in Map.keys(summaries)
      assert node_public_key2 in Map.keys(summaries)
    end

    test "should register update P2P summaries and get the latest one" do
      node_public_key = :crypto.strong_rand_bytes(32)
      EmbeddedImpl.register_p2p_summary(node_public_key, DateTime.utc_now(), true, 0.8)

      EmbeddedImpl.register_p2p_summary(
        node_public_key,
        DateTime.utc_now() |> DateTime.add(86_400),
        true,
        0.4
      )

      assert %{^node_public_key => {true, 0.4}} = EmbeddedImpl.get_last_p2p_summaries()
    end
  end

  describe "add_last_transaction_address/3" do
    test "should register a new address to a previous address" do
      tx1 =
        TransactionFactory.create_valid_transaction([],
          index: 0,
          timestamp: ~U[2020-03-30 10:13:00Z]
        )

      tx2 =
        TransactionFactory.create_valid_transaction([],
          index: 1
        )

      genesis_address = Transaction.previous_address(tx1)

      EmbeddedImpl.write_transaction(tx1)
      EmbeddedImpl.add_last_transaction_address(genesis_address, tx2.address, DateTime.utc_now())

      assert tx2.address == EmbeddedImpl.get_last_chain_address(tx1.address)
    end
  end

  @tag :benchmark
  test "load test write transaction chains" do
    Benchee.run(
      %{
        "write_chain" => fn transactions ->
          :ok = EmbeddedImpl.write_transaction_chain(transactions)
        end,
        "write_transaction_at" => fn transactions ->
          Enum.each(
            transactions,
            &EmbeddedImpl.write_transaction_at(&1, List.first(transactions).address)
          )
        end
      },
      inputs: %{
        "50" =>
          Enum.map(1..50, fn _ ->
            TransactionFactory.create_valid_transaction()
          end),
        "100" =>
          Enum.map(1..100, fn _ ->
            TransactionFactory.create_valid_transaction()
          end),
        "500" =>
          Enum.map(1..500, fn _ ->
            TransactionFactory.create_valid_transaction()
          end)
      },
      parallel: 100
    )
  end

  @tag :benchmark
  test "load test parallel transactions" do
    :ets.new(:genesis_seed, [:named_table])
    :ets.insert(:genesis_seed, {1, <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>})
    :ets.insert(:genesis_seed, {2, <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>})

    Benchee.run(
      %{
        "write_transaction_at" => fn ->
          tx = TransactionFactory.create_valid_transaction()

          [{_, genesis_address}] = :ets.lookup(:genesis_seed, :rand.uniform(2))

          EmbeddedImpl.write_transaction_at(
            tx,
            genesis_address
          )
        end
      },
      parallel: 1000
    )
  end
end
