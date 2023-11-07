defmodule Archethic.P2P.Message.GetUnspentOutputs do
  @moduledoc """
  Represents a message to request the list of unspent outputs from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0]

  alias Archethic.Crypto
  alias Archethic.Account
  alias Archethic.P2P.Message.UnspentOutputList

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          offset: non_neg_integer()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: UnspentOutputList.t()
  def process(%__MODULE__{address: tx_address, offset: offset}, _) do
    utxos = Account.get_unspent_outputs(tx_address)
    utxos_length = length(utxos)

    %{utxos: utxos, offset: offset, more?: more?} =
      utxos
      |> Enum.with_index()
      |> Enum.drop(offset)
      |> Enum.reduce_while(%{utxos: [], offset: 0, more?: false}, fn {versioned_utxo, index},
                                                                     acc ->
        acc_size =
          acc.utxos
          |> Enum.map(&VersionedUnspentOutput.serialize/1)
          |> :erlang.list_to_bitstring()
          |> byte_size()

        utxo_size =
          versioned_utxo
          |> VersionedUnspentOutput.serialize()
          |> byte_size

        if acc_size + utxo_size < 3_000_000 do
          new_acc =
            acc
            |> Map.update!(:utxos, &[versioned_utxo | &1])
            |> Map.put(:offset, index + 1)
            |> Map.put(:more?, index + 1 < utxos_length)

          {:cont, new_acc}
        else
          {:halt, acc}
        end
      end)

    %UnspentOutputList{
      unspent_outputs: utxos,
      offset: offset,
      more?: more?
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: tx_address, offset: offset}) do
    <<tx_address::binary, VarInt.from_value(offset)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {offset, rest} = VarInt.get_value(rest)
    {%__MODULE__{address: address, offset: offset}, rest}
  end
end
