defmodule Archethic.P2P.Message.GetUnspentOutputs do
  @moduledoc """
  Represents a message to request the list of unspent outputs from a transaction
  """
  @enforce_keys [:address]
  defstruct [:address, offset: nil, limit: 0]

  alias Archethic.Crypto
  alias Archethic.P2P.Message.UnspentOutputList

  alias Archethic.TransactionChain
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
          address: Crypto.prepended_hash(),
          offset: Crypto.sha256() | nil,
          limit: non_neg_integer()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: UnspentOutputList.t()
  def process(%__MODULE__{address: genesis_address, offset: offset, limit: limit}, _) do
    sorted_utxos =
      genesis_address
      |> UTXO.stream_unspent_outputs()
      |> Enum.sort_by(fn %VersionedUnspentOutput{
                           unspent_output: %UnspentOutput{timestamp: timestamp}
                         } ->
        if is_nil(timestamp), do: DateTime.from_unix!(0), else: timestamp
      end)

    case get_numerical_offset(sorted_utxos, offset) do
      nil ->
        %UnspentOutputList{
          unspent_outputs: [],
          offset: nil,
          more?: false,
          last_chain_sync_date: DateTime.from_unix!(0, :millisecond)
        }

      offset ->
        {utxos, more?, _offset} =
          Utils.limit_list(sorted_utxos, limit, offset, @threshold, fn utxo ->
            utxo |> VersionedUnspentOutput.serialize() |> byte_size
          end)

        offset =
          if Enum.empty?(utxos),
            do: nil,
            else: utxos |> List.last() |> VersionedUnspentOutput.hash()

        {_, last_chain_sync_date} = TransactionChain.get_last_address(genesis_address)

        %UnspentOutputList{
          unspent_outputs: utxos,
          offset: offset,
          more?: more?,
          last_chain_sync_date: last_chain_sync_date
        }
    end
  end

  defp get_numerical_offset(_utxos, nil), do: 0

  defp get_numerical_offset(utxos, offset) do
    case Enum.find_index(utxos, &(VersionedUnspentOutput.hash(&1) == offset)) do
      nil -> nil
      index -> index + 1
    end
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: tx_address, offset: offset, limit: limit}) do
    offset_bin = if is_nil(offset), do: <<0::1>>, else: <<1::1, offset::binary>>
    <<tx_address::binary, offset_bin::bitstring, VarInt.from_value(limit)::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {offset, rest} =
      case rest do
        <<0::1, rest::bitstring>> -> {nil, rest}
        <<1::1, offset::binary-size(32), rest::bitstring>> -> {offset, rest}
      end

    {limit, rest} = VarInt.get_value(rest)

    {%__MODULE__{address: address, offset: offset, limit: limit}, rest}
  end
end
