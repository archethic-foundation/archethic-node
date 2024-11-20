defmodule Archethic.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction, :genesis_address]
  defstruct [:transaction, :genesis_address]

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.Replication
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.Transaction.ProofOfReplication
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          genesis_address: Crypto.prepended_hash()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          transaction:
            tx = %Transaction{
              address: tx_address,
              validation_stamp: stamp = %ValidationStamp{timestamp: validation_time},
              proof_of_validation: proof_of_validation,
              proof_of_replication: proof_of_replication
            },
          genesis_address: genesis_address
        },
        _
      ) do
    validation_elected_nodes =
      validation_time
      |> P2P.authorized_and_available_nodes()
      |> ProofOfValidation.get_election(tx_address)

    replication_elected_nodes =
      validation_time
      |> P2P.authorized_and_available_nodes()
      |> ProofOfReplication.get_election(tx_address)

    tx_summary = TransactionSummary.from_transaction(tx, genesis_address)

    with true <- ProofOfValidation.valid?(validation_elected_nodes, proof_of_validation, stamp),
         true <-
           ProofOfReplication.valid?(replication_elected_nodes, proof_of_replication, tx_summary) do
      Task.Supervisor.start_child(Archethic.task_supervisors(), fn ->
        replicate_transaction(tx, genesis_address)
      end)
    end

    %Ok{}
  end

  defp replicate_transaction(
         tx = %Transaction{
           address: address,
           type: type,
           validation_stamp: %ValidationStamp{timestamp: validation_time}
         },
         genesis_address
       ) do
    authorized_nodes = P2P.authorized_and_available_nodes(validation_time)
    node_public_key = Crypto.first_node_public_key()

    cond do
      Transaction.network_type?(type) ->
        Replication.validate_and_store_transaction(tx, genesis_address, chain?: true)

      Election.chain_storage_node?(genesis_address, node_public_key, authorized_nodes) ->
        Replication.validate_and_store_transaction(tx, genesis_address, chain?: true)

      Election.chain_storage_node?(address, node_public_key, authorized_nodes) ->
        Replication.validate_and_store_transaction(tx, genesis_address, chain?: true)

      io_node?(tx, node_public_key, authorized_nodes) ->
        Replication.validate_and_store_transaction(tx, genesis_address, chain?: false)

      true ->
        :skip
    end
  end

  defp io_node?(
         %Transaction{
           validation_stamp: %ValidationStamp{
             ledger_operations: %LedgerOperations{transaction_movements: transaction_movements},
             recipients: recipients
           }
         },
         node_public_key,
         authorized_nodes
       ) do
    transaction_movements
    |> Enum.map(& &1.to)
    |> Enum.concat(recipients)
    |> Enum.uniq()
    |> Enum.any?(&Election.chain_storage_node?(&1, node_public_key, authorized_nodes))
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx, genesis_address: genesis_address}) do
    <<Transaction.serialize(tx)::bitstring, genesis_address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) when is_bitstring(bin) do
    {tx, rest} = Transaction.deserialize(bin)
    {genesis_address, rest} = Utils.deserialize_address(rest)

    {%__MODULE__{transaction: tx, genesis_address: genesis_address}, rest}
  end
end
