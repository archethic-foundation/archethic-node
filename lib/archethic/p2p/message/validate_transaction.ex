defmodule Archethic.P2P.Message.ValidateTransaction do
  @moduledoc false

  @enforce_keys [:transaction, :inputs]
  defstruct [:transaction, :contract_context, :inputs]

  alias Archethic.P2P.Message.CrossValidationDone
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.Contracts.Contract
  alias Archethic.TransactionChain.Transaction
  alias Archethic.Replication
  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          contract_context: nil | Contract.Context.t(),
          inputs: list(VersionedUnspentOutput.t())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: CrossValidationDone.t()
  def process(%__MODULE__{transaction: tx, contract_context: contract_context, inputs: inputs}, _) do
    %Transaction{address: tx_address, validation_stamp: %ValidationStamp{error: stamp_error}} = tx

    cross_stamp =
      %CrossValidationStamp{inconsistencies: inconsistencies} =
      Replication.validate_transaction(tx, contract_context, inputs)

    if stamp_error == nil and Enum.empty?(inconsistencies) do
      Replication.add_transaction_to_commit_pool(tx, inputs)
    end

    %CrossValidationDone{address: tx_address, cross_validation_stamp: cross_stamp}
  end

  @spec serialize(t()) :: bitstring()

  def serialize(%__MODULE__{transaction: tx, contract_context: nil, inputs: inputs}) do
    inputs_bin =
      inputs
      |> Enum.map(&VersionedUnspentOutput.serialize/1)
      |> :erlang.list_to_bitstring()

    inputs_size =
      inputs
      |> length()
      |> Utils.VarInt.from_value()

    <<Transaction.serialize(tx)::bitstring, 0::8, inputs_size::binary, inputs_bin::bitstring>>
  end

  def serialize(%__MODULE__{transaction: tx, contract_context: contract_context, inputs: inputs}) do
    inputs_bin =
      inputs
      |> Enum.map(&VersionedUnspentOutput.serialize/1)
      |> :erlang.list_to_bitstring()

    inputs_size =
      inputs
      |> length()
      |> Utils.VarInt.from_value()

    <<Transaction.serialize(tx)::bitstring, 1::8,
      Contract.Context.serialize(contract_context)::bitstring, inputs_size::binary,
      inputs_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring()}
  def deserialize(bin) when is_bitstring(bin) do
    {tx, rest} = Transaction.deserialize(bin)

    {contract_context, rest} =
      case rest do
        <<0::8, rest::bitstring>> -> {nil, rest}
        <<1::8, rest::bitstring>> -> Contract.Context.deserialize(rest)
      end

    {inputs_size, rest} = Utils.VarInt.get_value(rest)
    {inputs, rest} = deserialize_versioned_unspent_output_list(rest, inputs_size, [])

    {
      %__MODULE__{transaction: tx, contract_context: contract_context, inputs: inputs},
      rest
    }
  end

  defp deserialize_versioned_unspent_output_list(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_unspent_output_list(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end
end
