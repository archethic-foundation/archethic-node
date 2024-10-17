defmodule Archethic.DB.EmbeddedImpl.Encoding do
  @moduledoc """
  Handle the encoding and decoding of the transaction and its fields
  """

  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ProofOfValidation
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Ownership
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.TokenLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.CrossValidationStamp

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  @doc """
  Encode a transaction
  """
  @spec encode(Transaction.t()) :: binary()
  def encode(
        tx = %Transaction{
          version: tx_version,
          address: address,
          type: type,
          data: %TransactionData{
            content: content,
            code: code,
            ownerships: ownerships,
            ledger: %Ledger{uco: uco_ledger, token: token_ledger},
            recipients: recipients
          },
          previous_public_key: previous_public_key,
          previous_signature: previous_signature,
          origin_signature: origin_signature,
          validation_stamp: %ValidationStamp{
            timestamp: timestamp,
            proof_of_work: proof_of_work,
            proof_of_integrity: proof_of_integrity,
            proof_of_election: proof_of_election,
            ledger_operations: %LedgerOperations{
              fee: fee,
              transaction_movements: transaction_movements,
              unspent_outputs: unspent_outputs,
              consumed_inputs: consumed_inputs
            },
            recipients: resolved_recipients,
            signature: validation_stamp_sig,
            protocol_version: protocol_version
          }
        }
      ) do
    ownerships_encoding =
      ownerships
      |> Enum.map(&Ownership.serialize(&1, tx_version))
      |> :erlang.list_to_binary()

    recipients_encoding =
      recipients
      |> Enum.map(&Recipient.serialize(&1, tx_version))
      |> :erlang.list_to_bitstring()

    transaction_movements_encoding =
      transaction_movements
      |> Enum.map(&TransactionMovement.serialize(&1, protocol_version))
      |> :erlang.list_to_binary()

    unspent_outputs_encoding =
      unspent_outputs
      |> Enum.map(&UnspentOutput.serialize(&1, protocol_version))
      |> :erlang.list_to_bitstring()

    consumed_inputs_encoding =
      consumed_inputs
      |> Enum.map(&VersionedUnspentOutput.serialize(&1))
      |> :erlang.list_to_bitstring()

    encoded_recipients_len = length(recipients) |> VarInt.from_value()
    encoded_ownerships_len = length(ownerships) |> VarInt.from_value()

    encoded_transaction_movements_len =
      transaction_movements
      |> length()
      |> VarInt.from_value()

    encoded_unspent_outputs_len =
      unspent_outputs
      |> length()
      |> VarInt.from_value()

    encoded_consumed_inputs_len =
      consumed_inputs
      |> length()
      |> VarInt.from_value()

    encoded_resolved_recipients_len =
      resolved_recipients
      |> length()
      |> VarInt.from_value()

    encoding =
      [
        {"address", address},
        {"type", <<Transaction.serialize_type(type)::8>>},
        {"data.content", content},
        {"data.code", TransactionData.compress_code(code)},
        {"data.ledger.uco", UCOLedger.serialize(uco_ledger, tx_version)},
        {"data.ledger.token", TokenLedger.serialize(token_ledger, tx_version)},
        {"data.ownerships", <<encoded_ownerships_len::binary, ownerships_encoding::binary>>},
        {"data.recipients", <<encoded_recipients_len::binary, recipients_encoding::bitstring>>},
        {"previous_public_key", previous_public_key},
        {"previous_signature", previous_signature},
        {"origin_signature", origin_signature},
        {"validation_stamp.timestamp", <<DateTime.to_unix(timestamp, :millisecond)::64>>},
        {"validation_stamp.proof_of_work", proof_of_work},
        {"validation_stamp.proof_of_election", proof_of_election},
        {"validation_stamp.proof_of_integrity", proof_of_integrity},
        {"validation_stamp.ledger_operations.transaction_movements",
         <<encoded_transaction_movements_len::binary, transaction_movements_encoding::binary>>},
        {"validation_stamp.ledger_operations.unspent_outputs",
         <<encoded_unspent_outputs_len::binary, unspent_outputs_encoding::bitstring>>},
        {"validation_stamp.ledger_operations.consumed_inputs",
         <<encoded_consumed_inputs_len::binary, consumed_inputs_encoding::bitstring>>},
        {"validation_stamp.ledger_operations.fee", <<fee::64>>},
        {"validation_stamp.recipients",
         <<encoded_resolved_recipients_len::binary,
           :erlang.list_to_binary(resolved_recipients)::binary>>},
        {"validation_stamp.signature", validation_stamp_sig},
        {"validation_stamp.protocol_version", <<protocol_version::32>>}
      ]
      |> Enum.concat(encode_validation_fields(tx))
      |> Enum.map(fn {column, value} ->
        wrapped_value = Utils.wrap_binary(value)

        <<byte_size(column)::8, byte_size(wrapped_value)::32, column::binary,
          wrapped_value::binary>>
      end)

    binary_encoding = :erlang.list_to_binary(encoding)
    tx_size = byte_size(binary_encoding)
    <<tx_size::32, tx_version::32, binary_encoding::binary>>
  end

  defp encode_validation_fields(%Transaction{
         validation_stamp: %ValidationStamp{protocol_version: protocol_version},
         cross_validation_stamps: cross_validation_stamps
       })
       when protocol_version <= 8 do
    cross_validation_stamps_encoding =
      cross_validation_stamps
      |> Enum.map(&CrossValidationStamp.serialize/1)
      |> :erlang.list_to_binary()

    [
      {"cross_validation_stamps",
       <<length(cross_validation_stamps)::8, cross_validation_stamps_encoding::binary>>}
    ]
  end

  defp encode_validation_fields(%Transaction{proof_of_validation: proof_of_validation}) do
    [{"proof_of_validation", ProofOfValidation.serialize(proof_of_validation)}]
  end

  def decode(_version, "type", <<type::8>>, acc),
    do: Map.put(acc, :type, Transaction.parse_type(type))

  def decode(_version, "data.content", content, acc) do
    put_in(acc, [Access.key(:data, %{}), :content], content)
  end

  def decode(_version, "data.code", code, acc) do
    put_in(acc, [Access.key(:data, %{}), :code], code)
  end

  def decode(tx_version, "data.ownerships", <<rest::binary>>, acc) do
    {nb, rest} = VarInt.get_value(rest)
    ownerships = deserialize_ownerships(rest, nb, [], tx_version)
    put_in(acc, [Access.key(:data, %{}), :ownerships], ownerships)
  end

  def decode(tx_version, "data.ledger.uco", data, acc) do
    {uco_ledger, _} = UCOLedger.deserialize(data, tx_version)
    put_in(acc, [Access.key(:data, %{}), Access.key(:ledger, %{}), :uco], uco_ledger)
  end

  def decode(tx_version, "data.ledger.token", data, acc) do
    {token_ledger, _} = TokenLedger.deserialize(data, tx_version)
    put_in(acc, [Access.key(:data, %{}), Access.key(:ledger, %{}), :token], token_ledger)
  end

  def decode(_version, "data.recipients", <<1::8, 0::8>>, acc), do: acc

  def decode(tx_version, "data.recipients", <<rest::binary>>, acc) do
    {nb, rest} = VarInt.get_value(rest)
    recipients = deserialize_recipients(rest, nb, [], tx_version)
    put_in(acc, [Access.key(:data, %{}), :recipients], recipients)
  end

  def decode(_version, "validation_stamp.timestamp", <<timestamp::64>>, acc) do
    put_in(
      acc,
      [Access.key(:validation_stamp, %{}), :timestamp],
      DateTime.from_unix!(timestamp, :millisecond)
    )
  end

  def decode(_version, "validation_stamp.proof_of_work", pow, acc) do
    put_in(acc, [Access.key(:validation_stamp, %{}), :proof_of_work], pow)
  end

  def decode(_version, "validation_stamp.proof_of_integrity", poi, acc) do
    put_in(acc, [Access.key(:validation_stamp, %{}), :proof_of_integrity], poi)
  end

  def decode(_version, "validation_stamp.proof_of_election", poe, acc) do
    put_in(acc, [Access.key(:validation_stamp, %{}), :proof_of_election], poe)
  end

  def decode(_version, "validation_stamp.ledger_operations.fee", <<fee::64>>, acc) do
    put_in(
      acc,
      [Access.key(:validation_stamp, %{}), Access.key(:ledger_operations, %{}), :fee],
      fee
    )
  end

  def decode(
        protocol_version,
        "validation_stamp.ledger_operations.transaction_movements",
        <<rest::binary>>,
        acc
      ) do
    {nb, rest} = rest |> VarInt.get_value()
    tx_movements = deserialize_transaction_movements(rest, nb, [], protocol_version)

    put_in(
      acc,
      [
        Access.key(:validation_stamp, %{}),
        Access.key(:ledger_operations, %{}),
        :transaction_movements
      ],
      tx_movements
    )
  end

  def decode(
        protocol_version,
        "validation_stamp.ledger_operations.unspent_outputs",
        <<rest::binary>>,
        acc
      ) do
    {nb, rest} = VarInt.get_value(rest)
    utxos = deserialize_unspent_outputs(rest, nb, [], protocol_version)

    put_in(
      acc,
      [Access.key(:validation_stamp, %{}), Access.key(:ledger_operations, %{}), :unspent_outputs],
      utxos
    )
  end

  def decode(
        _protocol_version,
        "validation_stamp.ledger_operations.consumed_inputs",
        <<rest::binary>>,
        acc
      ) do
    {nb, rest} = VarInt.get_value(rest)
    utxos = deserialize_versioned_unspent_output_list(rest, nb, [])

    put_in(
      acc,
      [Access.key(:validation_stamp, %{}), Access.key(:ledger_operations, %{}), :consumed_inputs],
      utxos
    )
  end

  def decode(_version, "validation_stamp.recipients", <<rest::binary>>, acc) do
    {nb, rest} = VarInt.get_value(rest)
    {recipients, _} = Utils.deserialize_addresses(rest, nb, [])
    put_in(acc, [Access.key(:validation_stamp, %{}), :recipients], recipients)
  end

  def decode(_version, "validation_stamp.signature", data, acc) do
    put_in(acc, [Access.key(:validation_stamp, %{}), :signature], data)
  end

  def decode(_version, "validation_stamp.protocol_version", <<version::32>>, acc) do
    put_in(acc, [Access.key(:validation_stamp, %{}), :protocol_version], version)
  end

  def decode(_version, "cross_validation_stamps", <<nb::8, rest::bitstring>>, acc) do
    stamps = deserialize_cross_validation_stamps(rest, nb, [])
    Map.put(acc, :cross_validation_stamps, stamps)
  end

  def decode(_version, "proof_of_validation", <<rest::bitstring>>, acc) do
    {proof_of_validation, _} = ProofOfValidation.deserialize(rest)
    Map.put(acc, :proof_of_validation, proof_of_validation)
  end

  def decode(_version, column, data, acc), do: Map.put(acc, column, data)

  defp deserialize_ownerships(_, 0, _, _), do: []

  defp deserialize_ownerships(_, nb, acc, _) when length(acc) == nb do
    Enum.reverse(acc)
  end

  defp deserialize_ownerships(rest, nb, acc, tx_version) do
    {ownership, rest} = Ownership.deserialize(rest, tx_version)
    deserialize_ownerships(rest, nb, [ownership | acc], tx_version)
  end

  defp deserialize_recipients(_rest, 0, _acc, _version), do: []

  defp deserialize_recipients(_rest, nb, acc, _version) when length(acc) == nb,
    do: Enum.reverse(acc)

  defp deserialize_recipients(rest, nb, acc, version) do
    {recipient, rest} = Recipient.deserialize(rest, version)
    deserialize_recipients(rest, nb, [recipient | acc], version)
  end

  defp deserialize_unspent_outputs(_, 0, _, _), do: []

  defp deserialize_unspent_outputs(_, nb, acc, _) when length(acc) == nb do
    Enum.reverse(acc)
  end

  defp deserialize_unspent_outputs(rest, nb, acc, protocol_version) do
    {utxo, rest} = UnspentOutput.deserialize(rest, protocol_version)
    deserialize_unspent_outputs(rest, nb, [utxo | acc], protocol_version)
  end

  defp deserialize_versioned_unspent_output_list(_rest, 0, _acc), do: []

  defp deserialize_versioned_unspent_output_list(_rest, nb_unspent_outputs, acc)
       when length(acc) == nb_unspent_outputs do
    Enum.reverse(acc)
  end

  defp deserialize_versioned_unspent_output_list(
         rest,
         nb_unspent_outputs,
         acc
       ) do
    {unspent_output, rest} = VersionedUnspentOutput.deserialize(rest)

    deserialize_versioned_unspent_output_list(rest, nb_unspent_outputs, [unspent_output | acc])
  end

  defp deserialize_transaction_movements(_, 0, _, _), do: []

  defp deserialize_transaction_movements(_, nb, acc, _) when length(acc) == nb do
    Enum.reverse(acc)
  end

  defp deserialize_transaction_movements(rest, nb, acc, protocol_version) do
    {tx_movement, rest} = TransactionMovement.deserialize(rest, protocol_version)
    deserialize_transaction_movements(rest, nb, [tx_movement | acc], protocol_version)
  end

  defp deserialize_cross_validation_stamps(_, 0, _), do: []

  defp deserialize_cross_validation_stamps(_rest, nb, acc) when length(acc) == nb do
    Enum.reverse(acc)
  end

  defp deserialize_cross_validation_stamps(rest, nb, acc) do
    {stamp, rest} = CrossValidationStamp.deserialize(rest)
    deserialize_cross_validation_stamps(rest, nb, [stamp | acc])
  end
end
