defmodule Archethic.P2P.Message.GetUnspentOutputs do
  @moduledoc """
  Represents a message to request the list of unspent outputs from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: 0, limit: 0, genesis?: false]

  alias Archethic.Account
  alias Archethic.Contracts
  alias Archethic.Crypto
  alias Archethic.P2P.Message.UnspentOutputList

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
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
          limit: non_neg_integer(),
          genesis?: boolean()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: UnspentOutputList.t()
  def process(%__MODULE__{address: tx_address, offset: offset, genesis?: false}, _) do
    contract_utxos =
      tx_address
      |> Contracts.list_contract_transactions()
      |> Enum.map(fn {address, timestamp, protocol_version} ->
        %UnspentOutput{from: address, type: :call, timestamp: timestamp}
        |> VersionedUnspentOutput.wrap_unspent_output(protocol_version)
      end)

    ledger_utxos = Account.get_unspent_outputs(tx_address)

    utxos = ledger_utxos ++ contract_utxos

    %{utxos: utxos, offset: offset, more?: more?} = reduce_utxos(utxos, offset)

    %UnspentOutputList{
      unspent_outputs: utxos,
      offset: offset,
      more?: more?
    }
  end

  def process(%__MODULE__{address: genesis_address, offset: offset, genesis?: true}, _) do
    %{utxos: utxos, offset: offset, more?: more?} =
      genesis_address |> UTXO.stream_unspent_outputs() |> reduce_utxos(offset)

    %UnspentOutputList{
      unspent_outputs: utxos,
      offset: offset,
      more?: more?
    }
  end

  defp reduce_utxos(utxos, offset) do
    utxos_length = Enum.count(utxos)

    utxos
    |> Enum.sort_by(& &1.unspent_output.timestamp, {:desc, DateTime})
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
  def serialize(%__MODULE__{address: tx_address, offset: offset, genesis?: genesis?}) do
    genesis_bit = if genesis?, do: 1, else: 0
    <<tx_address::binary, VarInt.from_value(offset)::binary, genesis_bit::1>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {offset, <<genesis_bit::1, rest::bitstring>>} = VarInt.get_value(rest)
    {%__MODULE__{address: address, offset: offset, genesis?: genesis_bit == 1}, rest}
  end
end
