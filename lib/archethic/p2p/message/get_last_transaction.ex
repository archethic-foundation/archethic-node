defmodule Archethic.P2P.Message.GetLastTransaction do
  @moduledoc """
  Represents a message to request the last transaction of a chain
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Utils
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
      {:ok, tx} -> tx
      {:error, :transaction_not_exists} -> %NotFound{}
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end
end
