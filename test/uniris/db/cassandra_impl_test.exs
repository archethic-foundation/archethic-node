defmodule Uniris.DB.CassandraImplTest do
  use UnirisCase, async: false

  @moduletag capture_log: true

  alias Uniris.Crypto

  alias Uniris.DB.CassandraImpl, as: Cassandra

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionFactory

  setup do
    on_exit(fn ->
      {:ok, conn} = Xandra.start_link()
      Xandra.execute!(conn, "DROP KEYSPACE uniris")
    end)
  end

  @tag infrastructure: true
  test "start_link/1 should initiate create the connection pool and run the migrations" do
    {:ok, _pid} = Cassandra.start_link()
    assert {:ok, _} = Xandra.execute(:xandra_conn, "select * from uniris.transaction_chains")
  end

  @tag infrastructure: true
  test "write_transaction/1 should persist the transaction " do
    {:ok, _pid} = Cassandra.start_link()
    tx = create_transaction()
    assert :ok = Cassandra.write_transaction(tx)

    prepared_tx_query =
      Xandra.prepare!(:xandra_conn, "SELECT address FROM uniris.transactions WHERE address = ?")

    assert {:ok, %Xandra.Page{content: [_]}} =
             Xandra.execute(:xandra_conn, prepared_tx_query, [tx.address])
  end

  @tag infrastructure: true
  test "write_transaction_chain/1 should persist the transaction chain" do
    {:ok, _pid} = Cassandra.start_link()

    tx1 = create_transaction([], index: 0)
    Process.sleep(100)
    tx2 = create_transaction([], index: 1)

    chain = [tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    prepared_tx_query =
      Xandra.prepare!(:xandra_conn, "SELECT address FROM uniris.transactions WHERE address = ?")

    assert Enum.all?(chain, fn tx ->
             assert {:ok, %Xandra.Page{content: [_]}} =
                      Xandra.execute(:xandra_conn, prepared_tx_query, [tx.address])
           end)

    chain_prepared_query =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT * FROM uniris.transaction_chains WHERE chain_address = ? and fork = ?"
      )

    assert {:ok, %Xandra.Page{content: [_ | _]}} =
             Xandra.execute(:xandra_conn, chain_prepared_query, [
               List.first(chain).address,
               "main"
             ])
  end

  @tag infrastructure: true
  test "list_transactions/1 should stream the entire list of transactions with the requested fields" do
    {:ok, _pid} = Cassandra.start_link()

    Enum.each(1..500, fn i ->
      tx = create_transaction([], seed: "seed_#{i}")
      Cassandra.write_transaction(tx)
    end)

    transactions = Cassandra.list_transactions([:address, :type])
    assert 500 == Enum.count(transactions)

    assert Enum.all?(transactions, &([:address, :type] not in empty_keys(&1)))
  end

  @tag infrastructure: true
  test "get_transaction/2 should retrieve the transaction with the requested fields " do
    {:ok, _pid} = Cassandra.start_link()

    tx = create_transaction([%UnspentOutput{from: "@Alice2", amount: 10, type: :UCO}])

    assert :ok = Cassandra.write_transaction(tx)

    assert {:ok, db_tx} =
             Cassandra.get_transaction(tx.address, [
               :address,
               :type,
               validation_stamp: [:signature, ledger_operations: [:unspent_outputs]]
             ])

    assert [:address, :type] not in empty_keys(tx)
    assert tx.address == db_tx.address
    assert tx.type == db_tx.type
    assert tx.validation_stamp.signature == db_tx.validation_stamp.signature
  end

  @tag infrastructure: true
  test "get_transaction_chain/2 should retrieve the transaction chain with the requested fields" do
    {:ok, _pid} = Cassandra.start_link()
    chain = [create_transaction([], index: 1), create_transaction([], index: 0)]
    assert :ok = Cassandra.write_transaction_chain(chain)
    chain = Cassandra.get_transaction_chain(List.first(chain).address, [:address, :type])
    assert Enum.all?(chain, &([:address, :type] not in empty_keys(&1)))
  end

  @tag infrastructure: true
  test "add_last_transaction_address/2 should reference a last address for a chain" do
    {:ok, _pid} = Cassandra.start_link()
    assert :ok = Cassandra.add_last_transaction_address("@Alice1", "@Alice2")
  end

  @tag infrastructure: true
  test "list_last_transaction_addresses/0 should retrieve the last transaction addresses" do
    {:ok, _pid} = Cassandra.start_link()
    Cassandra.add_last_transaction_address("@Alice1", "@Alice2")
    Cassandra.add_last_transaction_address("@Alice1", "@Alice3")
    Cassandra.add_last_transaction_address("@Alice1", "@Alice4")
    assert [{ "@Alice1", "@Alice4"}] = Cassandra.list_last_transaction_addresses() |> Enum.to_list()
  end

  defp create_transaction(inputs \\ [], opts \\ []) do
    welcome_node = %Node{
      first_public_key: "key1",
      last_public_key: "key1",
      available?: true,
      geo_patch: "BBB",
      network_patch: "BBB"
    }

    coordinator_node = %Node{
      first_public_key: Crypto.node_public_key(0),
      last_public_key: Crypto.node_public_key(),
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

    Enum.each(storage_nodes, &P2P.add_node(&1))

    P2P.add_node(welcome_node)
    P2P.add_node(coordinator_node)

    context = %{
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      storage_nodes: storage_nodes
    }

    TransactionFactory.create_valid_transaction(context, inputs, opts)
  end

  defp empty_keys(tx) do
    tx
    |> Transaction.to_map()
    |> Enum.filter(&match?({_, nil}, &1))
    |> Enum.map(fn {k, _} -> k end)
  end
end
