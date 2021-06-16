defmodule Uniris.BeaconChain.Subset do
  @moduledoc """
  Represents a beacon slot running inside a process
  waiting to receive transactions to register in a beacon slot
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.Summary
  alias Uniris.BeaconChain.SummaryTimer

  alias __MODULE__.P2PSampling

  alias Uniris.BeaconChain.SubsetRegistry

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.ReplicateTransaction

  alias Uniris.TransactionChain
  alias Uniris.TransactionChain.Transaction
  alias Uniris.TransactionChain.Transaction.ValidationStamp
  alias Uniris.TransactionChain.TransactionData

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
       node_public_key: Crypto.first_node_public_key(),
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

      # Request the P2P view sampling if the not perfomed from the last 3 seconds
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

  def handle_info(
        {:create_slot, time},
        state
      ) do
    new_state = handle_slot(time, state)
    handle_summary(time, state)

    {:noreply, new_state}
  end

  defp handle_slot(
         time,
         state = %{
           subset: subset,
           current_slot: current_slot = %Slot{},
           node_public_key: node_public_key
         }
       ) do
    if beacon_slot_node?(subset, time, node_public_key) do
      current_slot = ensure_p2p_view(current_slot)

      beacon_transaction =
        %Transaction{previous_public_key: previous_public_key} =
        create_beacon_transaction(current_slot)

      # Write the beacon chain
      beacon_chain =
        if SummaryTimer.match_interval?(SlotTimer.previous_slot(time)) do
          []
        else
          previous_public_key
          |> Crypto.hash()
          |> TransactionChain.get()
        end

      [beacon_transaction]
      |> Stream.concat(beacon_chain)
      |> TransactionChain.write()

      nb_nodes_to_sample =
        subset
        |> P2PSampling.list_nodes_to_sample()
        |> length()

      next_time = SlotTimer.next_slot(time)

      new_state =
        Map.put(
          state,
          :current_slot,
          Slot.new(subset, next_time, nb_nodes_to_sample)
        )

      if time |> SlotTimer.next_slot() |> SummaryTimer.match_interval?() do
        new_state
      else
        # Send the transaction for the next pool
        %Slot{subset: subset, slot_time: next_time}
        |> Slot.involved_nodes()
        |> Enum.reject(&(&1.first_public_key == node_public_key))
        |> P2P.broadcast_message(%ReplicateTransaction{
          transaction: beacon_transaction
        })

        new_state
      end
    else
      state
    end
  end

  defp handle_summary(time, state = %{subset: subset, node_public_key: node_public_key}) do
    if SummaryTimer.match_interval?(DateTime.truncate(time, :millisecond)) and
         beacon_summary_node?(subset, time, node_public_key) do
      Task.start(fn -> create_summary_transaction(subset, time) end)
      state
    else
      state
    end
  end

  defp beacon_slot_node?(subset, slot_time, node_public_key) do
    %Slot{subset: subset, slot_time: slot_time}
    |> Slot.involved_nodes()
    |> Utils.key_in_node_list?(node_public_key)
  end

  defp beacon_summary_node?(subset, summary_time, node_public_key) do
    node_list =
      Enum.filter(
        P2P.authorized_nodes(),
        &(DateTime.compare(&1.authorization_date, summary_time) == :lt)
      )

    Election.beacon_storage_nodes(
      subset,
      summary_time,
      node_list,
      Election.get_storage_constraints()
    )
    |> Utils.key_in_node_list?(node_public_key)
  end

  defp add_p2p_view(current_slot = %Slot{subset: subset}) do
    p2p_views = P2PSampling.get_p2p_views(P2PSampling.list_nodes_to_sample(subset))

    Slot.add_p2p_view(current_slot, p2p_views)
  end

  defp ensure_p2p_view(slot = %Slot{p2p_view: %{availabilities: <<>>}}) do
    add_p2p_view(slot)
  end

  defp ensure_p2p_view(slot = %Slot{}), do: slot

  defp create_beacon_transaction(slot = %Slot{subset: subset, slot_time: slot_time}) do
    {prev_pub, prev_pv} = Crypto.derive_beacon_keypair(subset, SlotTimer.previous_slot(slot_time))
    {next_pub, _} = Crypto.derive_beacon_keypair(subset, slot_time)

    tx =
      Transaction.new(
        :beacon,
        %TransactionData{content: Slot.serialize(slot) |> Utils.wrap_binary()},
        prev_pv,
        prev_pub,
        next_pub
      )

    previous_address = Transaction.previous_address(tx)

    prev_tx =
      case TransactionChain.get_transaction(previous_address) do
        {:error, :transaction_not_exists} ->
          nil

        {:ok, prev_tx} ->
          prev_tx
      end

    stamp = create_validation_stamp(tx, prev_tx, slot_time)

    %{tx | validation_stamp: stamp}
  end

  defp create_summary_transaction(subset, summary_time) do
    {prev_pub, prev_pv} = Crypto.derive_beacon_keypair(subset, summary_time)
    {pub, _} = Crypto.derive_beacon_keypair(subset, summary_time, true)

    beacon_chain =
      prev_pub
      |> Crypto.hash()
      |> TransactionChain.get()

    previous_slots =
      Stream.map(beacon_chain, fn %Transaction{data: %TransactionData{content: content}} ->
        {slot, _} = Slot.deserialize(content)
        slot
      end)

    tx_content =
      %Summary{subset: subset, summary_time: summary_time}
      |> Summary.aggregate_slots(previous_slots)
      |> Summary.serialize()

    tx =
      Transaction.new(
        :beacon_summary,
        %TransactionData{content: tx_content |> Utils.wrap_binary()},
        prev_pv,
        prev_pub,
        pub
      )

    stamp = create_validation_stamp(tx, nil, summary_time)

    [%{tx | validation_stamp: stamp}]
    |> Stream.concat(beacon_chain)
    |> TransactionChain.write()
  end

  defp create_validation_stamp(tx = %Transaction{}, nil, time = %DateTime{}) do
    %ValidationStamp{
      proof_of_work: Crypto.first_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: <<0::size(512)>>,
      timestamp: time
    }
    |> ValidationStamp.sign()
  end

  defp create_validation_stamp(tx = %Transaction{}, prev_tx = %Transaction{}, time = %DateTime{}) do
    %ValidationStamp{
      proof_of_work: Crypto.first_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx, prev_tx]),
      proof_of_election: <<0::size(512)>>,
      timestamp: time
    }
    |> ValidationStamp.sign()
  end
end
