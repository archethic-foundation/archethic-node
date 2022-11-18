defmodule Archethic.BeaconChain.Slot.Validation do
  @moduledoc false

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Slot.EndOfNodeSync

  alias Archethic.P2P
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
           transaction_summary: %TransactionSummary{
             address: address,
             type: tx_type
           }
         }
       ) do
    case ReplicationAttestation.validate(attestation) do
      :ok ->
        true

      {:error, reason} ->
        Logger.debug("Invalid attestation #{inspect(reason)} - #{inspect(attestation)}",
          transaction_address: Base.encode16(address),
          transaction_type: tx_type
        )

        false
    end
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
