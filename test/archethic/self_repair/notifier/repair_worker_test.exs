defmodule Archethic.SelfRepair.Notifier.RepairWorkerTest do
  @moduledoc false
  use ArchethicCase

  alias Archethic.SelfRepair.Notifier.RepairWorker
  alias Archethic.SelfRepair.Notifier.Impl, as: NotifierImpl

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
      gen_addr = "gen_addr"
      last_Addr = "last_Addr"
      opts = %{genesis_address: gen_addr, last_address: last_Addr}

      MockDB
      |> stub(
        :transaction_exists?,
        fn _ ->
          Process.sleep(50)
          true
        end
      )

      {:ok, pid} = RepairWorker.start_link(opts)

      assert {:idle, %{:addresses => [], :genesis_address => "gen_addr"}} = :sys.get_state(pid)

      assert [{^pid, _}] = Registry.lookup(@registry_name, gen_addr)

      Enum.each(1..3, fn x ->
        NotifierImpl.update_worker(
          %{genesis_address: gen_addr, last_address: "txn" <> "#{x}"},
          pid
        )
      end)

      assert {:idle, %{:addresses => ["txn3", "txn2", "txn1"], :genesis_address => "gen_addr"}} =
               :sys.get_state(pid)

      Process.sleep(200)

      assert {:idle, %{:addresses => [], :genesis_address => "gen_addr"}} = :sys.get_state(pid)

      Process.sleep(100)
      assert [] = Registry.lookup(@registry_name, gen_addr)
    end

    test "should continue even if repair chain crashes" do
      gen_addr = "aa"
      last_Addr = "bb"
      opts = %{genesis_address: gen_addr, last_address: last_Addr}

      {:ok, pid} = RepairWorker.start_link(opts)
      assert {:idle, %{:addresses => [], :genesis_address => "aa"}} = :sys.get_state(pid)
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

      :ok
    end

    test "RepairWorker flow from ShardRepair" do
      alias Archethic.P2P.Message

      # %Message.ShardRepair{
      #   genesis_address: "gen_addr"
      # }
      IO.inspect(build_chain("randomseed ", 7), label: "==", limit: :infinity)
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
    end
  end
end
