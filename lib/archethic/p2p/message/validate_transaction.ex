defmodule Archethic.P2P.Message.ValidateTransaction do
  @moduledoc false

  @enforce_keys [:transaction, :inputs]
  defstruct [:transaction, :contract_context, :inputs]

  alias Archethic.Contracts.Contract
  alias Archethic.TransactionChain.Transaction
  alias Archethic.P2P.Message.ReplicationError
  alias Archethic.P2P.Message.Ok
  alias Archethic.Replication
  alias Archethic.Crypto

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils

  @type t :: %__MODULE__{
          transaction: Transaction.t(),
          contract_context: nil | Contract.Context.t(),
          inputs: list(VersionedUnspentOutput.t())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t() | ReplicationError.t()
  def process(%__MODULE__{transaction: tx, contract_context: contract_context, inputs: inputs}, _) do
    case Replication.validate_transaction(tx, contract_context, inputs) do
      :ok ->
        Replication.add_transaction_to_commit_pool(tx, inputs)
        %Ok{}

      {:error, error} ->
        %ReplicationError{address: tx.address, error: error}
    end
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
