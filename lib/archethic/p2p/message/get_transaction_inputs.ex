defmodule Archethic.P2P.Message.GetTransactionInputs do
  @moduledoc """
  Represents a message with to request the inputs (spent or unspents) from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0, limit: 0]

  alias Archethic.Crypto
  alias Archethic.Contracts
  alias Archethic.Account
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.TransactionChain.TransactionInput
  alias Archethic.P2P.Message.TransactionInputList

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          offset: non_neg_integer(),
          limit: non_neg_integer()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionInputList.t()
  def process(%__MODULE__{address: address, offset: offset, limit: limit}, _) do
    contract_inputs =
      address
      |> Contracts.list_contract_transactions()
      |> Enum.map(fn {address, timestamp, protocol_version} ->
        %VersionedTransactionInput{
          input: %TransactionInput{from: address, type: :call, timestamp: timestamp},
          protocol_version: protocol_version
        }
      end)

    inputs = Account.get_inputs(address) ++ contract_inputs
    inputs_length = length(inputs)

    %{inputs: inputs, offset: offset, more?: more?} =
      inputs
      |> Enum.sort_by(& &1.input.timestamp, {:desc, DateTime})
      |> Enum.with_index()
      |> Enum.drop(offset)
      |> Enum.reduce_while(
        %{inputs: [], offset: 0, more?: false},
        fn {versioned_input, index}, acc = %{inputs: inputs, offset: offset, more?: more?} ->
          acc_size = Map.get(acc, :acc_size, 0)
          acc_length = Map.get(acc, :acc_length, 0)

          input_size =
            versioned_input
            |> VersionedTransactionInput.serialize()
            |> byte_size

          size_capacity? = acc_size + input_size < 3_000_000

          should_take_more? =
            if limit > 0 do
              acc_length < limit and size_capacity?
            else
              size_capacity?
            end

          if should_take_more? do
            new_acc =
              acc
              |> Map.update!(:inputs, &[versioned_input | &1])
              |> Map.update(:acc_size, input_size, &(&1 + input_size))
              |> Map.update(:acc_length, 1, &(&1 + 1))
              |> Map.put(:offset, index + 1)
              |> Map.put(:more?, index + 1 < inputs_length)

            {:cont, new_acc}
          else
            {:halt, %{inputs: inputs, offset: offset, more?: more?}}
          end
        end
      )

    %TransactionInputList{
      inputs: Enum.reverse(inputs),
      more?: more?,
      offset: offset
    }
  end
end
