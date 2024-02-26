defmodule Archethic.P2P.Message.GetTransactionInputs do
  @moduledoc """
  Represents a message to request the inputs (spent or unspents) from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0, limit: 0]

  alias Archethic.Crypto
  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.VersionedTransactionInput
  alias Archethic.P2P.Message.TransactionInputList
  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          offset: non_neg_integer(),
          limit: non_neg_integer()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionInputList.t()
  def process(%__MODULE__{address: address, offset: offset, limit: limit}, _) do
    inputs = address |> TransactionChain.get_inputs() |> Enum.to_list()
    inputs_length = Enum.count(inputs)

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

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address, offset: offset, limit: limit}) do
    <<address::binary, VarInt.from_value(offset)::binary, VarInt.from_value(limit)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {offset, rest} = VarInt.get_value(rest)
    {limit, rest} = VarInt.get_value(rest)
    {%__MODULE__{address: address, offset: offset, limit: limit}, rest}
  end
end
