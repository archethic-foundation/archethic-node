defmodule Archethic.BeaconChain.Slot.Validation do
  @moduledoc false

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetTransactionSummary
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain.TransactionSummary

  require Logger

  @doc """
  Validate the transaction attestations to ensure the transactions included really exists
  """
  @spec valid_transaction_attestations?(Slot.t()) :: boolean()
  def valid_transaction_attestations?(%Slot{transaction_attestations: transaction_attestations}) do
    Task.Supervisor.async_stream(
      TaskSupervisor,
      transaction_attestations,
      &valid_transaction_attestation/1,
      ordered: false,
      on_timeout: :kill_task
    )
    |> Enum.all?(&match?({:ok, true}, &1))
  end

  defp valid_transaction_attestation(
         attestation = %ReplicationAttestation{
           transaction_summary:
             tx_summary = %TransactionSummary{
               address: address,
               timestamp: timestamp,
               type: tx_type
             }
         }
       ) do
    storage_nodes = transaction_storage_nodes(address, timestamp)

    with :ok <-
           ReplicationAttestation.validate(attestation),
         :ok <- check_transaction_summary(storage_nodes, tx_summary) do
      true
    else
      {:error, reason} ->
        Logger.debug("Invalid attestation #{inspect(reason)} - #{inspect(attestation)}",
          transaction_address: Base.encode16(address),
          transaction_type: tx_type
        )

        false
    end
  end

  defp check_transaction_summary(nodes, expected_summary, timeout \\ 500)

  defp check_transaction_summary([], _, _), do: {:error, :network_issue}

  defp check_transaction_summary(
         nodes,
         expected_summary = %TransactionSummary{
           address: address,
           type: type
         },
         _timeout
       ) do
    conflict_resolver = fn results ->
      case Enum.find(results, &match?(%TransactionSummary{address: ^address, type: ^type}, &1)) do
        nil ->
          %NotFound{}

        tx_summary ->
          tx_summary
      end
    end

    case P2P.quorum_read(
           nodes,
           %GetTransactionSummary{address: address},
           conflict_resolver
         ) do
      {:ok, ^expected_summary} ->
        :ok

      {:ok, recv = %TransactionSummary{}} ->
        Logger.warning(
          "Transaction summary received is different #{inspect(recv)} - expect #{inspect(expected_summary)}",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

      {:ok, %NotFound{}} ->
        Logger.warning("Transaction summary was not found",
          transaction_address: Base.encode16(address),
          transaction_type: type
        )

        {:error, :invalid_summary}

      {:error, :network_issue} ->
        {:error, :network_issue}
    end
  end

  defp transaction_storage_nodes(address, timestamp) do
    authorized_nodes =
      case P2P.authorized_nodes(timestamp) do
        [] ->
          # Should only happen during bootstrap
          P2P.authorized_nodes()

        nodes ->
          Enum.filter(nodes, & &1.available?)
      end

    address
    # We are targeting the authorized nodes from the transaction validation to increase consistency and some guarantee
    |> Election.chain_storage_nodes(authorized_nodes)
    |> P2P.nearest_nodes()
    |> Enum.filter(&Node.locally_available?/1)
    |> P2P.unprioritize_node(Crypto.first_node_public_key())
  end

  @doc """
  Validate the end of node synchronization to ensure the list of nodes exists
  """
  @spec valid_end_of_node_sync?(Slot.t()) :: boolean
  def valid_end_of_node_sync?(%Slot{end_of_node_synchronizations: end_of_node_sync}) do
    Enum.all?(end_of_node_sync, fn %EndOfNodeSync{public_key: key} ->
      match?({:ok, %Node{first_public_key: ^key}}, P2P.get_node_info(key))
    end)
  end
end
