defmodule Uniris.DB.KeyValueImplTest do
  use UnirisCase, async: false

  alias Uniris.Crypto

  alias Uniris.DB.KeyValueImpl, as: KV

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionFactory

  alias Uniris.Utils

  setup do
    File.rm_rf!(Utils.mut_dir("priv/storage/kv_test"))

    path = Path.join("priv/storage/kv_test", Base.encode16(:crypto.strong_rand_bytes(16)))

    on_exit(fn ->
      File.rm_rf!(Utils.mut_dir("priv/storage/kv_test"))
    end)

    {:ok, %{root_dir: path}}
  end

  test "start_link/1 should initiate a KV store instance", %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)
    assert File.dir?(Utils.mut_dir(root_dir))

    assert :undefined != :ets.info(:uniris_kv_db_transactions)
    assert :undefined != :ets.info(:uniris_kv_db_chain)
    assert :undefined != :ets.info(:uniris_kv_db_beacon_slots)
    assert :undefined != :ets.info(:uniris_kv_db_beacon_slot)
    assert :undefined != :ets.info(:uniris_kv_db_beacon_summary)
    assert :undefined != :ets.info(:uniris_kv_transactions_type_lookup)
  end

  test "write_transaction/1 should persist the transaction in the KV", %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    tx = create_transaction()
    assert :ok = KV.write_transaction(tx)

    assert [{_, ^tx}] = :ets.lookup(:uniris_kv_db_transactions, tx.address)
  end

  test "write_transaction_chain/1 should persist the transaction chain in the KV and index it", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    chain = [create_transaction(1), create_transaction(0)]
    assert :ok = KV.write_transaction_chain(chain)

    [{_, _}, {_, _}] = :ets.lookup(:uniris_kv_db_chain, {:addresses, List.first(chain).address})
    assert [{_, 2}] = :ets.lookup(:uniris_kv_db_chain, {:size, List.first(chain).address})

    Enum.all?(chain, fn tx ->
      assert [{_, _}] = :ets.lookup(:uniris_kv_db_transactions, tx.address)
    end)
  end

  test "list_transactions/1 should stream the entire list of transactions with the requested fields",
       %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    Enum.each(1..100, fn i ->
      tx = create_transaction(i)
      :ok = KV.write_transaction(tx)
    end)

    transactions = KV.list_transactions([:address, :type])

    assert 100 == Enum.count(transactions)

    assert Enum.all?(transactions, &([:address, :type] not in empty_keys(&1)))
  end

  test "get_transaction/2 should retrieve the transaction with the requested fields ", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)
    tx = create_transaction()
    assert :ok = KV.write_transaction(tx)

    assert {:ok, tx} = KV.get_transaction(tx.address, [:address, :type])
    assert [:address, :type] not in empty_keys(tx)
  end

  test "get_transaction_chain/2 should retrieve the transaction chain with the requested fields ",
       %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)
    chain = [create_transaction(1), create_transaction(0)]
    assert :ok = KV.write_transaction_chain(chain)
    chain = KV.get_transaction_chain(List.first(chain).address, [:address, :type])
    Enum.all?(chain, &([:address, :type] not in empty_keys(&1)))
  end

  test "add_last_transaction_address/2 should reference a last address for a chain", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)
    assert :ok = KV.add_last_transaction_address("@Alice1", "@Alice2", DateTime.utc_now())
  end

  test "list_last_transaction_addresses/0 should retrieve the last transaction addresses", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    d = DateTime.utc_now()
    d1 = DateTime.utc_now() |> DateTime.add(1)
    d2 = DateTime.utc_now() |> DateTime.add(2)

    KV.add_last_transaction_address("@Alice1", "@Alice2", d)
    KV.add_last_transaction_address("@Alice1", "@Alice3", d1)
    KV.add_last_transaction_address("@Alice1", "@Alice4", d2)
    assert [{"@Alice1", "@Alice4", ^d2}] = KV.list_last_transaction_addresses() |> Enum.to_list()
  end

  test "chain_size/1 should return the size of a transaction chain", %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    chain = [create_transaction(1), create_transaction(0)]
    assert :ok = KV.write_transaction_chain(chain)

    assert 2 == KV.chain_size(List.first(chain).address)

    assert 0 == KV.chain_size(:crypto.strong_rand_bytes(32))
  end

  test "list_transactions_by_type/1 should return the list of transaction by the given type", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    chain = [create_transaction(1, :transfer), create_transaction(0, :hosting)]
    assert :ok = KV.write_transaction_chain(chain)

    assert [List.first(chain).address] ==
             KV.list_transactions_by_type(:transfer) |> Enum.map(& &1.address)

    assert [List.last(chain).address] ==
             KV.list_transactions_by_type(:hosting) |> Enum.map(& &1.address)

    assert [] == KV.list_transactions_by_type(:node) |> Enum.map(& &1.address)
  end

  test "count_transactions_by_type/1 should return the number of transactions for a given type",
       %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    chain = [create_transaction(1, :transfer), create_transaction(0, :hosting)]
    assert :ok = KV.write_transaction_chain(chain)

    assert 1 == KV.count_transactions_by_type(:transfer)
    assert 1 == KV.count_transactions_by_type(:hosting)
    assert 0 == KV.count_transactions_by_type(:node)
  end

  test "get_last_chain_address/1 should return the last transaction address of a chain", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    KV.add_last_transaction_address("@Alice2", "@Alice3", ~U[2021-03-25 15:12:29Z])
    KV.add_last_transaction_address("@Alice1", "@Alice2", ~U[2021-03-25 15:11:29Z])
    KV.add_last_transaction_address("@Alice0", "@Alice1", ~U[2021-03-25 15:10:29Z])

    assert "@Alice3" == KV.get_last_chain_address("@Alice0")
    assert "@Alice3" == KV.get_last_chain_address("@Alice1")
    assert "@Alice3" == KV.get_last_chain_address("@Alice2")
    assert "@Alice3" == KV.get_last_chain_address("@Alice3")
  end

  test "get_last_chain_address/2 should return the last transaction address of a chain before a given datetime",
       %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    KV.add_last_transaction_address("@Alice2", "@Alice3", ~U[2021-03-25 15:12:29Z])
    KV.add_last_transaction_address("@Alice1", "@Alice2", ~U[2021-03-25 15:11:29Z])
    KV.add_last_transaction_address("@Alice0", "@Alice1", ~U[2021-03-25 15:10:29Z])

    assert "@Alice2" == KV.get_last_chain_address("@Alice1", ~U[2021-03-25 15:11:29Z])
  end

  test "get_first_chain_address/1 should return the first transaction address of a chain", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    chain = [create_transaction(1, :transfer), create_transaction(0, :hosting)]
    assert :ok = KV.write_transaction_chain(chain)

    assert List.last(chain).address == KV.get_first_chain_address(List.first(chain).address)
    assert List.last(chain).address == KV.get_first_chain_address(List.last(chain).address)
  end

  test "get_first_public_key/1 should return the first public key from a transaction address of a chain",
       %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    chain = [create_transaction(1, :transfer), create_transaction(0, :hosting)]
    assert :ok = KV.write_transaction_chain(chain)

    assert List.last(chain).previous_public_key ==
             KV.get_first_public_key(List.first(chain).previous_public_key)

    assert List.last(chain).previous_public_key ==
             KV.get_first_public_key(List.last(chain).previous_public_key)
  end

  test "should dump the tables after a delay", %{root_dir: root_dir} do
    Process.flag(:trap_exit, true)

    {:ok, pid} = KV.start_link(root_dir: root_dir, dump_delay: 1_000)
    tx = create_transaction()
    assert :ok = KV.write_transaction(tx)

    Process.sleep(1_000)
    Process.exit(pid, :kill)
    Process.sleep(100)

    {:ok, _pid} = KV.start_link(root_dir: root_dir, dump_delay: 0)
    assert 1 == KV.list_transactions() |> Enum.count()
  end

  defp create_transaction(index \\ 0, type \\ :transfer) do
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

    Enum.each(storage_nodes, &P2P.add_and_connect_node(&1))

    P2P.add_and_connect_node(welcome_node)
    P2P.add_and_connect_node(coordinator_node)

    context = %{
      welcome_node: welcome_node,
      coordinator_node: coordinator_node,
      storage_nodes: storage_nodes
    }

    TransactionFactory.create_valid_transaction(context, [], index: index, type: type)
  end

  defp empty_keys(tx) do
    tx
    |> Transaction.to_map()
    |> Enum.filter(&match?({_, nil}, &1))
    |> Enum.map(fn {k, _} -> k end)
  end
end
