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
          limit: non_neg_integer(),
          limit: non_neg_integer()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: UnspentOutputList.t()
  def process(%__MODULE__{address: genesis_address, offset: offset, limit: limit}, _) do
    {utxos, more?, offset} =
      genesis_address
      |> UTXO.stream_unspent_outputs()
      |> Enum.sort_by(fn %VersionedUnspentOutput{
                           unspent_output: %UnspentOutput{timestamp: timestamp}
                         } ->
        if is_nil(timestamp), do: DateTime.from_unix!(0), else: timestamp
      end)
      |> Utils.limit_list(limit, offset, @threshold, fn utxo ->
        utxo
        |> VersionedUnspentOutput.serialize()
        |> byte_size
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

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)

    {offset, rest} = VarInt.get_value(rest)
    {%__MODULE__{address: address, offset: offset}, rest}
  end
end
