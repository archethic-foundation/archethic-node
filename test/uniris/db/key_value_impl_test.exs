defmodule Uniris.DB.KeyValueImplTest do
  use UnirisCase, async: false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Summary

  alias Uniris.Crypto

  alias Uniris.DB.KeyValueImpl, as: KV

  alias Uniris.P2P
  alias Uniris.P2P.Node

  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionFactory

  setup do
    File.rm_rf!(Application.app_dir(:uniris, "priv/storage/kv_test"))

    path = Path.join("priv/storage/kv_test", Base.encode16(:crypto.strong_rand_bytes(16)))
    root_dir = Application.app_dir(:uniris, path)

    on_exit(fn ->
      File.rm_rf!(Application.app_dir(:uniris, "priv/storage/kv_test"))
    end)

    {:ok, %{root_dir: root_dir}}
  end

  test "start_link/1 should initiate a KV store instance", %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)
    assert File.dir?(root_dir)

    assert :undefined != :ets.info(:uniris_kv_db_transactions)
    assert :undefined != :ets.info(:uniris_kv_db_chain)
    assert :undefined != :ets.info(:uniris_kv_db_beacon_slots)
    assert :undefined != :ets.info(:uniris_kv_db_beacon_slot)
    assert :undefined != :ets.info(:uniris_kv_db_beacon_summary)
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

    [{_, _}, {_, _}] = :ets.lookup(:uniris_kv_db_chain, List.first(chain).address)

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
    assert :ok = KV.add_last_transaction_address("@Alice1", "@Alice2")
  end

  test "list_last_transaction_addresses/0 should retrieve the last transaction addresses", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)
    KV.add_last_transaction_address("@Alice1", "@Alice2")
    KV.add_last_transaction_address("@Alice1", "@Alice3")
    KV.add_last_transaction_address("@Alice1", "@Alice4")
    assert [{"@Alice1", "@Alice4"}] = KV.list_last_transaction_addresses() |> Enum.to_list()
  end

  test "register_beacon_slot/1 should register a beacon slot", %{root_dir: root_dir} do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)
    assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
  end

  describe "get_beacon_slots/2" do
    test "should return an empty list when not previous slots were registered", %{
      root_dir: root_dir
    } do
      {:ok, _pid} = KV.start_link(root_dir: root_dir)
      assert [] == KV.get_beacon_slots(<<0>>, DateTime.utc_now()) |> Enum.to_list()
    end

    test "should return a list of beacon slots registered before a given date", %{
      root_dir: root_dir
    } do
      {:ok, _pid} = KV.start_link(root_dir: root_dir)
      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})

      assert [%Slot{}, %Slot{}, %Slot{}] =
               KV.get_beacon_slots(<<0>>, DateTime.utc_now() |> DateTime.add(2)) |> Enum.to_list()
    end

    test "should return an empty list of beacon slots registered after a given date", %{
      root_dir: root_dir
    } do
      {:ok, _pid} = KV.start_link(root_dir: root_dir)
      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})
      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: DateTime.utc_now()})

      assert [] =
               KV.get_beacon_slots(<<0>>, DateTime.utc_now() |> DateTime.add(-2))
               |> Enum.to_list()
    end
  end

  describe "get_beacon_slot/2" do
    test "should retrieve a given slot by subset and slot time", %{root_dir: root_dir} do
      {:ok, _pid} = KV.start_link(root_dir: root_dir)

      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2)

      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: d1})
      assert :ok = KV.register_beacon_slot(%Slot{subset: <<1>>, slot_time: d2})

      assert {:ok, %Slot{slot_time: ^d2}} = KV.get_beacon_slot(<<1>>, d2)
    end

    test "should return an error when not slot is found for the given subset and date", %{
      root_dir: root_dir
    } do
      {:ok, _pid} = KV.start_link(root_dir: root_dir)

      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2)

      assert :ok = KV.register_beacon_slot(%Slot{subset: <<0>>, slot_time: d1})
      assert {:error, :not_found} = KV.get_beacon_slot(<<1>>, d2)
    end
  end

  test "register_beacon_summary/1 should register the summary into the database", %{
    root_dir: root_dir
  } do
    {:ok, _pid} = KV.start_link(root_dir: root_dir)

    assert :ok =
             KV.register_beacon_summary(%Summary{subset: <<0>>, summary_time: DateTime.utc_now()})
  end

  describe "get_beacon_summary/2" do
    test "should retrieve a given summary by subset and summary time", %{root_dir: root_dir} do
      {:ok, _pid} = KV.start_link(root_dir: root_dir)

      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2)

      assert :ok = KV.register_beacon_summary(%Summary{subset: <<0>>, summary_time: d1})
      assert :ok = KV.register_beacon_summary(%Summary{subset: <<1>>, summary_time: d2})

      assert {:ok, %Summary{summary_time: ^d2}} = KV.get_beacon_summary(<<1>>, d2)
    end

    test "should return an error when not summary is found for the given subset and date", %{
      root_dir: root_dir
    } do
      {:ok, _pid} = KV.start_link(root_dir: root_dir)

      d1 = DateTime.utc_now()
      d2 = DateTime.utc_now() |> DateTime.add(2)

      assert :ok = KV.register_beacon_summary(%Summary{subset: <<0>>, summary_time: d1})
      assert {:error, :not_found} = KV.get_beacon_summary(<<1>>, d2)
    end
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

  defp create_transaction(index \\ 0) do
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

    TransactionFactory.create_valid_transaction(context, [], index: index)
  end

  defp empty_keys(tx) do
    tx
    |> Transaction.to_map()
    |> Enum.filter(&match?({_, nil}, &1))
    |> Enum.map(fn {k, _} -> k end)
  end
end
