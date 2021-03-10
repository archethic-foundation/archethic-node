defmodule Uniris.BeaconChain.SummaryValidation do
  @moduledoc false

  alias Uniris.BeaconChain.Slot
  alias Uniris.BeaconChain.Slot.EndOfNodeSync
  alias Uniris.BeaconChain.Slot.TransactionSummary
  alias Uniris.BeaconChain.SlotTimer
  alias Uniris.BeaconChain.SummaryTimer

  alias Uniris.DB

  alias Uniris.Crypto
  alias Uniris.Election

  alias Uniris.P2P
  alias Uniris.P2P.Message.GetTransactionSummary
  alias Uniris.P2P.Node

  alias Uniris.Replication

  alias Uniris.Utils

  @doc """
  Determines if the node is a storage node for the beacon summary
  """
  @spec storage_node?(Slot.t()) :: boolean()
  def storage_node?(%Slot{subset: subset, slot_time: slot_time}) do
    summary_time = SummaryTimer.next_summary(slot_time)
    Utils.key_in_node_list?(slot_storage_nodes(subset, summary_time), Crypto.node_public_key(0))
  end

  @doc """
  Determines if slot previous hash is valid.

  Without previous slots, it expects to be the genesis one
  Otherwise the previous slot will be compared
  """
  @spec valid_previous_hash?(Slot.t()) :: boolean()
  def valid_previous_hash?(%Slot{previous_hash: hash, subset: subset, slot_time: slot_time}) do
    previous_slot_time = SlotTimer.previous_slot(slot_time)

    case DB.get_beacon_slot(subset, previous_slot_time) do
      {:ok, slot} ->
        previous_hash =
          slot
          |> Slot.serialize()
          |> Crypto.hash()

        hash == previous_hash

      {:error, :not_found} ->
        hash == Slot.genesis_previous_hash()
    end
  end

  @doc """
  Determines if all the signatures from the beacon slot are valid according to the list of involved nodes.

  Each involved node is retrieved by performing a lookup to find out
  the storage node public key based on the position of the bits

  By checking all we are ensuring the atomic commitment of the beacon slot creation
  """
  @spec valid_signatures?(Slot.t()) :: boolean()
  def valid_signatures?(
        slot = %Slot{
          slot_time: slot_time,
          subset: subset,
          validation_signatures: validation_signatures
        }
      ) do
    storage_nodes =
      subset
      |> slot_storage_nodes(slot_time)
      |> Enum.map(& &1.last_public_key)

    Enum.all?(validation_signatures, fn {pos, signature} ->
      case Enum.at(storage_nodes, pos) do
        nil ->
          false

        node_key ->
          Crypto.verify(signature, Slot.digest(slot), node_key)
      end
    end)
  end

  defp slot_storage_nodes(subset, slot_time) do
    subset
    |> Election.beacon_storage_nodes(
      slot_time,
      P2P.list_nodes(availability: :global),
      Election.get_storage_constraints()
    )
    |> Enum.filter(&(DateTime.compare(&1.enrollment_date, slot_time) == :lt))
  end

  @doc """
  Validate the transaction summaries to ensure the transactions included really exists
  """
  @spec valid_transaction_summaries?(list(TransactionSummary.t())) :: boolean
  def valid_transaction_summaries?(transaction_summaries) when is_list(transaction_summaries) do
    Task.async_stream(transaction_summaries, &do_valid_transaction_summary/1, ordered: false)
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.all?(&match?(true, &1))
  end

  defp do_valid_transaction_summary(
         summary = %TransactionSummary{address: address, timestamp: timestamp}
       ) do
    case transaction_summary_storage_nodes(address, timestamp) do
      [] ->
        true

      nodes ->
        case P2P.reply_first(nodes, %GetTransactionSummary{address: address}) do
          {:ok, ^summary} ->
            true

          _ ->
            false
        end
    end
  end

  defp transaction_summary_storage_nodes(address, timestamp) do
    address
    |> Replication.chain_storage_nodes(P2P.list_nodes(availability: :global))
    |> Enum.filter(fn %Node{enrollment_date: enrollment_date} ->
      previous_summary_time = SummaryTimer.previous_summary(timestamp)

      diff = DateTime.compare(Utils.truncate_datetime(enrollment_date), previous_summary_time)

      diff == :lt or diff == :eq
    end)
    |> Enum.reject(&(&1.first_public_key == Crypto.node_public_key(0)))
  end

  @doc """
  Validate the end of node synchronization to ensure the list of nodes exists
  """
  @spec valid_end_of_node_sync?(list(EndOfNodeSync.t())) :: boolean
  def valid_end_of_node_sync?(end_of_node_sync) when is_list(end_of_node_sync) do
    Enum.all?(end_of_node_sync, fn %EndOfNodeSync{public_key: key} ->
      match?({:ok, %Node{first_public_key: ^key}}, P2P.get_node_info(key))
    end)
  end
end
