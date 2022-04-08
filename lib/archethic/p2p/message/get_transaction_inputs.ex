defmodule ArchEthic.P2P.Message.GetTransactionInputs do
  @moduledoc """
  Represents a message with to request the inputs (spent or unspents) from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.Account
  alias ArchEthic.Contracts
  alias ArchEthic.Crypto
  alias ArchEthic.P2P.Message.TransactionInputList
  alias ArchEthic.TransactionChain.TransactionInput
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 17

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash()
        }

  def encode(%__MODULE__{address: address}) do
    address
  end

  def decode(message) when is_bitstring(message) do
    {address, rest} = Utils.deserialize_address(message)

    {
      %__MODULE__{
        address: address
      },
      rest
    }
  end

  def process(%__MODULE__{address: address}) do
    contract_inputs =
      address
      |> Contracts.list_contract_transactions()
      |> Enum.map(fn {address, timestamp} ->
        %TransactionInput{from: address, type: :call, timestamp: timestamp}
      end)

    %TransactionInputList{
      inputs: Account.get_inputs(address) ++ contract_inputs
    }
  end
end
