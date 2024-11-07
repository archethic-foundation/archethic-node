defmodule Archethic.Replication.TransactionValidator do
  @moduledoc false

  alias Archethic.Election
  alias Archethic.Mining.Error
  alias Archethic.Mining.ValidationContext
  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.SharedSecrets
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp

  require Logger

  @doc """
  Validate transaction with context

  This function is called by the chain replication nodes
  """
  @spec validate(validation_context :: ValidationContext.t()) :: ValidationContext.t()
  def validate(validation_context) do
    validation_context
    |> validate_consensus()
    |> ValidationContext.validate_pending_transaction()
    |> ValidationContext.cross_validate()
  end

  @doc """
  Validate transaction only (without chain integrity or unspent outputs)

  This function called by the replication nodes which are involved in the io storage
  """
  @spec validate_consensus(context :: ValidationContext.t()) :: ValidationContext.t()
  def validate_consensus(context) do
    context
    |> validate_atomic_commitment()
    |> validate_cross_validation_stamps_inconsistencies()
    |> validate_proof_of_work()
    |> validate_node_election()
    |> validate_no_additional_error()
  end

  defp validate_atomic_commitment(context = %ValidationContext{mining_error: %Error{}}),
    do: context

  defp validate_atomic_commitment(context = %ValidationContext{transaction: tx}) do
    if Transaction.atomic_commitment?(tx) do
      context
    else
      ValidationContext.set_mining_error(
        context,
        Error.new(:consensus_not_reached, "Invalid atomic commitment")
      )
    end
  end

  defp validate_cross_validation_stamps_inconsistencies(
         context = %ValidationContext{mining_error: %Error{}}
       ),
       do: context

  defp validate_cross_validation_stamps_inconsistencies(
         context = %ValidationContext{transaction: %Transaction{cross_validation_stamps: stamps}}
       ) do
    if Enum.all?(stamps, &(&1.inconsistencies == [])) do
      context
    else
      Logger.error("Inconsistencies: #{inspect(Enum.map(stamps, & &1.inconsistencies))}")

      error_data =
        stamps
        |> Enum.flat_map(& &1.inconsistencies)
        |> Enum.uniq()
        |> Enum.map(&(&1 |> Atom.to_string() |> String.replace("_", " ")))

      ValidationContext.set_mining_error(context, Error.new(:consensus_not_reached, error_data))
    end
  end

  defp validate_proof_of_work(context = %ValidationContext{mining_error: %Error{}}), do: context

  defp validate_proof_of_work(
         context = %ValidationContext{
           transaction: tx = %Transaction{validation_stamp: %ValidationStamp{proof_of_work: pow}}
         }
       ) do
    if Transaction.verify_origin_signature?(tx, pow) do
      context
    else
      Logger.error("Invalid proof of work #{Base.encode16(pow)}",
        transaction_address: Base.encode16(tx.address),
        transaction_type: tx.type
      )

      ValidationContext.set_mining_error(
        context,
        Error.new(:consensus_not_reached, "Invalid proof of work")
      )
    end
  end

  defp validate_node_election(context = %ValidationContext{mining_error: %Error{}}), do: context

  defp validate_node_election(
         context = %ValidationContext{
           transaction:
             tx = %Transaction{
               address: tx_address,
               validation_stamp: %ValidationStamp{
                 timestamp: tx_timestamp,
                 proof_of_election: proof_of_election
               }
             },
           validation_stamp: stamp
         }
       ) do
    authorized_nodes = P2P.authorized_and_available_nodes(tx_timestamp)

    daily_nonce_public_key = SharedSecrets.get_daily_nonce_public_key(tx_timestamp)

    case authorized_nodes do
      [] ->
        # Should happens only during the network bootstrapping
        if daily_nonce_public_key == SharedSecrets.genesis_daily_nonce_public_key() do
          %ValidationContext{context | coordinator_node: P2P.get_node_info()}
        else
          ValidationContext.set_mining_error(
            context,
            Error.new(:consensus_not_reached, "Invalid election")
          )
        end

      _ ->
        storage_nodes = Election.chain_storage_nodes(tx_address, authorized_nodes)

        validation_nodes =
          Election.validation_nodes(
            tx,
            proof_of_election,
            authorized_nodes,
            storage_nodes,
            Election.get_validation_constraints()
          )

        validation_nodes_mining_key =
          Enum.map(validation_nodes, fn %Node{mining_public_key: mining_public_key} ->
            [mining_public_key]
          end)

        if Transaction.valid_stamps_signature?(tx, validation_nodes_mining_key) do
          coordinator_key =
            validation_nodes_mining_key
            |> List.flatten()
            |> Enum.find(&ValidationStamp.valid_signature?(stamp, &1))

          coordinator_node =
            Enum.find(validation_nodes, fn
              %Node{mining_public_key: ^coordinator_key} -> true
              _ -> false
            end)

          %ValidationContext{context | coordinator_node: coordinator_node}
        else
          ValidationContext.set_mining_error(
            context,
            Error.new(:consensus_not_reached, "Invalid election")
          )
        end
    end
  end

  defp validate_no_additional_error(context = %ValidationContext{mining_error: %Error{}}),
    do: context

  defp validate_no_additional_error(
         context = %ValidationContext{
           transaction: %Transaction{validation_stamp: %ValidationStamp{error: nil}}
         }
       ),
       do: context

  defp validate_no_additional_error(
         context = %ValidationContext{
           transaction: tx = %Transaction{validation_stamp: %ValidationStamp{error: error}}
         }
       ) do
    Logger.info(
      "Contains errors: #{inspect(error)}",
      transaction_address: Base.encode16(tx.address),
      transaction_type: tx.type
    )

    ValidationContext.set_mining_error(context, Error.new(error))
  end
end
