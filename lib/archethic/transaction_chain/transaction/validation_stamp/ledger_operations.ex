defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations do
  @moduledoc """
  Represents the ledger operations defined during the transaction mining regarding the network movements
  """

  defstruct transaction_movements: [], unspent_outputs: [], fee: 0, consumed_inputs: []

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.Utils.VarInt

  @typedoc """
  - Transaction movements: represents the pending transaction ledger movements
  - Unspent outputs: represents the new unspent outputs
  - fee: represents the transaction fee
  - Consumed inputs: represents the list of inputs consumed to produce the unspent outputs
  """
  @type t() :: %__MODULE__{
          transaction_movements: list(TransactionMovement.t()),
          unspent_outputs: list(UnspentOutput.t()),
          fee: non_neg_integer(),
          consumed_inputs: list(VersionedUnspentOutput.t())
        }

  @doc """
  List all the addresses from transaction movements
  """
  @spec movement_addresses(t()) :: list(binary())
  def movement_addresses(%__MODULE__{
        transaction_movements: transaction_movements
      }) do
    Enum.map(transaction_movements, & &1.to)
  end

  @doc """
  Serialize a ledger operations
  """
  @spec serialize(ledger_operations :: t(), protocol_version :: non_neg_integer()) :: bitstring()
  def serialize(
        %__MODULE__{
          fee: fee,
          transaction_movements: transaction_movements,
          unspent_outputs: unspent_outputs,
          consumed_inputs: consumed_inputs
        },
        protocol_version
      ) do
    bin_transaction_movements =
      transaction_movements
      |> Enum.map(&TransactionMovement.serialize(&1, protocol_version))
      |> :erlang.list_to_binary()

    bin_unspent_outputs =
      unspent_outputs
      |> Enum.map(&UnspentOutput.serialize(&1, protocol_version))
      |> :erlang.list_to_bitstring()

    encoded_transaction_movements_len = transaction_movements |> length() |> VarInt.from_value()
    encoded_unspent_outputs_len = unspent_outputs |> length() |> VarInt.from_value()

    consumed_inputs_bin =
      if protocol_version < 7 do
        <<>>
      else
        encoded_consumed_inputs_len = consumed_inputs |> length() |> VarInt.from_value()

        bin_consumed_inputs =
          consumed_inputs
          |> Enum.map(&VersionedUnspentOutput.serialize/1)
          |> :erlang.list_to_bitstring()

        <<encoded_consumed_inputs_len::binary, bin_consumed_inputs::bitstring>>
      end

    <<fee::64, encoded_transaction_movements_len::binary, bin_transaction_movements::binary,
      encoded_unspent_outputs_len::binary, bin_unspent_outputs::bitstring,
      consumed_inputs_bin::bitstring>>
  end

  @doc """
  Deserialize an encoded ledger operations
  """
  @spec deserialize(data :: bitstring(), protocol_version :: non_neg_integer()) ::
          {t(), bitstring()}
  def deserialize(<<fee::64, rest::bitstring>>, protocol_version) when protocol_version < 7 do
    {nb_transaction_movements, rest} = VarInt.get_value(rest)

    {tx_movements, rest} =
      deserialiaze_transaction_movements(rest, nb_transaction_movements, [], protocol_version)

    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, rest} =
      deserialize_unspent_outputs(rest, nb_unspent_outputs, [], protocol_version)

    {
      %__MODULE__{
        fee: fee,
        transaction_movements: tx_movements,
        unspent_outputs: unspent_outputs,
        consumed_inputs: []
      },
      rest
    }
  end

  def deserialize(<<fee::64, rest::bitstring>>, protocol_version) do
    {nb_transaction_movements, rest} = VarInt.get_value(rest)

    {tx_movements, rest} =
      deserialiaze_transaction_movements(rest, nb_transaction_movements, [], protocol_version)

    {nb_unspent_outputs, rest} = rest |> VarInt.get_value()

    {unspent_outputs, rest} =
      deserialize_unspent_outputs(rest, nb_unspent_outputs, [], protocol_version)

    {nb_consumed_inputs, rest} = rest |> VarInt.get_value()

    {consumed_inputs, rest} = deserialize_versioned_unspent_outputs(rest, nb_consumed_inputs, [])

    {
      %__MODULE__{
        fee: fee,
        transaction_movements: tx_movements,
        unspent_outputs: unspent_outputs,
        consumed_inputs: consumed_inputs
      },
      rest
    }
  end

  defp deserialiaze_transaction_movements(rest, 0, _, _), do: {[], rest}

  defp deserialiaze_transaction_movements(rest, nb, acc, _) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp deserialiaze_transaction_movements(rest, nb, acc, protocol_version) do
    {tx_movement, rest} = TransactionMovement.deserialize(rest, protocol_version)
    deserialiaze_transaction_movements(rest, nb, [tx_movement | acc], protocol_version)
  end

  defp deserialize_unspent_outputs(rest, 0, _, _), do: {[], rest}

  defp deserialize_unspent_outputs(rest, nb, acc, _) when length(acc) == nb do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_unspent_outputs(rest, nb, acc, protocol_version) do
    {unspent_output, rest} = UnspentOutput.deserialize(rest, protocol_version)
    deserialize_unspent_outputs(rest, nb, [unspent_output | acc], protocol_version)
  end

  defp deserialize_versioned_unspent_outputs(rest, 0, _acc), do: {[], rest}

  defp deserialize_versioned_unspent_outputs(rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_versioned_unspent_outputs(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_outputs(rest, nb_unspent_outputs, [unspent_output | acc])
  end

  @spec cast(map()) :: t()
  def cast(ledger_ops = %{}) do
    %__MODULE__{
      transaction_movements:
        ledger_ops
        |> Map.get(:transaction_movements, [])
        |> Enum.map(&TransactionMovement.cast/1),
      unspent_outputs:
        ledger_ops
        |> Map.get(:unspent_outputs, [])
        |> Enum.map(&UnspentOutput.cast/1),
      fee: Map.get(ledger_ops, :fee),
      consumed_inputs:
        ledger_ops
        |> Map.get(:consumed_inputs, [])
        |> Enum.map(&VersionedUnspentOutput.cast/1)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{
        transaction_movements: transaction_movements,
        unspent_outputs: unspent_outputs,
        fee: fee,
        consumed_inputs: consumed_inputs
      }) do
    %{
      transaction_movements: Enum.map(transaction_movements, &TransactionMovement.to_map/1),
      unspent_outputs: Enum.map(unspent_outputs, &UnspentOutput.to_map/1),
      fee: fee,
      consumed_inputs: Enum.map(consumed_inputs, &VersionedUnspentOutput.to_map/1)
    }
  end
end
