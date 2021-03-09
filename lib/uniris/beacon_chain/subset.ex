defmodule Uniris.BeaconChain.Subset do
  @moduledoc """
  Represents a beacon slot running inside a process 
  waiting to receive transactions to register in a beacon slot
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.P2P

  alias Uniris.Crypto

  alias __MODULE__.Seal
  alias __MODULE__.SlotConsensus

  alias Uniris.BeaconChain.SubsetRegistry

  use GenServer

  require Logger

  def start_link(opts) do
    subset = Keyword.get(opts, :subset)
    GenServer.start_link(__MODULE__, [subset], name: via_tuple(subset))
  end

  @doc """
  Add transaction summary to the current slot for the given subset
  """
  @spec add_transaction_summary(subset :: binary(), TransactionSummary.t()) :: :ok
  def add_transaction_summary(subset, tx_summary = %TransactionSummary{})
      when is_binary(subset) do
    GenServer.call(via_tuple(subset), {:add_transaction_summary, tx_summary})
  end

  @doc """
  Add an end of synchronization to the current slot for the given subset
  """
  @spec add_end_of_node_sync(subset :: binary(), EndOfNodeSync.t()) :: :ok
  def add_end_of_node_sync(subset, end_of_node_sync = %EndOfNodeSync{}) when is_binary(subset) do
    GenServer.call(via_tuple(subset), {:add_end_of_node_sync, end_of_node_sync})
  end

  @doc """
  Add the beacon slot proof for validation
  """
  @spec add_slot_proof(binary(), binary(), Crypto.key(), binary()) :: :ok
  def add_slot_proof(subset, digest, node_public_key, signature)
      when is_binary(subset) and is_binary(digest) and is_binary(node_public_key) and
             is_binary(signature) do
    GenServer.call(via_tuple(subset), {:add_slot_proof, digest, node_public_key, signature})
  end

  @spec get_current_slot(binary()) :: Slot.t()
  def get_current_slot(subset) when is_binary(subset) do
    GenServer.call(via_tuple(subset), :get_current_slot)
  end

  defp via_tuple(subset) do
    {:via, Registry, {SubsetRegistry, subset}}
  end

  def init([subset]) do
    Process.flag(:trap_exit, true)
    {:ok, consensus_worker_pid} = SlotConsensus.start_link()
    Process.monitor(consensus_worker_pid)

    {:ok,
     %{
       subset: subset,
       current_slot: %Slot{subset: subset},
       consensus_worker: consensus_worker_pid
     }}
  end

  def handle_call(
        {:add_transaction_summary,
         tx_summary = %TransactionSummary{address: address, type: type}},
        _from,
        state = %{current_slot: current_slot, subset: subset}
      ) do
    nodes =
      Enum.filter(P2P.list_nodes(), fn x -> :binary.part(x.first_public_key, 0, 1) == subset end)

    message = "test"
    _p2p_view_available =
      nodes
      |> Task.async_stream(fn node -> P2P.send_message(node, message) end)
      |> Enum.map(fn {:ok, result} -> result end)

    if Slot.has_transaction?(current_slot, address) do
      {:reply, :ok, state}
    else
      Logger.info("Transaction #{type}@#{Base.encode16(address)} added to the beacon chain",
        beacon_subset: Base.encode16(subset)
      )

      current_slot = Slot.add_transaction_summary(current_slot, tx_summary)
      {:reply, :ok, %{state | current_slot: current_slot}}
    end
  end

  def handle_call(
        {:add_end_of_node_sync, end_of_sync = %EndOfNodeSync{public_key: node_public_key}},
        _from,
        state = %{current_slot: current_slot, subset: subset}
      ) do
    Logger.info(
      "Node #{Base.encode16(node_public_key)} synchronization ended added to the beacon chain",
      beacon_subset: Base.encode16(subset)
    )

    current_slot = Slot.add_end_of_node_sync(current_slot, end_of_sync)
    {:reply, :ok, %{state | current_slot: current_slot}}
  end

  def handle_call(
        {:add_slot_proof, digest, node_public_key, signature},
        _,
        state = %{consensus_worker: consensus_worker}
      ) do
    SlotConsensus.add_slot_proof(consensus_worker, digest, node_public_key, signature)
    {:reply, :ok, state}
  end

  def handle_call(:get_current_slot, _from, state = %{current_slot: slot}) do
    {:reply, slot, state}
  end

  def handle_info(
        {:create_slot, slot_time},
        state = %{
          subset: subset,
          current_slot: current_slot,
          consensus_worker: consensus_worker
        }
      ) do
    SlotConsensus.validate_and_notify_slot(consensus_worker, %{
      current_slot
      | slot_time: slot_time
    })

    {:noreply, %{state | current_slot: %Slot{subset: subset}}}
  end

  def handle_info(
        {:create_summary, summary_time},
        state = %{
          subset: subset
        }
      ) do
    Task.start(fn -> Seal.new_summary(subset, summary_time) end)
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, _ref, :process, pid, _reason},
        state = %{consensus_worker: consensus_worker_pid}
      )
      when pid == consensus_worker_pid do
    {:ok, consensus_worker_pid} = SlotConsensus.start_link()
    Process.monitor(consensus_worker_pid)
    {:noreply, Map.put(state, :consensus_worker, consensus_worker_pid)}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.error("#{inspect(reason)}")
    {:noreply, state}
  end
end
