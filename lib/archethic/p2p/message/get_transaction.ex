defmodule Archethic.P2P.Message.GetTransaction do
  @moduledoc """
  Represents a message to request a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Message.Error

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: NotFound.t() | Error.t() | Transaction.t()
  def process(%__MODULE__{address: tx_address}, _) do
    case TransactionChain.get_transaction(tx_address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end
end
