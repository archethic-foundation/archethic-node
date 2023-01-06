defmodule Archethic.P2P.Message.GetLastTransaction do
  @moduledoc """
  Represents a message to request the last transaction of a chain
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.P2P.Message.Error
  alias Archethic.P2P.Message.NotFound
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: NotFound.t() | Error.t() | Transaction.t()
  def process(%__MODULE__{address: address}, _) do
    case TransactionChain.get_last_transaction(address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end
end
