defmodule ArchEthic.P2P.Message.ReplicateTransaction do
  @moduledoc """
  Represents a message to initiate the replication of the transaction
  """
  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias ArchEthic.P2P.Message.Error
  alias ArchEthic.P2P.Message.Ok
  alias ArchEthic.Replication
  alias ArchEthic.TransactionChain.Transaction

  use ArchEthic.P2P.Message, message_id: 12

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  def encode(%__MODULE__{transaction: tx}) do
    Transaction.serialize(tx)
  end

  def decode(message) when is_bitstring(message) do
    {tx, rest} = Transaction.deserialize(message)

    {
      %__MODULE__{
        transaction: tx
      },
      rest
    }
  end

  def process(%__MODULE__{transaction: tx}) do
    case Replication.validate_and_store_transaction(tx) do
      :ok ->
        %Ok{}

      {:error, :transaction_already_exists} ->
        %Error{reason: :transaction_already_exists}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end
end
