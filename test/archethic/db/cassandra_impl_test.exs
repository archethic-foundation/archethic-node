defmodule ArchEthic.DB.CassandraImplTest do
  use ArchEthicCase, async: false

  @moduletag capture_log: true

  alias ArchEthic.Crypto

  alias ArchEthic.DB.CassandraImpl, as: Cassandra
  alias ArchEthic.DB.CassandraImpl.Supervisor, as: CassandraSupervisor

  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias ArchEthic.TransactionFactory

  alias ArchEthic.Utils

  setup_all do
    {:ok, conn} = Xandra.start_link()
    Xandra.execute!(conn, "DROP KEYSPACE IF EXISTS archethic")
    start_supervised!(CassandraSupervisor)
    :ok
  end

  setup do
    Xandra.run(:xandra_conn, fn conn ->
      Xandra.execute!(conn, "TRUNCATE archethic.transactions")
      Xandra.execute!(conn, "TRUNCATE archethic.transaction_type_lookup")
      Xandra.execute!(conn, "TRUNCATE archethic.chain_lookup_by_first_address")
      Xandra.execute!(conn, "TRUNCATE archethic.chain_lookup_by_first_key")
      Xandra.execute!(conn, "TRUNCATE archethic.chain_lookup_by_last_address")
      Xandra.execute!(conn, "TRUNCATE archethic.network_stats_by_date")
    end)

    :ok
  end

  @tag infrastructure: true
  test "write_transaction/1 should persist the transaction " do
    tx = create_transaction()
    assert :ok = Cassandra.write_transaction(tx)

    prepared_tx_query =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT address, type FROM archethic.transactions WHERE chain_address = ?"
      )

    tx_address = tx.address

    assert %{"address" => ^tx_address, "type" => "transfer"} =
             Xandra.execute!(:xandra_conn, prepared_tx_query, [tx_address]) |> Enum.at(0)
  end

  @tag infrastructure: true
  test "write_transaction_chain/1 should persist the transaction chain" do
    tx1 = create_transaction(index: 0)
    Process.sleep(100)
    tx2 = create_transaction(index: 1)

    chain = [tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    chain_prepared_query =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT * FROM archethic.transactions WHERE chain_address = ?"
      )

    chain =
      Xandra.execute!(:xandra_conn, chain_prepared_query, [
        List.first(chain).address
      ])
      |> Enum.to_list()

    assert length(chain) == 2
  end

  @tag infrastructure: true
  test "list_transactions/1 should stream the entire list of transactions with the requested fields" do
    Enum.each(1..500, fn i ->
      tx = create_transaction(seed: "seed_#{i}")
      Cassandra.write_transaction(tx)
    end)

    transactions = Cassandra.list_transactions([:address, :type])
    assert 500 == Enum.count(transactions)

    assert Enum.all?(transactions, &([:address, :type] not in empty_keys(&1)))
  end

  @tag infrastructure: true
  test "get_transaction/2 should retrieve the transaction with the requested fields " do
    tx = create_transaction(inputs: [%UnspentOutput{from: "@Alice2", amount: 10, type: :UCO}])

    assert :ok = Cassandra.write_transaction(tx)

    assert {:ok, db_tx} =
             Cassandra.get_transaction(tx.address, [
               :address,
               :type,
               :cross_validation_stamps,
               validation_stamp: [:signature, ledger_operations: [:unspent_outputs]]
             ])

    assert [:address, :type] not in empty_keys(tx)
    assert tx.address == db_tx.address
    assert tx.type == db_tx.type
    assert tx.validation_stamp.signature == db_tx.validation_stamp.signature
    assert tx.cross_validation_stamps == db_tx.cross_validation_stamps
  end

  @tag infrastructure: true
  test "get_transaction_chain/2 should retrieve the transaction chain with the requested fields" do
    chain = [create_transaction(index: 1), create_transaction(index: 0)]
    assert :ok = Cassandra.write_transaction_chain(chain)
    chain = Cassandra.get_transaction_chain(List.first(chain).address, [:address, :type])
    assert Enum.all?(chain, &([:address, :type] not in empty_keys(&1)))
  end

  @tag infrastructure: true
  test "add_last_transaction_address/2 should reference a last address for a chain" do
    assert :ok = Cassandra.add_last_transaction_address("@Alice1", "@Alice2", DateTime.utc_now())
  end

  @tag infrastructure: true
  test "list_last_transaction_addresses/0 should retrieve the last transaction addresses" do
    d = DateTime.utc_now() |> Utils.truncate_datetime()
    d1 = DateTime.utc_now() |> DateTime.add(1) |> Utils.truncate_datetime()
    d2 = DateTime.utc_now() |> DateTime.add(2) |> Utils.truncate_datetime()

    Cassandra.add_last_transaction_address("@Alice1", "@Alice2", d)

    Cassandra.add_last_transaction_address(
      "@Alice1",
      "@Alice3",
      d1
    )

    Cassandra.add_last_transaction_address(
      "@Alice1",
      "@Alice4",
      d2
    )

    assert [{"@Alice1", "@Alice4", timestamp}] =
             Cassandra.list_last_transaction_addresses() |> Enum.to_list()

    assert Utils.truncate_datetime(timestamp) == d2
  end

  @tag infrastructure: true
  test "chain_size/1 should return the size of a transaction chain" do
    chain = [create_transaction(index: 1), create_transaction(index: 0)]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert 2 == Cassandra.chain_size(List.first(chain).address)

    assert 0 == Cassandra.chain_size(:crypto.strong_rand_bytes(32))
  end

  @tag infrastructure: true
  test "list_transactions_by_type/1 should return the list of transaction by the given type" do
    chain = [
      create_transaction(
        index: 1,
        type: :transfer,
        timestamp: DateTime.utc_now() |> DateTime.add(5_000)
      ),
      create_transaction(index: 0, type: :hosting, timestamp: DateTime.utc_now())
    ]

    assert :ok = Cassandra.write_transaction_chain(chain)

    assert [List.first(chain).address] ==
             Cassandra.list_transactions_by_type(:transfer) |> Enum.map(& &1.address)

    assert [List.last(chain).address] ==
             Cassandra.list_transactions_by_type(:hosting) |> Enum.map(& &1.address)

    assert [] == Cassandra.list_transactions_by_type(:node) |> Enum.map(& &1.address)
  end

  @tag infrastructure: true
  test "count_transactions_by_type/1 should return the number of transactions for a given type" do
    chain = [
      create_transaction(index: 1, type: :transfer),
      create_transaction(index: 0, type: :hosting)
    ]

    assert :ok = Cassandra.write_transaction_chain(chain)

    assert 1 == Cassandra.count_transactions_by_type(:transfer)
    assert 1 == Cassandra.count_transactions_by_type(:hosting)
    assert 0 == Cassandra.count_transactions_by_type(:node)
  end

  @tag infrastructure: true
  test "get_last_chain_address/1 should return the last transaction address of a chain" do
    tx1 = create_transaction(index: 0)
    tx2 = create_transaction(index: 1)
    tx3 = create_transaction(index: 2)

    chain = [tx3, tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert tx3.address == Cassandra.get_last_chain_address(tx3.address)
    assert tx3.address == Cassandra.get_last_chain_address(tx2.address)
    assert tx3.address == Cassandra.get_last_chain_address(tx1.address)
    assert tx3.address == Cassandra.get_last_chain_address(Crypto.hash(tx1.previous_public_key))
  end

  @tag infrastructure: true
  test "get_last_chain_address/2 should return the last transaction address of a chain before a given datetime" do
    tx1 = create_transaction(index: 0, timestamp: DateTime.utc_now())
    tx2 = create_transaction(index: 1, timestamp: DateTime.utc_now() |> DateTime.add(5_000))
    tx3 = create_transaction(index: 2, timestamp: DateTime.utc_now() |> DateTime.add(10_000))

    chain = [tx3, tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert tx3.address ==
             Cassandra.get_last_chain_address(tx3.address, tx3.validation_stamp.timestamp)

    assert tx3.address ==
             Cassandra.get_last_chain_address(tx2.address, tx3.validation_stamp.timestamp)

    assert tx2.address ==
             Cassandra.get_last_chain_address(tx2.address, tx1.validation_stamp.timestamp)

    assert tx1.address ==
             Cassandra.get_last_chain_address(
               tx1.address,
               tx1.validation_stamp.timestamp |> DateTime.add(-1)
             )
  end

  @tag infrastructure: true
  test "get_first_chain_address/1 should return the first transaction address of a chain" do
    tx1 = create_transaction(index: 0, timestamp: DateTime.utc_now())
    tx2 = create_transaction(index: 1, timestamp: DateTime.utc_now() |> DateTime.add(5_000))
    tx3 = create_transaction(index: 2, timestamp: DateTime.utc_now() |> DateTime.add(10_000))

    chain = [tx3, tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert tx1.address == Cassandra.get_first_chain_address(tx3.address)
  end

  @tag infrastructure: true
  test "get_first_public_key/1 should return the first public key from a transaction address of a chain" do
    tx1 = create_transaction(index: 0, timestamp: DateTime.utc_now())
    tx2 = create_transaction(index: 1, timestamp: DateTime.utc_now() |> DateTime.add(5_000))
    tx3 = create_transaction(index: 2, timestamp: DateTime.utc_now() |> DateTime.add(10_000))

    chain = [tx3, tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert tx1.previous_public_key == Cassandra.get_first_public_key(tx3.previous_public_key)
  end

  @tag infrastructure: true
  test "register_tps/3 should insert the tps and the nb transactions for a given date" do
    :ok = Cassandra.register_tps(DateTime.utc_now(), 10.0, 10_000)

    assert 10.0 =
             :xandra_conn
             |> Xandra.execute!("SELECT * FROM archethic.network_stats_by_date")
             |> Enum.at(0)
             |> Map.get("tps")
  end

  defp create_transaction(opts \\ []) do
    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB"
    }

    coordinator_node = %Node{
      first_public_key: Crypto.first_node_public_key(),
      last_public_key: Crypto.last_node_public_key(),
      authorized?: true,
      available?: true,
      authorization_date: DateTime.utc_now(),
      geo_patch: "AAA",
      network_patch: "AAA"
    }

    storage_nodes = [
      %Node{
        ip: {127, 0, 0, 1},
        port: 3000,
        first_public_key: "key3",
        last_public_key: "key3",
        available?: true,
        geo_patch: "BBB",
        network_patch: "BBB"
      }
    ]

    Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)

    context = %{
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      storage_nodes: storage_nodes
    }

    inputs = Keyword.get(opts, :inputs, [])
    TransactionFactory.create_valid_transaction(context, inputs, opts)
  end

  defp empty_keys(tx) do
    tx
    |> Transaction.to_map()
    |> Enum.filter(&match?({_, nil}, &1))
    |> Enum.map(fn {k, _} -> k end)
  end
end
