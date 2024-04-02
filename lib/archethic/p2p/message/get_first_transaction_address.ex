defmodule Archethic.P2P.Message.GetFirstTransactionAddress do
  @moduledoc """
  Represents a message to request the first address from a transaction chain.
  Genesis address != first transaction address
  Hash of current index public key gives current index address
  Hash of genesis public key gives genesis address
  Hash of first public key gives first transaction address
  """
  alias Archethic.Utils
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.NotFound

  @enforce_keys [:address]
  defstruct [:address]

  @type t() :: %__MODULE__{
          address: binary()
        }

  @doc """
  Serialize GetFirstTransactionAddress struct
  """
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @doc """
  Deserialize GetFirstTransactionAddress struct
  """
  def deserialize(bin) do
    {address, <<rest::bitstring>>} = Utils.deserialize_address(bin)

    {%__MODULE__{address: address}, rest}
  end

  @spec process(t(), Message.metadata()) :: NotFound.t() | FirstTransactionAddress.t()
  def process(%__MODULE__{address: address}, _) do
    case TransactionChain.get_first_transaction_address(address) do
      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:ok, {first_address, timestamp}} ->
        %FirstTransactionAddress{address: first_address, timestamp: timestamp}
    end
  end
end
