defmodule Uniris.BeaconChain.Subset do
  @moduledoc """
  Represents a beacon slot running inside a process
  waiting to receive transactions to register in a beacon slot
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.Subset.Seal

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
    GenServer.cast(via_tuple(subset), {:add_slot_proof, digest, node_public_key, signature})
  end

  defp via_tuple(subset) do
    {:via, Registry, {SubsetRegistry, subset}}
  end

  def init([subset]) do
    {:ok,
     %{
       subset: subset,
       current_slot: %Slot{subset: subset},
       previous_slot: nil
     }}
  end

  def handle_call(
        {:add_transaction_summary,
         tx_summary = %TransactionSummary{address: address, type: type}},
        _from,
        state = %{current_slot: current_slot, subset: subset}
      ) do
    if Slot.has_transaction?(current_slot, address) do
      {:reply, :ok, state}
    else
      current_slot = Slot.add_transaction_summary(current_slot, tx_summary)

      Logger.info("Transaction #{type}@#{Base.encode16(address)} added to the beacon chain",
        beacon_subset: Base.encode16(subset)
      )

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

  def handle_cast(
        {:add_slot_proof, digest, node_public_key, signature},
        state
      ) do
    case Map.fetch(state, :consensus_worker) do
      {:ok, pid} ->
        SlotConsensus.add_slot_proof(pid, digest, node_public_key, signature)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:create_slot, slot_time},
        state = %{
          subset: subset,
          current_slot: current_slot
        }
      ) do
    new_state =
      state
      |> Map.put(:previous_slot, current_slot)
      |> Map.put(:current_slot, %Slot{subset: subset})
      |> Map.put(:last_slot_date, slot_time)

    if Slot.has_changes?(current_slot) do
      previous_date = Map.get(state, :last_slot_date) || DateTime.utc_now()

      current_slot =
        %{
          current_slot
          | slot_time: slot_time
        }
        |> Seal.link_to_previous_slot(previous_date)

      {:ok, consensus_worker} =
        SlotConsensus.start_link(node_public_key: Crypto.node_public_key(0), slot: current_slot)

      {:noreply, Map.put(new_state, :consensus_worker, consensus_worker)}
    else
      {:noreply, new_state}
    end
  end

  def handle_info(
        {:create_summary, summary_time},
        state = %{
          subset: subset,
          current_slot: current_slot
        }
      ) do
    Task.start(fn -> Seal.new_summary(subset, summary_time, current_slot) end)
    {:noreply, Map.delete(state, :last_slot_date)}
  end
end
