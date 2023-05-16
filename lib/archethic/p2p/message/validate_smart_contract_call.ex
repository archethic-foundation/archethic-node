defmodule Archethic.P2P.Message.ValidateSmartContractCall do
  @moduledoc """
  Represents a message to validate a smart contract call
  """

  @enforce_keys [:contract_address, :transaction, :inputs_before]
  defstruct [:contract_address, :transaction, :inputs_before]

  alias Archethic.Contracts
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Utils

  @type t :: %__MODULE__{
          contract_address: binary(),
          transaction: Transaction.t(),
          inputs_before: DateTime.t()
        }

  def serialize(%__MODULE__{
        contract_address: contract_address,
        transaction: tx = %Transaction{},
        inputs_before: time = %DateTime{}
      }) do
    <<contract_address::binary, Transaction.serialize(tx)::bitstring,
      DateTime.to_unix(time, :millisecond)::64>>
  end

  def deserialize(data) when is_bitstring(data) do
    {contract_address, rest} = Utils.deserialize_address(data)
    {tx, <<timestamp::64, rest::bitstring>>} = Transaction.deserialize(rest)

    {
      %__MODULE__{
        contract_address: contract_address,
        transaction: tx,
        inputs_before: DateTime.from_unix(timestamp, :millisecond)
      },
      rest
    }
  end

  def process(%__MODULE__{
        contract_address: contract_address,
        transaction: transaction = %Transaction{},
        inputs_before: inputs_before
      }) do
    valid? =
      with {:ok, contract} <- Contracts.from_transaction(contract_address),
           {:ok, calls} <- TransactionChain.fetch_contract_calls(contract_address, inputs_before) do
        Contracts.valid_contract_execution?(contract, transaction, calls)
      else
        _ ->
          false
      end

    %SmartContractCallValidation{
      valid?: valid?
    }
  end
end
