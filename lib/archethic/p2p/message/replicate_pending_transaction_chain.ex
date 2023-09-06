defmodule Archethic.P2P.Message.ReplicatePendingTransactionChain do
  @moduledoc false

  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Utils
  alias Archethic.Replication
  alias Archethic.TaskSupervisor
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.P2P
  alias Archethic.P2P.Message.Ok
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.AcknowledgeStorage

  @type t() :: %__MODULE__{
          address: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | Error.t()
  def process(%__MODULE__{address: address}, sender_public_key) do
    case Replication.get_transaction_in_commit_pool(address) do
      {:ok, tx = %Transaction{validation_stamp: %ValidationStamp{timestamp: validation_time}}} ->
        Task.Supervisor.start_child(TaskSupervisor, fn ->
          authorized_nodes = P2P.authorized_and_available_nodes(validation_time)

          Replication.sync_transaction_chain(tx, authorized_nodes)
          tx_summary = TransactionSummary.from_transaction(tx)

          ack = %AcknowledgeStorage{
            address: tx.address,
            signature: Crypto.sign_with_first_node_key(TransactionSummary.serialize(tx_summary))
          }

          P2P.send_message(sender_public_key, ack)
        end)

        %Ok{}

      {:error, :transaction_not_exists} ->
        %Error{reason: :invalid_transaction}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}) do
    address
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)

    {
      %__MODULE__{
        address: address
      },
      rest
    }
  end
end
