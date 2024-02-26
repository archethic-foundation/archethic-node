defmodule Archethic.P2P.Message.GetUnspentOutputs do
  @moduledoc """
  Represents a message to request the list of unspent outputs from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0, limit: 0]

  alias Archethic.Crypto
  alias Archethic.P2P.Message.UnspentOutputList

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils
  alias Archethic.Utils.VarInt
  alias Archethic.UTXO

  @threshold Keyword.get(
               Application.compile_env(:archethic, __MODULE__, []),
               :threshold,
               3_000_000
             )

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          offset: non_neg_integer(),
          # limit is not used
          limit: non_neg_integer()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: UnspentOutputList.t()
  def process(%__MODULE__{address: genesis_address, offset: offset}, _) do
    %{utxos: utxos, offset: offset, more?: more?} =
      genesis_address
      |> UTXO.stream_unspent_outputs()
      |> reduce_utxos(offset)

    %UnspentOutputList{
      unspent_outputs: utxos,
      offset: offset,
      more?: more?
    }
  end

  defp reduce_utxos(utxos, offset) do
    utxos_length = Enum.count(utxos)

    utxos
    |> Enum.sort_by(fn %VersionedUnspentOutput{
                         unspent_output: %UnspentOutput{timestamp: timestamp}
                       } ->
      if is_nil(timestamp), do: DateTime.from_unix!(0), else: timestamp
    end)
    |> Enum.with_index()
    |> Enum.drop(offset)
    |> Enum.reduce_while(
      %{utxos: [], offset: 0, more?: false, acc_size: 0},
      fn {versioned_utxo, index}, acc ->
        acc_size = Map.get(acc, :acc_size)

        utxo_size =
          versioned_utxo
          |> VersionedUnspentOutput.serialize()
          |> byte_size

        new_acc_size = acc_size + utxo_size

        if new_acc_size < @threshold do
          new_acc =
            acc
            |> Map.update!(:utxos, &[versioned_utxo | &1])
            |> Map.put(:acc_size, new_acc_size)
            |> Map.put(:offset, index + 1)
            |> Map.put(:more?, index + 1 < utxos_length)

          {:cont, new_acc}
        else
          {:halt, acc}
        end
      end
    )
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: tx_address, offset: offset}) do
    <<tx_address::binary, VarInt.from_value(offset)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {offset, rest} = VarInt.get_value(rest)
    {%__MODULE__{address: address, offset: offset}, rest}
  end
end
