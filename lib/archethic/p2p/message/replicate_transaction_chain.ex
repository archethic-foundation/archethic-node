defmodule Archethic.P2P.Message.ReplicateTransactionChain do
  @moduledoc """
  Represents a message to initiate the replication of the transaction chain related to the given transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction, :replying_node]

  alias Archethic.Crypto
  alias Archethic.TaskSupervisor
  alias Archethic.Election
  alias Archethic.Replication
  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.P2P.Message.AcknowledgeStorage
  alias Archethic.P2P.Message.ReplicationError

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          replying_node: nil | Crypto.key()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          transaction:
            tx = %Transaction{
              address: tx_address,
              type: tx_type,
              validation_stamp: %ValidationStamp{timestamp: timestamp}
            },
          replying_node: replying_node_public_key
        },
        _
      ) do
    # We don't check the election for network transactions because all the nodes receive the chain replication message
    # The chain storage nodes election is all the authorized nodes but during I/O replication, we send this message to enforce
    # the synchronization of the network chains
    storage_nodes =
      Election.chain_storage_nodes_with_type(
        tx_address,
        tx_type,
        P2P.authorized_and_available_nodes(timestamp)
      )

    # Replicate transaction chain only if the current node is one of the chain storage nodes
    if Utils.key_in_node_list?(storage_nodes, Crypto.first_node_public_key()) do
      process_replication_chain(tx, replying_node_public_key)
    end

    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx, replying_node: nil}) do
    <<Transaction.serialize(tx)::bitstring, 0::1>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, <<replying_node::1, rest::bitstring>>} = Transaction.deserialize(rest)

    if replying_node == 1 do
      {node_public_key, rest} = Utils.deserialize_public_key(rest)

      {%__MODULE__{
         transaction: tx,
         replying_node: node_public_key
       }, rest}
    else
      {%__MODULE__{
         transaction: tx
       }, rest}
    end
  end

  defp process_replication_chain(tx, replying_node_public_key) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      response =
        case Replication.validate_and_store_transaction_chain(tx) do
          :ok ->
            tx_summary = TransactionSummary.from_transaction(tx)

            %AcknowledgeStorage{
              address: tx.address,
              signature: Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary))
            }

          {:error, :transaction_already_exists} ->
            %ReplicationError{address: tx.address, reason: :transaction_already_exists}

          {:error, invalid_tx_error} ->
            %ReplicationError{address: tx.address, reason: invalid_tx_error}
        end

      if replying_node_public_key do
        P2P.send_message(replying_node_public_key, response)
      end
    end)
  end
end
