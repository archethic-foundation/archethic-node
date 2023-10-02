defmodule Archethic.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction, :contract_context]

  alias Archethic.Contracts.Contract
  alias Archethic.Crypto
  alias Archethic.Election
  alias Archethic.P2P
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message.Ok
  alias Archethic.Replication
  alias Archethic.Utils
  alias Archethic.TaskSupervisor
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          contract_context: nil | Contract.Context.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | ReplicationError.t()
  def process(
        %__MODULE__{
          transaction:
            tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: validation_time}},
          contract_context: contract_context
        },
        _
      ) do
    Task.Supervisor.start_child(TaskSupervisor, fn ->
      if Transaction.network_type?(tx.type) do
        Replication.validate_and_store_transaction_chain(tx, contract_context)
      else
        resolved_addresses = TransactionChain.resolve_transaction_addresses(tx, validation_time)

        io_storage_nodes =
          resolved_addresses
          |> Enum.map(fn {_origin, resolved} -> resolved end)
          |> Enum.concat([LedgerOperations.burning_address()])
          |> Election.io_storage_nodes(P2P.authorized_and_available_nodes(validation_time))

        # Replicate tx only if the current node is one of the I/O storage nodes
        if Utils.key_in_node_list?(io_storage_nodes, Crypto.first_node_public_key()) do
          Replication.validate_and_store_transaction(tx)
        end
      end
    end)

    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx, contract_context: nil}) do
    <<Transaction.serialize(tx)::bitstring, 0::8>>
  end

  def serialize(%__MODULE__{transaction: tx, contract_context: contract_context}) do
    <<Transaction.serialize(tx)::bitstring, 1::8,
      Contract.Context.serialize(contract_context)::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {tx, rest} = Transaction.deserialize(rest)

    {contract_context, rest} =
      case rest do
        <<0::8, rest::bitstring>> -> {nil, rest}
        <<1::8, rest::bitstring>> -> Contract.Context.deserialize(rest)
      end

    {
      %__MODULE__{transaction: tx, contract_context: contract_context},
      rest
    }
  end
end
