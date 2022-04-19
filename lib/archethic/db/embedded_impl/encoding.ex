defmodule ArchEthic.DB.EmbeddedImpl.Encoding do
  @moduledoc """
  Handle the encoding and decoding of the transaction and its fields
  """

  alias ArchEthic.TransactionChain.Transaction
  alias ArchEthic.TransactionChain.TransactionData
  alias ArchEthic.TransactionChain.TransactionData.Ledger
  alias ArchEthic.TransactionChain.TransactionData.Ownership
  alias ArchEthic.TransactionChain.TransactionData.UCOLedger
  alias ArchEthic.TransactionChain.TransactionData.NFTLedger
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias ArchEthic.TransactionChain.Transaction.CrossValidationStamp

  alias ArchEthic.Utils

  @doc """
  Encode a transaction
  """
  @spec encode(Transaction.t()) :: binary()
  def encode(%Transaction{
        version: 1,
        address: address,
        type: type,
        data: %TransactionData{
          content: content,
          code: code,
          ownerships: ownerships,
          ledger: %Ledger{uco: uco_ledger, nft: nft_ledger},
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
            unspent_outputs: unspent_outputs
          },
          recipients: resolved_recipients,
          signature: validation_stamp_sig
        },
        cross_validation_stamps: cross_validation_stamps
      }) do
    ownerships_encoding =
      ownerships
      |> Enum.map(&Ownership.serialize/1)
      |> :erlang.list_to_binary()

    transaction_movements_encoding =
      transaction_movements
      |> Enum.map(&TransactionMovement.serialize/1)
      |> :erlang.list_to_binary()

    unspent_outputs_encoding =
      unspent_outputs
      |> Enum.map(&UnspentOutput.serialize/1)
      |> :erlang.list_to_binary()

    cross_validation_stamps_encoding =
      cross_validation_stamps
      |> Enum.map(&CrossValidationStamp.serialize/1)
      |> :erlang.list_to_binary()

    encoding =
      [
        {"address", address},
        {"type", <<Transaction.serialize_type(type)::8>>},
        {"data.content", content},
        {"data.code", code},
        {"data.ledger.uco", UCOLedger.serialize(uco_ledger)},
        {"data.ledger.nft", NFTLedger.serialize(nft_ledger)},
        {"data.ownerships", <<length(ownerships)::8, ownerships_encoding::binary>>},
        {"data.recipients",
         <<length(recipients)::8, :erlang.list_to_binary(recipients)::binary>>},
        {"previous_public_key", previous_public_key},
        {"previous_signature", previous_signature},
        {"origin_signature", origin_signature},
        {"validation_stamp.timestamp", <<DateTime.to_unix(timestamp, :millisecond)::64>>},
        {"validation_stamp.proof_of_work", proof_of_work},
        {"validation_stamp.proof_of_election", proof_of_election},
        {"validation_stamp.proof_of_integrity", proof_of_integrity},
        {"validation_stamp.ledger_operations.transaction_movements",
         <<length(transaction_movements)::8, transaction_movements_encoding::binary>>},
        {"validation_stamp.ledger_operations.unspent_outputs",
         <<length(unspent_outputs)::8, unspent_outputs_encoding::binary>>},
        {"validation_stamp.ledger_operations.fee", <<fee::64>>},
        {"validation_stamp.recipients",
         <<length(resolved_recipients)::8, :erlang.list_to_binary(resolved_recipients)::binary>>},
        {"validation_stamp.signature", validation_stamp_sig},
        {"cross_validation_stamps",
         <<length(cross_validation_stamps)::8, cross_validation_stamps_encoding::binary>>}
      ]
      |> Enum.map(fn {column, value} ->
        <<byte_size(column)::8, byte_size(value)::32, column::binary, value::binary>>
      end)

    binary_encoding = :erlang.list_to_binary(encoding)
    tx_size = byte_size(binary_encoding)
    <<tx_size::32, 1::32, binary_encoding::binary>>
  end

  def decode(_version, "type", <<type::8>>, acc),
    do: Map.put(acc, :type, Transaction.parse_type(type))

  def decode(_version, "data.content", content, acc) do
    put_in(acc, [Access.key(:data, %{}), :content], content)
  end

  def decode(_version, "data.code", code, acc) do
    put_in(acc, [Access.key(:data, %{}), :code], code)
  end

  def decode(_version, "data.ownerships", <<0>>, acc), do: acc

  def decode(_version, "data.ownerships", <<nb::8, rest::binary>>, acc) do
    {_, ownerships} =
      Enum.reduce(1..nb, {rest, []}, fn _, {data, acc} ->
        {ownership, rest} = Ownership.deserialize(data)
        {rest, [ownership | acc]}
      end)

    put_in(acc, [Access.key(:data, %{}), :ownerships], Enum.reverse(ownerships))
  end

  def decode(_version, "data.ledger.uco", data, acc) do
    {uco_ledger, _} = UCOLedger.deserialize(data)
    put_in(acc, [Access.key(:data, %{}), Access.key(:ledger, %{}), :uco], uco_ledger)
  end

  def decode(_version, "data.ledger.nft", data, acc) do
    {nft_ledger, _} = NFTLedger.deserialize(data)
    put_in(acc, [Access.key(:data, %{}), Access.key(:ledger, %{}), :nft], nft_ledger)
  end

  def decode(_version, "data.recipients", <<0>>, acc), do: acc

  def decode(_version, "data.recipients", <<nb::8, rest::binary>>, acc) do
    {_, recipients} =
      Enum.reduce(1..nb, {rest, []}, fn _, {data, acc} ->
        {address, rest} = Utils.deserialize_address(data)
        {rest, [address | acc]}
      end)

    put_in(acc, [Access.key(:data, %{}), :recipients], Enum.reverse(recipients))
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

  def decode(_version, "validation_stamp.ledger_operations.transaction_movements", <<0>>, acc),
    do: acc

  def decode(
        1,
        "validation_stamp.ledger_operations.transaction_movements",
        <<nb::8, rest::binary>>,
        acc
      ) do
    {_, movements} =
      Enum.reduce(1..nb, {rest, []}, fn _, {data, acc} ->
        {movement, rest} = TransactionMovement.deserialize(data)
        {rest, [movement | acc]}
      end)

    put_in(
      acc,
      [
        Access.key(:validation_stamp, %{}),
        Access.key(:ledger_operations, %{}),
        :transaction_movements
      ],
      Enum.reverse(movements)
    )
  end

  def decode(_version, "validation_stamp.ledger_operations.unspent_outputs", <<0>>, acc), do: acc

  def decode(
        _version,
        "validation_stamp.ledger_operations.unspent_outputs",
        <<nb::8, rest::binary>>,
        acc
      ) do
    {_, utxos} =
      Enum.reduce(1..nb, {rest, []}, fn _, {data, acc} ->
        {utxo, rest} = UnspentOutput.deserialize(data)
        {rest, [utxo | acc]}
      end)

    put_in(
      acc,
      [Access.key(:validation_stamp, %{}), Access.key(:ledger_operations, %{}), :unspent_outputs],
      Enum.reverse(utxos)
    )
  end

  def decode(_version, "validation_stamp.recipients", <<0>>, acc), do: acc

  def decode(_version, "validation_stamp.recipients", <<nb::8, rest::binary>>, acc) do
    {_, recipients} =
      Enum.reduce(1..nb, {rest, []}, fn _, {data, acc} ->
        {address, rest} = Utils.deserialize_address(data)
        {rest, [address | acc]}
      end)

    put_in(acc, [Access.key(:validation_stamp, %{}), :recipients], Enum.reverse(recipients))
  end

  def decode(_version, "validation_stamp.signature", data, acc) do
    put_in(acc, [Access.key(:validation_stamp, %{}), :signature], data)
  end

  def decode(_version, "cross_validation_stamps", <<nb::8, rest::bitstring>>, acc) do
    {_, stamps} =
      Enum.reduce(1..nb, {rest, []}, fn _, {data, acc} ->
        {stamp, rest} = CrossValidationStamp.deserialize(data)
        {rest, [stamp | acc]}
      end)

    Map.put(acc, :cross_validation_stamps, Enum.reverse(stamps))
  end

  def decode(_version, column, data, acc), do: Map.put(acc, column, data)
end
