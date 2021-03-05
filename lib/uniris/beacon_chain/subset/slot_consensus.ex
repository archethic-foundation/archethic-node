defmodule Uniris.BeaconChain.Subset.SlotConsensus do
  @moduledoc """
  Process a BeaconChain Slot by starting the consensus verification
  among the beacon slot storage nodes and notify the summary pool
  """

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.Crypto

  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.AddBeaconSlotProof
  alias Uniris.P2P.Message.NotifyBeaconSlot
  alias Uniris.P2P.Node

  alias Uniris.Utils

  require Logger

  use GenStateMachine, callback_mode: :handle_event_function

  @doc """
  Start the consensus worker
  """
  @spec start_link(list()) :: {:ok, pid()}
  def start_link(args \\ []) do
    GenStateMachine.start(__MODULE__, args)
  end

  @doc """
  Request validation of a beacon slot
  """
  @spec validate_and_notify_slot(pid(), Slot.t()) :: :ok
  def validate_and_notify_slot(pid, slot = %Slot{}) do
    GenStateMachine.cast(pid, {:validate_and_notify_slot, slot})
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
      GenStateMachine.cast(pid, {:add_slot_proof, slot_digest, node_public_key, signature})
    else
      {:error, :invalid_proof}
    end
  end

  def init(args) do
    node_public_key = Keyword.fetch!(args, :node_public_key)
    slot = Keyword.fetch!(args, :slot)
    timeout = Keyword.get(args, :timeout, 5_000)

    {:ok, :started, %{node_public_key: node_public_key, slot: slot, timeout: timeout},
     {:next_event, :internal, :validate_and_notify_slot}}
  end

  def handle_event(
        :internal,
        :validate_and_notify_slot,
        :started,
        data = %{
          node_public_key: node_public_key,
          slot: slot = %Slot{subset: subset, slot_time: slot_time},
          timeout: timeout
        }
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
        # Node is not ready or doesn't need it for now
        :stop

      node_pos ->
        nb_nodes = length(storage_nodes)

        current_slot = %{
          slot
          | involved_nodes: Utils.set_bitstring_bit(<<0::size(nb_nodes)>>, node_pos),
            validation_signatures: %{node_pos => Crypto.sign_with_node_key(digest)}
        }

        case storage_nodes do
          [%Node{first_public_key: ^node_public_key}] ->
            notify_summary_pool(current_slot)
            :stop

          _ ->
            new_data =
              data
              |> Map.put(:current_slot, current_slot)
              |> Map.put(:storage_nodes, storage_nodes)
              |> Map.put(:digest, digest)
              |> Map.put(:node_pos, node_pos)

            {:next_state, :waiting_proofs, new_data,
             {:state_timeout, timeout, :sync_to_summary_pool}}
        end
    end
  end

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
    case Enum.find_index(storage_nodes, &(&1.last_public_key == node_public_key)) do
      nil ->
        :keep_state_and_data

      node_pos ->
        new_slot =
          current_slot
          |> Map.update!(:involved_nodes, &Utils.set_bitstring_bit(&1, node_pos))
          |> Map.update!(:validation_signatures, &Map.put(&1, node_pos, signature))

        if map_size(new_slot.validation_signatures) == length(storage_nodes) do
          notify_summary_pool(current_slot)
          :stop
        else
          {:keep_state, Map.put(data, :current_slot, new_slot)}
        end
    end
  end

  def handle_event(
        :cast,
        {:add_slot_proof, _recv_digest, node_public_key, _remote_signature},
        :waiting_proofs,
        _data = %{
          current_slot: %Slot{subset: subset}
        }
      ) do
    Logger.warning("Different beacon slot from #{Base.encode16(node_public_key)}",
      beacon_subset: Base.encode16(subset)
    )

    :keep_state_and_data
  end

  def handle_event(:cast, {:add_slot_proof, _, _, _}, :started, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :state_timeout,
        :sync_to_summary_pool,
        :waiting_proofs,
        _data = %{current_slot: slot}
      ) do
    notify_summary_pool(slot)
    :stop
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
