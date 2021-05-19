defmodule Uniris.BeaconChain.Subset do
  @moduledoc """
  Represents a beacon slot running inside a process
  waiting to receive transactions to register in a beacon slot
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer

  alias Uniris.BeaconChain.Subset.Seal

  alias __MODULE__.P2PSampling
  alias __MODULE__.Seal
  alias __MODULE__.SlotConsensus

  alias Uniris.BeaconChain.SubsetRegistry

  alias Uniris.Crypto

  alias Uniris.Utils

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
    GenServer.cast(via_tuple(subset), {:add_transaction_summary, tx_summary})
  end

  @doc """
  Add an end of synchronization to the current slot for the given subset
  """
  @spec add_end_of_node_sync(subset :: binary(), EndOfNodeSync.t()) :: :ok
  def add_end_of_node_sync(subset, end_of_node_sync = %EndOfNodeSync{}) when is_binary(subset) do
    GenServer.cast(via_tuple(subset), {:add_end_of_node_sync, end_of_node_sync})
  end

  @doc """
  Add the beacon slot proof for validation
  """
  @spec add_slot(Slot.t(), Crypto.key(), binary()) :: :ok
  def add_slot(slot = %Slot{subset: subset}, node_public_key, signature)
      when is_binary(node_public_key) and is_binary(signature) do
    GenServer.cast(via_tuple(subset), {:add_slot, slot, node_public_key, signature})
  end

  @doc """
  Get the current slot
  """
  @spec get_current_slot(binary()) :: Slot.t()
  def get_current_slot(subset) when is_binary(subset) do
    GenServer.call(via_tuple(subset), :get_current_slot)
  end

  defp via_tuple(subset) do
    {:via, Registry, {SubsetRegistry, subset}}
  end

  def init([subset]) do
    nb_nodes_to_sample =
      subset
      |> P2PSampling.list_nodes_to_sample()
      |> length()

    {:ok,
     %{
       node_public_key: Crypto.node_public_key(0),
       subset: subset,
       current_slot: Slot.new(subset, SlotTimer.next_slot(DateTime.utc_now()), nb_nodes_to_sample)
     }}
  end

  def handle_cast(
        {:add_transaction_summary,
         tx_summary = %TransactionSummary{address: address, type: type}},
        state = %{current_slot: current_slot, subset: subset}
      ) do
    if Slot.has_transaction?(current_slot, address) do
      {:reply, :ok, state}
    else
      current_slot = Slot.add_transaction_summary(current_slot, tx_summary)

      Logger.info("Transaction #{type}@#{Base.encode16(address)} added to the beacon chain",
        beacon_subset: Base.encode16(subset)
      )

      # Request the P2P view sampling if the not perfomed from the last 10 seconds
      case Map.get(state, :sampling_time) do
        nil ->
          new_state =
            state
            |> Map.put(:current_slot, add_p2p_view(current_slot))
            |> Map.put(:sampling_time, DateTime.utc_now())

          {:noreply, new_state}

        time ->
          if DateTime.diff(DateTime.utc_now(), time) > 3 do
            new_state =
              state
              |> Map.put(:current_slot, add_p2p_view(current_slot))
              |> Map.put(:sampling_time, DateTime.utc_now())

            {:noreply, new_state}
          else
            {:noreply, %{state | current_slot: current_slot}}
          end
      end
    end
  end

  def handle_cast(
        {:add_end_of_node_sync, end_of_sync = %EndOfNodeSync{public_key: node_public_key}},
        state = %{current_slot: current_slot, subset: subset}
      ) do
    Logger.info(
      "Node #{Base.encode16(node_public_key)} synchronization ended added to the beacon chain",
      beacon_subset: Base.encode16(subset)
    )

    current_slot = Slot.add_end_of_node_sync(current_slot, end_of_sync)
    {:noreply, %{state | current_slot: current_slot}}
  end

  def handle_cast(
        {:add_slot, slot, node_public_key, signature},
        state = %{consensus_worker: pid}
      ) do
    SlotConsensus.add_remote_slot(pid, slot, node_public_key, signature)
    {:noreply, state}
  end

  def handle_cast({:add_slot, _, _, _}, state), do: {:noreply, state}

  def handle_call(:get_current_slot, _, state = %{current_slot: slot}) do
    {:reply, slot, state}
  end

  def handle_info(
        {:create_slot, _time},
        state = %{
          subset: subset,
          current_slot: current_slot = %Slot{slot_time: slot_time},
          node_public_key: node_public_key
        }
      ) do
    if beacon_slot_node?(subset, slot_time, node_public_key) do
      nb_nodes_to_sample =
        subset
        |> P2PSampling.list_nodes_to_sample()
        |> length()

      new_state =
        state
        |> Map.put(
          :current_slot,
          Slot.new(subset, SlotTimer.next_slot(DateTime.utc_now()), nb_nodes_to_sample)
        )
        |> Map.put(:last_slot_date, slot_time)

      current_slot = ensure_p2p_view(current_slot)
      previous_date = Map.get(state, :last_slot_date) || DateTime.utc_now()

      if Slot.has_changes?(current_slot) do
        sealed_slot = Seal.link_to_previous_slot(current_slot, previous_date)

        {:ok, consensus_worker} =
          SlotConsensus.start_link(node_public_key: node_public_key, slot: sealed_slot)

        {:noreply, Map.put(new_state, :consensus_worker, consensus_worker)}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:create_summary, summary_time},
        state = %{
          subset: subset,
          current_slot: current_slot = %Slot{slot_time: slot_time},
          node_public_key: node_public_key
        }
      ) do
    if beacon_summary_node?(subset, slot_time, node_public_key) do
      Task.start(fn -> Seal.new_summary(subset, summary_time, current_slot) end)
      {:noreply, Map.delete(state, :last_slot_date)}
    else
      {:noreply, state}
    end
  end

  defp beacon_slot_node?(subset, slot_time, node_public_key) do
    %Slot{subset: subset, slot_time: slot_time}
    |> Slot.involved_nodes()
    |> Utils.key_in_node_list?(node_public_key)
  end

  defp beacon_summary_node?(subset, slot_time, node_public_key) do
    %Slot{subset: subset, slot_time: slot_time}
    |> Slot.summary_storage_nodes()
    |> Utils.key_in_node_list?(node_public_key)
  end

  defp add_p2p_view(current_slot = %Slot{subset: subset}) do
    p2p_views = P2PSampling.get_p2p_views(P2PSampling.list_nodes_to_sample(subset))

    Slot.add_p2p_view(current_slot, p2p_views)
  end

  defp ensure_p2p_view(slot = %Slot{p2p_view: %{network_stats: []}}) do
    add_p2p_view(slot)
  end

  defp ensure_p2p_view(slot = %Slot{}), do: slot
end
