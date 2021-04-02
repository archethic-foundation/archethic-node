defmodule Uniris.DB.CassandraImplTest do
  use UnirisCase, async: false

  @moduletag capture_log: true

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Summary

  alias Uniris.Crypto

  alias Uniris.DB.CassandraImpl, as: Cassandra

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Uniris.TransactionFactory

  alias Uniris.Utils

  setup_all do
    Code.compiler_options(ignore_module_conflict: true)

    {:ok, conn} = Xandra.start_link()
    Xandra.execute!(conn, "DROP KEYSPACE IF EXISTS uniris")
    {:ok, _pid} = Cassandra.start_link()

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)
  end

  setup do
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.transactions")
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.transaction_chains")
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.transaction_type_lookup")
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.chain_lookup_by_first_address")
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.chain_lookup_by_first_key")
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.chain_lookup_by_last_address")
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.beacon_chain_slot")
    Xandra.execute!(:xandra_conn, "TRUNCATE uniris.beacon_chain_summary")

    :ok
  end

  @tag infrastructure: true
  test "start_link/1 should initiate create the connection pool and run the migrations" do
    assert {:ok, _} = Xandra.execute(:xandra_conn, "select * from uniris.transaction_chains")
  end

  @tag infrastructure: true
  test "write_transaction/1 should persist the transaction " do
    tx = create_transaction()
    assert :ok = Cassandra.write_transaction(tx)

    prepared_tx_query =
      Xandra.prepare!(:xandra_conn, "SELECT address FROM uniris.transactions WHERE address = ?")

    assert {:ok, %Xandra.Page{content: [_]}} =
             Xandra.execute(:xandra_conn, prepared_tx_query, [tx.address])
  end

  @tag infrastructure: true
  test "write_transaction_chain/1 should persist the transaction chain" do
    tx1 = create_transaction(index: 0)
    Process.sleep(100)
    tx2 = create_transaction(index: 1)

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
        "SELECT * FROM uniris.transaction_chains WHERE chain_address = ?"
      )

    assert {:ok, %Xandra.Page{content: [_ | _]}} =
             Xandra.execute(:xandra_conn, chain_prepared_query, [
               List.first(chain).address
             ])
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
  test "register_beacon_slot/1 should register a beacon slot" do
    slot_time = DateTime.utc_now()
    assert :ok = Cassandra.register_beacon_slot(%Slot{subset: <<0>>, slot_time: slot_time})

    prepared_tx_query =
      Xandra.prepare!(
        :xandra_conn,
        "SELECT * FROM uniris.beacon_chain_slot WHERE subset = ? and slot_time = ?"
      )

    assert {:ok, %Xandra.Page{content: [_]}} =
             Xandra.execute(:xandra_conn, prepared_tx_query, [<<0>>, slot_time])
  end

  describe "get_beacon_slots/1" do
    @tag infrastructure: true
    test "should return an empty list when not previous slots were registered" do
      assert 0 == Cassandra.get_beacon_slots(<<0>>, DateTime.utc_now()) |> Enum.count()
    end

    @tag infrastructure: true
    test "should return a list of beacon slots registered" do
      assert :ok =
               Cassandra.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})

      assert :ok =
               Cassandra.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})

      assert :ok =
               Cassandra.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})

      assert 3 ==
               Cassandra.get_beacon_slots(<<0>>, DateTime.utc_now() |> DateTime.add(2))
               |> Enum.count()
    end
  end

  describe "get_beacon_slot/2" do
    @tag infrastructure: true
    test "should retrieve a given slot by subset and slot time" do
      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2) |> Utils.truncate_datetime()

      assert :ok = Cassandra.register_beacon_slot(%Slot{subset: <<0>>, slot_time: d1})
      assert :ok = Cassandra.register_beacon_slot(%Slot{subset: <<1>>, slot_time: d2})

      assert {:ok, %Slot{slot_time: slot_time}} = Cassandra.get_beacon_slot(<<1>>, d2)
      assert Utils.truncate_datetime(slot_time) == d2
    end

    @tag infrastructure: true
    test "should return an error when not slot is found for the given subset and date" do
      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2) |> Utils.truncate_datetime()

      assert :ok = Cassandra.register_beacon_slot(%Slot{subset: <<0>>, slot_time: d1})
      assert {:error, :not_found} = Cassandra.get_beacon_slot(<<1>>, d2)
    end
  end

  @tag infrastructure: true
  test "register_beacon_summary/1 should register the summary into the database" do
    assert :ok =
             Cassandra.register_beacon_summary(%Summary{
               subset: <<0>>,
               summary_time: DateTime.utc_now()
             })
  end

  describe "get_beacon_summary/2" do
    @tag infrastructure: true
    test "should retrieve a given summary by subset and summary time" do
      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2) |> Utils.truncate_datetime()

      assert :ok = Cassandra.register_beacon_summary(%Summary{subset: <<0>>, summary_time: d1})
      assert :ok = Cassandra.register_beacon_summary(%Summary{subset: <<1>>, summary_time: d2})

      assert {:ok, %Summary{summary_time: summary_time}} = Cassandra.get_beacon_summary(<<1>>, d2)
      assert Utils.truncate_datetime(summary_time) == d2
    end

    @tag infrastructure: true
    test "should return an error when not summary is found for the given subset and date" do
      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2)

      assert :ok = Cassandra.register_beacon_summary(%Summary{subset: <<0>>, summary_time: d1})
      assert {:error, :not_found} = Cassandra.get_beacon_summary(<<1>>, d2)
    end
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
      create_transaction(index: 1, type: :transfer),
      create_transaction(index: 0, type: :hosting)
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
    tx1 = create_transaction(index: 0)
    tx2 = create_transaction(index: 1)
    tx3 = create_transaction(index: 2)

    chain = [tx3, tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert tx3.address == Cassandra.get_last_chain_address(tx3.address, tx3.timestamp)
    assert tx3.address == Cassandra.get_last_chain_address(tx2.address, tx3.timestamp)
    assert tx2.address == Cassandra.get_last_chain_address(tx2.address, tx1.timestamp)
    assert tx1.address == Cassandra.get_last_chain_address(tx1.address, tx1.timestamp)
  end

  @tag infrastructure: true
  test "get_first_chain_address/1 should return the first transaction address of a chain" do
    tx1 = create_transaction(index: 0)
    tx2 = create_transaction(index: 1)
    tx3 = create_transaction(index: 2)

    chain = [tx3, tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert tx1.address == Cassandra.get_first_chain_address(tx3.address)
    assert tx1.address == Cassandra.get_first_chain_address(tx2.address)
    assert tx1.address == Cassandra.get_first_chain_address(tx1.address)
  end

  @tag infrastructure: true
  test "get_first_public_key/1 should return the first public key from a transaction address of a chain" do
    tx1 = create_transaction(index: 0)
    tx2 = create_transaction(index: 1)
    tx3 = create_transaction(index: 2)

    chain = [tx3, tx2, tx1]
    assert :ok = Cassandra.write_transaction_chain(chain)

    assert tx1.previous_public_key == Cassandra.get_first_public_key(tx3.previous_public_key)
    assert tx1.previous_public_key == Cassandra.get_first_public_key(tx2.previous_public_key)
    assert tx1.previous_public_key == Cassandra.get_first_public_key(tx1.previous_public_key)
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
