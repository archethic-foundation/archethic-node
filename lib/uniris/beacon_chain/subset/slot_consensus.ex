defmodule Uniris.BeaconChain.Subset.SlotConsensus do
  @moduledoc """
  Process a BeaconChain Slot by starting the consensus verification
  among the beacon slot storage nodes and notify the summary pool
  """

  alias Uniris.BeaconChain.Slot

  alias Uniris.Crypto

  alias Uniris.P2P
  alias Uniris.P2P.Message.AddBeaconSlot
  alias Uniris.P2P.Message.NotifyBeaconSlot
  alias Uniris.P2P.Node

  alias Uniris.Utils

  require Logger

  use GenStateMachine, callback_mode: :handle_event_function

  @doc """
  Start the consensus worker
  """
  @spec start_link(list()) :: GenStateMachine.on_start()
  def start_link(args \\ []) do
    GenStateMachine.start_link(__MODULE__, args)
  end

  @doc """
  Add beacon slot coming from a remote node

  If enough valid proofs and signatures are received, the summary can be notified
  """
  @spec add_remote_slot(pid(), Slot.t(), Crypto.key(), binary()) :: :ok
  def add_remote_slot(pid, slot = %Slot{}, node_public_key, signature)
      when is_binary(node_public_key) and is_binary(signature) do
    GenStateMachine.cast(pid, {:add_remote_slot, slot, node_public_key, signature})
  end

  def init(args) do
    node_public_key = Keyword.fetch!(args, :node_public_key)
    slot = Keyword.fetch!(args, :slot)
    timeout = Keyword.get(args, :timeout, 5_000)

    {:ok, :started, %{node_public_key: node_public_key, current_slot: slot, timeout: timeout},
     {:next_event, :internal, :sign_and_notify_slot}}
  end

  def handle_event(
        :internal,
        :sign_and_notify_slot,
        :started,
        data = %{
          node_public_key: node_public_key,
          current_slot: slot = %Slot{},
          timeout: timeout
        }
      ) do
    storage_nodes = Slot.involved_nodes(slot)
    signature = slot |> Slot.to_pending() |> Slot.serialize() |> Crypto.sign_with_node_key()
    notify_slot(storage_nodes, slot, node_public_key, signature)

    node_pos = Enum.find_index(storage_nodes, &(&1.first_public_key == node_public_key))
    nb_nodes = length(storage_nodes)

    current_slot = %{
      slot
      | involved_nodes: Utils.set_bitstring_bit(<<0::size(nb_nodes)>>, node_pos),
        validation_signatures: %{node_pos => signature}
    }

    case storage_nodes do
      [%Node{first_public_key: ^node_public_key}] ->
        notify_summary_pool(slot)
        :stop

      _ ->
        new_data =
          data
          |> Map.put(:current_slot, current_slot)
          |> Map.put(:storage_nodes, storage_nodes)

        {:next_state, :waiting_slots, new_data, {:state_timeout, timeout, :sync_to_summary_pool}}
    end
  end

  def handle_event(
        :cast,
        {:add_remote_slot, slot = %Slot{}, node_public_key, signature},
        :waiting_slots,
        data = %{
          storage_nodes: storage_nodes,
          current_slot: current_slot
        }
      ) do
    digest =
      slot
      |> Slot.to_pending()
      |> Slot.serialize()

    with node_pos when node_pos != nil <-
           Enum.find_index(storage_nodes, &(&1.last_public_key == node_public_key)),
         true <- Crypto.verify(signature, digest, node_public_key),
         {:ok, new_slot} <- resolve_conflicts(current_slot, slot) do
      new_slot =
        new_slot
        |> Map.update!(:involved_nodes, &Utils.set_bitstring_bit(&1, node_pos))
        |> Map.update!(:validation_signatures, &Map.put(&1, node_pos, signature))

      if map_size(new_slot.validation_signatures) == length(storage_nodes) do
        notify_summary_pool(current_slot)
        :stop
      else
        {:keep_state, Map.put(data, :current_slot, new_slot)}
      end
    else
      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:cast, {:add_remote_slot, _, _, _}, :started, _),
    do: {:keep_state_and_data, :postpone}

  def handle_event(
        :state_timeout,
        :sync_to_summary_pool,
        :waiting_slots,
        _data = %{current_slot: slot}
      ) do
    notify_summary_pool(slot)
    :stop
  end

  defp resolve_conflicts(current, remote) do
    # TODO: check if the transaction summaries are correct

    slot = resolve_p2p_differences(current, remote)
    {:ok, slot}
  end

  defp resolve_p2p_differences(
         current = %Slot{
           p2p_view: %{availabilities: current_availaiblities, network_stats: current_net_stats}
         },
         _incoming = %Slot{
           p2p_view: %{availabilities: incoming_availabilities, network_stats: incoming_net_stats}
         }
       ) do
    new_availabilities =
      Utils.aggregate_bitstring(current_availaiblities, incoming_availabilities)

    if length(current_net_stats) == length(incoming_net_stats) do
      %{
        current
        | p2p_view: %{
            availabilities: new_availabilities,
            network_stats: resolve_network_stats(current_net_stats, incoming_net_stats, [])
          }
      }
    else
      current
    end
  end

  defp resolve_network_stats(
         [%{latency: latency_a} | tail_a],
         [%{latency: latency_b} | tail_b],
         acc
       )
       when latency_a > latency_b do
    resolve_network_stats(tail_a, tail_b, [%{latency: latency_a} | acc])
  end

  defp resolve_network_stats(
         [%{latency: latency_a} | tail_a],
         [%{latency: latency_b} | tail_b],
         acc
       )
       when latency_a < latency_b do
    resolve_network_stats(tail_a, tail_b, [%{latency: latency_b} | acc])
  end

  defp resolve_network_stats(
         [%{latency: latency_a} | tail_a],
         [%{latency: latency_b} | tail_b],
         acc
       )
       when latency_a == latency_b do
    resolve_network_stats(tail_a, tail_b, [%{latency: latency_a} | acc])
  end

  defp resolve_network_stats([], [], acc), do: Enum.reverse(acc)

  defp notify_slot(storage_nodes, slot, node_public_key, signature) do
    storage_nodes
    |> Enum.reject(&(&1.first_public_key == node_public_key))
    |> P2P.broadcast_message(%AddBeaconSlot{
      slot: slot,
      public_key: node_public_key,
      signature: signature
    })
  end

  defp notify_summary_pool(current_slot = %Slot{subset: subset}) do
    current_slot
    |> Slot.summary_storage_nodes()
    |> P2P.broadcast_message(%NotifyBeaconSlot{slot: current_slot})

    Logger.debug("Notified summary: #{inspect(current_slot)}",
      beacon_subset: Base.encode16(subset)
    )
  end
end
