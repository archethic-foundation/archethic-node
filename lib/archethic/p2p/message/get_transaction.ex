defmodule ArchEthic.P2P.Message.GetTransaction do
  @moduledoc """
  Represents a message to request a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.NotFound
  alias ArchEthic.P2P.Message.Error
  alias ArchEthic.TransactionChain
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 3

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  def encode(%__MODULE__{address: address}) do
    address
  end

  def decode(message) when is_bitstring(message) do
    {address, rest} = Utils.deserialize_address(message)

    {
      %__MODULE__{address: address},
      rest
    }
  end

  def process(%__MODULE__{address: address}) do
    case TransactionChain.get_transaction(address) do
      {:ok, tx} ->
        tx

      {:error, :transaction_not_exists} ->
        %NotFound{}

      {:error, :invalid_transaction} ->
        %Error{reason: :invalid_transaction}
    end
  end
end
