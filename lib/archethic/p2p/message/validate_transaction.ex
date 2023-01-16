defmodule Archethic.P2P.Message.ValidateTransaction do
  @moduledoc false

  @enforce_keys [:transaction]
  defstruct [:transaction]

  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message.Ok
  alias Archethic.Replication
  alias Archethic.Crypto

  @type t :: %__MODULE__{
          transaction: Transaction.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | ReplicationError.t()
  def process(%__MODULE__{transaction: tx}, _) do
    case Replication.validate_transaction(tx) do
      :ok ->
        Replication.add_transaction_to_commit_pool(tx)
        %Ok{}

      {:error, :transaction_already_exists} ->
        %ReplicationError{address: tx.address, reason: :transaction_already_exists}

      {:error, reason} ->
        %ReplicationError{address: tx.address, reason: reason}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction: tx}) do
    Transaction.serialize(tx)
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) when is_bitstring(bin) do
    {tx, rest} = Transaction.deserialize(bin)

    {
      %__MODULE__{transaction: tx},
      rest
    }
  end
end
