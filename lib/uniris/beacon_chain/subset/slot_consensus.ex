defmodule Uniris.BeaconChain.Subset.SlotConsensus do
  @moduledoc """
  Process a BeaconChain Slot by starting the consensus verification
  among the beacon slot storage nodes and notify the summary pool
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.AddBeaconSlotProof
  alias Uniris.P2P.Message.GetCurrentBeaconSlot
  alias Uniris.P2P.Message.GetTransactionSummary
  alias Uniris.P2P.Message.NotifyBeaconSlot
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.Utils

  require Logger

  @doc """
  Start the consensus worker
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []) do
    :gen_statem.start_link(__MODULE__, args, [])
  end

  @doc """
  Request validation of a beacon slot
  """
  @spec validate_and_notify_slot(pid(), Slot.t()) :: :ok
  def validate_and_notify_slot(pid, slot = %Slot{}) do
    :gen_statem.cast(pid, {:validate_and_notify_slot, slot})
  end

  @doc """
  Add beacon slot proof to the consensus worker state.

  If enough valid proofs and signatures are received, the summary can be notified
  Otherwise a resync step is started excluding any malicious behavior
  for the invalid transaction summaries
  """
  @spec add_slot_proof(pid(), binary(), Crypto.key(), binary()) :: :ok | {:error, :invalid_proof}
  def add_slot_proof(pid, slot_digest, node_public_key, signature)
      when is_binary(slot_digest) and is_binary(node_public_key) and is_binary(signature) do
    if Crypto.verify(signature, slot_digest, node_public_key) do
      :gen_statem.cast(pid, {:add_slot_proof, slot_digest, node_public_key, signature})
    else
      {:error, :invalid_proof}
    end
  end

  def init(args) do
    node_public_key = Keyword.fetch!(args, :node_public_key)
    {:ok, :idle, %{node_public_key: node_public_key}}
  end

  def callback_mode do
    [:handle_event_function]
  end

  def handle_event(
        :cast,
        {:validate_and_notify_slot, slot = %Slot{subset: subset, slot_time: slot_time}},
        :idle,
        data = %{node_public_key: node_public_key}
      ) do
    storage_nodes =
      Election.beacon_storage_nodes(
        subset,
        slot_time,
        P2P.list_nodes(availability: :global),
        Election.get_storage_constraints()
      )

    digest = Slot.digest(slot)
    notify_digest(subset, digest, storage_nodes)

    case Enum.find_index(storage_nodes, &(&1.first_public_key == node_public_key)) do
      nil ->
        Logger.error("Not found")
        # Node is not ready or doesn't need it for now
        :keep_state_and_data

      node_pos ->
        current_slot = %{
          slot
          | involved_nodes:
              Range.new(1, length(storage_nodes))
              |> Enum.map(fn _ -> <<0::1>> end)
              |> :erlang.list_to_bitstring()
              |> Utils.set_bitstring_bit(node_pos),
            validation_signatures: [{node_pos, Crypto.sign_with_node_key(digest)}]
        }

        case storage_nodes do
          [%Node{first_public_key: ^node_public_key}] ->
            notify_summary_pool(current_slot)
            {:next_state, :idle, %{node_public_key: node_public_key}}

          _ ->
            new_data =
              data
              |> Map.put(:current_slot, current_slot)
              |> Map.put(:storage_nodes, storage_nodes)
              |> Map.put(:digest, digest)

            {:next_state, :waiting_proofs, new_data,
             {{:timeout, :sync_to_summary_pool}, 5_000, :any}}
        end
    end
  end

  def handle_event(
        :cast,
        {:validate_and_notify_slot, %Slot{}},
        _,
        _data
      ),
      do: {:keep_state_and_data, :postpone}

  def handle_event(
        :cast,
        {:add_slot_proof, recv_digest, node_public_key, signature},
        :waiting_proofs,
        data = %{
          digest: digest,
          storage_nodes: storage_nodes,
          current_slot: current_slot
        }
      )
      when digest == recv_digest do
    node_pos = Enum.find_index(storage_nodes, &(&1.last_public_key == node_public_key))

    new_slot =
      current_slot
      |> Map.update!(:involved_nodes, &Utils.set_bitstring_bit(&1, node_pos))
      |> Map.update!(:validation_signatures, fn validations ->
        Enum.uniq_by([{node_pos, signature} | validations], fn {pos, _} -> pos end)
      end)

    if length(new_slot.validation_signatures) == length(storage_nodes) do
      notify_summary_pool(current_slot)
      {:next_state, :idle, %{node_public_key: node_public_key}}
    else
      {:keep_state, Map.put(data, :current_slot, new_slot)}
    end
  end

  def handle_event(
        :cast,
        {:add_slot_proof, _recv_digest, node_public_key, _signature},
        :waiting_proofs,
        data = %{
          digest: _digest,
          storage_nodes: storage_nodes,
          current_slot: current_slot = %Slot{subset: subset}
        }
      ) do
    with node_pos when node_pos != nil <-
           Enum.find_index(storage_nodes, &(&1.last_public_key == node_public_key)),
         remote_node <- Enum.at(storage_nodes, node_pos),
         remote_slot <- P2P.send_message!(remote_node, %GetCurrentBeaconSlot{subset: subset}),
         {:ok, new_slot} <- handle_conflicts(current_slot, remote_slot) do
      notify_digest(subset, Slot.serialize(new_slot), storage_nodes)

      new_slot = Map.update!(new_slot, :involved_nodes, &Utils.set_bitstring_bit(&1, node_pos))

      {:keep_state, Map.put(data, :current_slot, new_slot)}
    else
      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:cast, {:add_slot_proof, _, _, _}, :idle, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        {:timeout, :sync_to_summary_pool},
        :any,
        _state,
        _data = %{current_slot: slot, node_public_key: node_public_key}
      ) do
    notify_summary_pool(slot)
    {:next_state, :idle, %{node_public_key: node_public_key}}
  end

  defp handle_conflicts(
         %Slot{previous_hash: current_previous_hash},
         %Slot{previous_hash: recv_previous_hash}
       )
       when current_previous_hash != recv_previous_hash,
       do: {:error, :invalid_hash}

  defp handle_conflicts(
         %Slot{subset: current_subset},
         %Slot{subset: recv_subset}
       )
       when current_subset != recv_subset,
       do: {:error, :invalid_subset}

  defp handle_conflicts(
         current_slot = %Slot{slot_time: current_slot_time = %DateTime{}},
         recv_slot = %Slot{slot_time: recv_slot_time = %DateTime{}}
       ) do
    if DateTime.diff(current_slot_time, recv_slot_time) >= 3 do
      {:error, :invalid_slot_time}
    else
      diff_transaction_summaries = get_diff_transaction_summaries(current_slot, recv_slot)
      handle_diff_transaction_summaries(current_slot, diff_transaction_summaries)
    end
  end

  defp get_diff_transaction_summaries(%Slot{transaction_summaries: local_summaries}, %Slot{
         transaction_summaries: remote_summaries
       }),
       do: Enum.filter(remote_summaries, &(!Enum.member?(local_summaries, &1)))

  defp handle_diff_transaction_summaries(current_slot = %Slot{}, []), do: {:ok, current_slot}

  defp handle_diff_transaction_summaries(current_slot = %Slot{}, diff) when is_list(diff) do
    case get_valid_diff_transaction_summaries(diff) do
      [] ->
        {:error, :invalid_transactions}

      valid_tx_summaries ->
        {:ok, Map.update!(current_slot, :transaction_summaries, &(&1 ++ valid_tx_summaries))}
    end
  end

  defp notify_digest(subset, digest, storage_nodes) do
    signature = Crypto.sign_with_node_key(digest)

    storage_nodes
    |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
    |> P2P.broadcast_message(%AddBeaconSlotProof{
      subset: subset,
      digest: digest,
      public_key: Crypto.node_public_key(),
      signature: signature
    })
  end

  defp get_valid_diff_transaction_summaries(summaries) do
    Enum.map(summaries, fn summary = %TransactionSummary{address: address} ->
      storage_nodes =
        Replication.chain_storage_nodes(address, P2P.list_nodes(availability: :global))

      case P2P.reply_first(storage_nodes, %GetTransactionSummary{address: address}) do
        {:ok, ^summary = %TransactionSummary{}} ->
          summary

        _ ->
          nil
      end
    end)
    |> Enum.reject(&match?(nil, &1))
  end

  defp notify_summary_pool(current_slot = %Slot{subset: subset}) do
    next_summary_time = SummaryTimer.next_summary(DateTime.utc_now())

    subset
    |> Election.beacon_storage_nodes(
      next_summary_time,
      P2P.list_nodes(availability: :global),
      Election.get_storage_constraints()
    )
    |> P2P.broadcast_message(%NotifyBeaconSlot{slot: current_slot})
  end
end
