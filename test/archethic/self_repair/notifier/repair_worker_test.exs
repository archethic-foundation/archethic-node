defmodule Archethic.SelfRepair.Notifier.RepairWorkerTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.SelfRepair.Notifier.Impl, as: NotifierImpl
  alias Archethic.SelfRepair.Notifier.RepairWorker

  import Mox
  @registry_name Archethic.SelfRepair.Notifier.Impl.registry_name()
  describe "RepairWorker FSM Behaviour" do
    setup do
      case Process.whereis(@registry_name) do
        nil ->
          start_supervised!({Registry, name: @registry_name, keys: :unique, partitions: 1})

        pid when is_pid(pid) ->
          :ok
      end

      :ok
    end

    test "Expected behaviour Repair worker" do
      first_address = "first_address"
      last_addr = "last_addr"
      opts = %{first_address: first_address, last_address: last_addr}

      MockDB
      |> stub(
        :transaction_exists?,
        fn _ ->
          Process.sleep(50)
          true
        end
      )

      {:ok, pid} = RepairWorker.start_link(opts)

      # first repair task deployed during init
      assert {:idle, %{:addresses => [], :first_address => "first_address"}} = :sys.get_state(pid)

      assert [{^pid, _}] = Registry.lookup(@registry_name, first_address)

      Enum.each(1..3, fn x ->
        NotifierImpl.update_worker(
          %{first_address: first_address, last_address: "txn" <> "#{x}"},
          pid
        )
      end)

      assert {:idle, %{:addresses => ["txn3", "txn2", "txn1"], :first_address => "first_address"}} =
               :sys.get_state(pid)

      Process.sleep(200)

      assert {:idle, %{:addresses => [], :first_address => "first_address"}} = :sys.get_state(pid)

      Process.sleep(100)
      assert [] = Registry.lookup(@registry_name, first_address)
    end

    test "should continue even if repair chain crashes" do
      first_address = "aa"
      last_addr = "bb"
      opts = %{first_address: first_address, last_address: last_addr}

      {:ok, pid} = RepairWorker.start_link(opts)
      assert {:idle, %{:addresses => [], :first_address => "aa"}} = :sys.get_state(pid)
    end
  end

  describe "RepairWorker flow from Message.Process" do
    setup do
      alias Archethic.TransactionFactory

      :ok = TransactionFactory.build_valid_p2p_view()

      case Process.whereis(@registry_name) do
        nil ->
          start_supervised!({Registry, name: @registry_name, keys: :unique, partitions: 1})

        pid when is_pid(pid) ->
          :ok
      end

      case Process.whereis(Archethic.SelfRepair.Notifier.RepairSupervisor) do
        nil ->
          start_supervised!(
            {DynamicSupervisor,
             strategy: :one_for_one, name: Archethic.SelfRepair.Notifier.RepairSupervisor}
          )

        pid when is_pid(pid) ->
          :ok
      end

      :ok
    end

    test "RepairWorker flow from ShardRepair" do
      alias Archethic.P2P.Message
      alias Archethic.P2P.Message.ShardRepair

      chain_list = build_chain("random seed", 3)
      first_address = Map.get(chain_list, 0).address
      addr1 = Map.get(chain_list, 1).address
      addr2 = Map.get(chain_list, 2).address

      msg_list =
        Enum.map(chain_list, fn
          {index, txn} ->
            %ShardRepair{
              first_address: first_address,
              last_address: txn.address
            }
        end)

      assert Enum.map(chain_list, fn _x ->
               %Message.Ok{}
             end) == Enum.map(msg_list, fn msg -> Message.process(msg) end)

      assert [{pid, _}] = Registry.lookup(NotifierImpl.registry_name(), first_address)

      {:idle,
       %{
         addresses: [^addr2, ^addr1],
         first_address: ^first_address
       }} = :sys.get_state(pid)
    end

    def build_chain(seed, length \\ 1) when length > 0 do
      alias Archethic.TransactionFactory

      time = DateTime.utc_now() |> DateTime.add(-5000 * length)

      Enum.reduce(0..(length - 1), _acc = {_map = %{}, _prev_tx = []}, fn
        index, {map, prev_tx} ->
          # put input un mock client
          txn =
            TransactionFactory.create_valid_chain(
              [],
              seed: seed,
              index: index,
              prev_txn: prev_tx,
              timestamp: time |> DateTime.add(5000 * index)
            )

          {
            Map.put(map, index, txn),
            [txn]
          }
      end)
      |> elem(0)
    end

    # test "Stress Test RepairWorker" do
    # end
  end
end
