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
  alias Archethic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: NotFound.t() | Error.t() | Transaction.t()
  def process(%__MODULE__{address: tx_address}, _) do
    case TransactionChain.get_transaction(tx_address) do
      {:ok, tx} -> tx
      {:error, :transaction_not_exists} -> %NotFound{}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: tx_address}), do: <<tx_address::binary>>

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {
      %__MODULE__{address: address},
      rest
    }
  end
end
