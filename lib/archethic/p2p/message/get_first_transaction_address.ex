defmodule Archethic.P2P.Message.GetFirstTransactionAddress do
  @moduledoc """
  Represents a message to request the first address from a transaction chain.
  Genesis address != first transaction address
  Hash of current index public key gives current index address
  Hash of genesis public key gives genesis address
  Hash of first public key gives first transaction address
  """
  alias Archethic.Utils
  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.TransactionChain
  @enforce_keys [:address]
  defstruct [:address]

  @type t() :: %__MODULE__{
          address: binary()
        }

  @doc """
         Serialize GetFirstTransactionAddress Struct

        iex> %GetFirstTransactionAddress{
        ...> address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...>  3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        ...> } |> GetFirstTransactionAddress.serialize()
        #address
        <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
  """
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @doc """
        DeSerialize GetFirstTransactionAddress Struct

        iex> # First address
        ...> <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
        ...> 3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        ...> |> GetFirstTransactionAddress.deserialize()
        {
        %GetFirstTransactionAddress{
        address: <<0, 0, 94, 5, 249, 103, 126, 31, 43, 57, 25, 14, 187, 133, 59, 234, 201, 172,
         3, 195, 43, 81, 81, 146, 164, 202, 147, 218, 207, 204, 31, 185, 73, 251>>
        }, ""}

  """
  def deserialize(bin) do
    {address, <<rest::bitstring>>} = Utils.deserialize_address(bin)

    {%__MODULE__{address: address}, rest}
  end

  def process(%__MODULE__{address: address}) do
    case TransactionChain.get_first_transaction_address(address) do
      {:error, :transaction_not_exists} ->
        %Archethic.P2P.Message.NotFound{}

      {:ok, first_address} ->
        %FirstTransactionAddress{address: first_address}
    end
  end
end
