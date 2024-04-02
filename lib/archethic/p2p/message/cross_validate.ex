defmodule Archethic.P2P.Message.CrossValidate do
  @moduledoc """
  Represents a message to request the cross validation of a validation stamp
  """
  @enforce_keys [
    :address,
    :validation_stamp,
    :replication_tree,
    :confirmed_validation_nodes,
    :aggregated_utxos
  ]
  defstruct [
    :address,
    :validation_stamp,
    :replication_tree,
    :confirmed_validation_nodes,
    :aggregated_utxos
  ]

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.Mining
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok
  alias Archethic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          validation_stamp: ValidationStamp.t(),
          replication_tree: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          confirmed_validation_nodes: bitstring(),
          aggregated_utxos: list(VersionedUnspentOutput.t())
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(
        %__MODULE__{
          address: tx_address,
          validation_stamp: stamp,
          replication_tree: replication_tree,
          confirmed_validation_nodes: confirmed_validation_nodes,
          aggregated_utxos: aggregated_utxos
        },
        _
      ) do
    Mining.cross_validate(
      tx_address,
      stamp,
      replication_tree,
      confirmed_validation_nodes,
      aggregated_utxos
    )

    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{
        address: address,
        validation_stamp: stamp,
        replication_tree: %{
          chain: chain_replication_tree,
          beacon: beacon_replication_tree,
          IO: io_replication_tree
        },
        confirmed_validation_nodes: confirmed_validation_nodes,
        aggregated_utxos: aggregated_utxos
      }) do
    nb_validation_nodes = length(chain_replication_tree)
    chain_tree_size = chain_replication_tree |> List.first() |> bit_size()
    beacon_tree_size = beacon_replication_tree |> List.first() |> bit_size()

    io_tree_size =
      case io_replication_tree do
        [] ->
          0

        tree ->
          tree
          |> List.first()
          |> bit_size()
      end

    size_aggregated_utxos =
      aggregated_utxos
      |> length()
      |> Utils.VarInt.from_value()

    aggregated_utxos_bin =
      aggregated_utxos
      |> Enum.map(&VersionedUnspentOutput.serialize/1)
      |> :erlang.list_to_bitstring()

    <<address::binary, ValidationStamp.serialize(stamp)::bitstring, nb_validation_nodes::8,
      chain_tree_size::8, :erlang.list_to_bitstring(chain_replication_tree)::bitstring,
      beacon_tree_size::8, :erlang.list_to_bitstring(beacon_replication_tree)::bitstring,
      io_tree_size::8, :erlang.list_to_bitstring(io_replication_tree)::bitstring,
      bit_size(confirmed_validation_nodes)::8, confirmed_validation_nodes::bitstring,
      size_aggregated_utxos::binary, aggregated_utxos_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {validation_stamp, <<nb_validations::8, rest::bitstring>>} = ValidationStamp.deserialize(rest)

    <<chain_tree_size::8, rest::bitstring>> = rest

    {chain_tree, <<beacon_tree_size::8, rest::bitstring>>} =
      deserialize_bit_sequences(rest, nb_validations, chain_tree_size, [])

    {beacon_tree, <<io_tree_size::8, rest::bitstring>>} =
      deserialize_bit_sequences(rest, nb_validations, beacon_tree_size, [])

    {io_tree, rest} =
      if io_tree_size > 0 do
        deserialize_bit_sequences(rest, nb_validations, io_tree_size, [])
      else
        {[], rest}
      end

    <<nb_cross_validation_nodes::8,
      cross_validation_node_confirmation::bitstring-size(nb_cross_validation_nodes),
      rest::bitstring>> = rest

    {size_aggregated_utxos, rest} = Utils.VarInt.get_value(rest)

    {aggregated_utxos, rest} =
      deserialize_versioned_unspent_outputs(rest, size_aggregated_utxos, [])

    {%__MODULE__{
       address: address,
       validation_stamp: validation_stamp,
       replication_tree: %{
         chain: chain_tree,
         beacon: beacon_tree,
         IO: io_tree
       },
       confirmed_validation_nodes: cross_validation_node_confirmation,
       aggregated_utxos: aggregated_utxos
     }, rest}
  end

  defp deserialize_bit_sequences(rest, nb_sequences, _sequence_size, acc)
       when length(acc) == nb_sequences do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_bit_sequences(rest, nb_sequences, sequence_size, acc) do
    <<sequence::bitstring-size(sequence_size), rest::bitstring>> = rest
    deserialize_bit_sequences(rest, nb_sequences, sequence_size, [sequence | acc])
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
end
