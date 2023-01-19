defmodule Archethic.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message.Ok
  alias Archethic.Replication
  alias Archethic.Utils
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | ReplicationError.t()
  def process(
        %__MODULE__{
          transaction:
            tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: validation_time}}
        },
        _
      ) do
    resolved_addresses = TransactionChain.resolve_transaction_addresses(tx, validation_time)

    io_storage_nodes =
      if Transaction.network_type?(tx.type) do
        P2P.list_nodes()
      else
        resolved_addresses
        |> Enum.map(fn {_origin, resolved} -> resolved end)
        |> Enum.concat([LedgerOperations.burning_address()])
        |> Election.io_storage_nodes(P2P.authorized_and_available_nodes(validation_time))
      end

    # Replicate tx only if the current node is one of the I/O storage nodes
    if Utils.key_in_node_list?(io_storage_nodes, Crypto.first_node_public_key()) do
      case Replication.validate_and_store_transaction(tx) do
        :ok ->
          %Ok{}

        {:error, :transaction_already_exists} ->
          %ReplicationError{address: tx.address, reason: :transaction_already_exists}

        {:error, invalid_tx_reason} ->
          %ReplicationError{address: tx.address, reason: invalid_tx_reason}
      end
    else
      %Ok{}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx}) do
    <<Transaction.serialize(tx)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {%__MODULE__{
       transaction: tx
     }, rest}
  end
end
