defmodule ArchEthic.P2P.Message.GetTransactionSummary do
  @moduledoc """
  Represents a message to get a transaction summary from a transaction address
  """
  @enforce_keys [:address]
  defstruct [:address]

  alias ArchEthic.P2P.Message.NotFound

  alias ArchEthic.TransactionChain
  alias ArchEthic.TransactionChain.TransactionSummary
  alias ArchEthic.Utils

  use ArchEthic.P2P.Message, message_id: 23

  @type t :: %__MODULE__{
          address: binary()
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
    case TransactionChain.get_transaction(address, [
           :address,
           :type,
           validation_stamp: [
             :timestamp,
             ledger_operations: [:fee, :transaction_movements]
           ]
         ]) do
      {:ok, tx} ->
        TransactionSummary.from_transaction(tx)

      _ ->
        %NotFound{}
    end
  end
end
