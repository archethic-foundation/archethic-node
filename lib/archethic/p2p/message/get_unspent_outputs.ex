defmodule Archethic.P2P.Message.GetUnspentOutputs do
  @moduledoc """
  Represents a message to request the list of unspent outputs from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0]

  alias Archethic.Crypto
  alias Archethic.Account
  alias Archethic.P2P.Message.UnspentOutputList

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
          |> :erlang.list_to_binary()
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
end
