defmodule Archethic.P2P.Message.GetContractCalls do
  @moduledoc """
  Represents a message to request the transactions that called this version of the contract.
  """
  @enforce_keys [:address, :before]
  defstruct [:address, :before]

  alias Archethic.Contracts
  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.P2P.Message.TransactionList
  alias Archethic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          before: DateTime.t()
        }

  @spec process(t(), Crypto.key()) :: TransactionList.t()
  def process(%__MODULE__{address: address, before: before = %DateTime{}}, _) do
    transaction_addresses =
      Contracts.list_contract_transactions(address)
      |> Enum.filter(fn {_, timestamp, _} -> DateTime.compare(timestamp, before) == :lt end)
      |> Enum.map(&elem(&1, 0))

    # will crash if a task did not succeed
    transactions =
      Task.async_stream(transaction_addresses, &TransactionChain.get_transaction(&1))
      |> Stream.map(fn {:ok, {:ok, tx}} -> tx end)
      |> Enum.to_list()

    %TransactionList{transactions: transactions, paging_state: nil, more?: false}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, before: before = %DateTime{}}) do
    <<address::binary, DateTime.to_unix(before, :millisecond)::64>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, <<timestamp::64, rest::bitstring>>} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address, before: DateTime.from_unix!(timestamp, :millisecond)}, rest}
  end
end
