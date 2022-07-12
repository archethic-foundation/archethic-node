defmodule Archethic.BeaconChain.Subset do
  @moduledoc """
  Represents a beacon slot running inside a process
  waiting to receive transactions to register in a beacon slot
  """

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync
  alias Archethic.BeaconChain.SlotTimer
  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryTimer

  alias __MODULE__.P2PSampling
  alias __MODULE__.SummaryCache

  alias Archethic.BeaconChain.SubsetRegistry

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.NewBeaconTransaction
  alias Archethic.P2P.Message.BeaconUpdate

  alias Archethic.PubSub

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

  use GenServer

  require Logger

  def start_link(opts) do
    subset = Keyword.get(opts, :subset)
    GenServer.start_link(__MODULE__, [subset], name: via_tuple(subset))
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
    PubSub.register_to_new_replication_attestations()

    {:ok,
     %{
       node_public_key: Crypto.first_node_public_key(),
       subset: subset,
       current_slot: %Slot{subset: subset, slot_time: SlotTimer.next_slot(DateTime.utc_now())},
       subscribed_nodes: [],
       postponed: %{end_of_sync: [], transaction_attestations: []}
     }}
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
        {:subscribe_node_to_beacon_updates, node_public_key},
        state = %{subscribed_nodes: current_list_of_subscribed_nodes, current_slot: current_slot}
      ) do
    %Slot{transaction_attestations: transaction_attestations} = current_slot

    if !Enum.empty?(transaction_attestations) do
      P2P.send_message(node_public_key, %BeaconUpdate{
        transaction_attestations: transaction_attestations
      })
    end

    updated_list_of_subscribed_nodes =
      if Enum.member?(current_list_of_subscribed_nodes, node_public_key) do
        current_list_of_subscribed_nodes
      else
        [node_public_key | current_list_of_subscribed_nodes]
      end

    {:noreply, %{state | subscribed_nodes: updated_list_of_subscribed_nodes}}
  end

  def handle_info(
        {:create_slot, time},
        state = %{subset: subset, node_public_key: node_public_key, current_slot: current_slot}
      ) do
    if beacon_slot_node?(subset, time, node_public_key) do
      handle_slot(time, current_slot)

      if summary_time?(time) and beacon_summary_node?(subset, time, node_public_key) do
        handle_summary(time, subset)
      end
    end

    {:noreply, next_state(state, time)}
  end

  def handle_info(
        {:new_replication_attestation,
         attestation = %ReplicationAttestation{
           transaction_summary: %TransactionSummary{
             address: address,
             type: type,
             timestamp: timestamp
           }
         }},
        state = %{
          current_slot: current_slot = %Slot{slot_time: slot_time},
          subset: subset,
          subscribed_nodes: subscribed_nodes
        }
      ) do
    with ^subset <- BeaconChain.subset_from_address(address),
         ^slot_time <- SlotTimer.next_slot(timestamp) do
      {new_tx?, new_slot} =
        Slot.add_transaction_attestation(
          current_slot,
          attestation
        )

      if new_tx? do
        Logger.info(
          "Transaction #{type}@#{Base.encode16(address)} added to the beacon chain (in #{DateTime.to_string(slot_time)} slot)",
          beacon_subset: Base.encode16(subset)
        )

        notify_subscribed_nodes(subscribed_nodes, attestation)
      else
        Logger.info(
          "New confirmation for transaction #{type}@#{Base.encode16(address)} added to the beacon chain (in #{DateTime.to_string(slot_time)} slot)",
          beacon_subset: Base.encode16(subset)
        )
      end

      # Request the P2P view sampling if the not perfomed from the last 3 seconds
      if update_p2p_view?(state) do
        new_state =
          state
          |> Map.put(:current_slot, add_p2p_view(new_slot))
          |> Map.put(:sampling_time, DateTime.utc_now())

        {:noreply, new_state}
      else
        {:noreply, %{state | current_slot: new_slot}}
      end
    else
      next_slot_time = %DateTime{} ->
        new_state = update_in(state, [:postponed, :transaction_attestations], &[attestation | &1])

        Logger.info(
          "Transaction #{type}@#{Base.encode16(address)} will be added to the next beacon chain (#{DateTime.to_string(next_slot_time)} slot)",
          beacon_subset: Base.encode16(subset)
        )

        notify_subscribed_nodes(subscribed_nodes, attestation)

        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  defp notify_subscribed_nodes(nodes, %ReplicationAttestation{
         transaction_summary:
           tx_summary = %TransactionSummary{timestamp: timestamp, address: address}
       }) do
    PubSub.notify_transaction_attestation(tx_summary)

    # Do not notify beacon storage nodes as they are already aware of the transaction
    beacon_storage_nodes =
      Election.beacon_storage_nodes(
        BeaconChain.subset_from_address(address),
        BeaconChain.next_slot(timestamp),
        P2P.authorized_nodes(timestamp)
      )
      |> Enum.map(& &1.first_public_key)

    nodes
    |> P2P.get_nodes_info()
    |> Enum.reject(&Enum.member?(beacon_storage_nodes, &1.first_public_key))
    |> P2P.broadcast_message(tx_summary)
  end

  defp handle_slot(
         time,
         current_slot = %Slot{subset: subset}
       ) do
    current_slot = ensure_p2p_view(current_slot)

    # Avoid to store or dispatch an empty beacon's slot
    unless Slot.empty?(current_slot) do
      current_slot = %{current_slot | slot_time: SlotTimer.previous_slot(time)}

      beacon_transaction = create_beacon_transaction(current_slot)

      if summary_time?(time) do
        genesis_address =
          Crypto.derive_beacon_chain_address(subset, SummaryTimer.previous_summary(time))

        TransactionChain.write_transaction_at(beacon_transaction, genesis_address)
        SummaryCache.add_slot(subset, current_slot)
      else
        next_time = SlotTimer.next_slot(time)
        broadcast_beacon_transaction(subset, next_time, beacon_transaction)
      end
    end
  end

  defp update_p2p_view?(%{sampling_time: time}) do
    DateTime.diff(DateTime.utc_now(), time) > 3
  end

  defp update_p2p_view?(_), do: true

  defp next_state(
         state = %{
           subset: subset,
           postponed: %{
             transaction_attestations: transaction_attestations,
             end_of_sync: end_of_sync
           }
         },
         time
       ) do
    next_time = SlotTimer.next_slot(time)

    state
    |> Map.put(
      :current_slot,
      %Slot{
        subset: subset,
        slot_time: next_time,
        transaction_attestations: transaction_attestations,
        end_of_node_synchronizations: end_of_sync
      }
    )
    |> Map.put(:postponed, %{transaction_attestations: [], end_of_sync: []})
    |> Map.put(
      :subscribed_nodes,
      []
    )
  end

  defp broadcast_beacon_transaction(subset, next_time, transaction) do
    subset
    |> Election.beacon_storage_nodes(next_time, P2P.authorized_and_available_nodes())
    |> P2P.broadcast_message(%NewBeaconTransaction{transaction: transaction})
  end

  defp handle_summary(time, subset) do
    beacon_slots = SummaryCache.pop_slots(subset)

    if Enum.empty?(beacon_slots) do
      :ok
    else
      Logger.debug("Create beacon summary with #{inspect(beacon_slots, limit: :infinity)}",
        beacon_subset: Base.encode16(subset)
      )

      genesis_address =
        Crypto.derive_beacon_chain_address(subset, SummaryTimer.previous_summary(time))

      beacon_slots
      |> create_summary_transaction(subset, time)
      |> TransactionChain.write_transaction_at(genesis_address)
    end
  end

  defp summary_time?(time) do
    SummaryTimer.match_interval?(DateTime.truncate(time, :millisecond))
  end

  defp beacon_slot_node?(subset, slot_time, node_public_key) do
    %Slot{subset: subset, slot_time: slot_time}
    |> Slot.involved_nodes()
    |> Utils.key_in_node_list?(node_public_key)
  end

  defp beacon_summary_node?(subset, summary_time, node_public_key) do
    node_list = P2P.authorized_nodes(summary_time)

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
    {prev_pub, prev_pv} = Crypto.derive_beacon_keypair(subset, slot_time)
    {next_pub, _} = Crypto.derive_beacon_keypair(subset, slot_time)

    slot_content =
      slot
      |> Slot.serialize()
      |> Utils.wrap_binary()

    tx =
      Transaction.new_with_keys(
        :beacon,
        %TransactionData{content: slot_content},
        prev_pv,
        prev_pub,
        next_pub
      )

    stamp =
      %ValidationStamp{
        timestamp: slot_time,
        proof_of_election: <<0::size(512)>>,
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        proof_of_work: Crypto.first_node_public_key()
      }
      |> ValidationStamp.sign()

    %{tx | validation_stamp: stamp}
  end

  defp create_summary_transaction(beacon_slots, subset, summary_time) do
    {prev_pub, prev_pv} = Crypto.derive_beacon_keypair(subset, summary_time)
    {pub, _} = Crypto.derive_beacon_keypair(subset, summary_time, true)

    tx_content =
      %Summary{subset: subset, summary_time: summary_time}
      |> Summary.aggregate_slots(beacon_slots, P2PSampling.list_nodes_to_sample(subset))
      |> Summary.serialize()

    tx =
      Transaction.new_with_keys(
        :beacon_summary,
        %TransactionData{content: tx_content |> Utils.wrap_binary()},
        prev_pv,
        prev_pub,
        pub
      )

    stamp =
      %ValidationStamp{
        timestamp: summary_time,
        proof_of_election: <<0::size(512)>>,
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        proof_of_work: Crypto.first_node_public_key()
      }
      |> ValidationStamp.sign()

    %{tx | validation_stamp: stamp}
  end

  @doc """
  Add node public key to the corresponding subset for beacon updates
  """
  @spec subscribe_for_beacon_updates(binary(), Crypto.key()) :: :ok
  def subscribe_for_beacon_updates(subset, node_public_key) do
    GenServer.cast(via_tuple(subset), {:subscribe_node_to_beacon_updates, node_public_key})
  end
end
