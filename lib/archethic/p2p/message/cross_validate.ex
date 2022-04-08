defmodule ArchEthic.P2P.Message.CrossValidate do
  @moduledoc """
  Represents a message to request the cross validation of a validation stamp
  """
  @enforce_keys [
    :address,
    :validation_stamp,
    :replication_tree,
    :confirmed_validation_nodes
  ]
  defstruct [:address, :validation_stamp, :replication_tree, :confirmed_validation_nodes]

  alias ArchEthic.Crypto

  alias ArchEthic.Mining

  alias ArchEthic.P2P.Message.Ok

  alias ArchEthic.TransactionChain.Transaction.ValidationStamp

  alias ArchEthic.Utils

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          validation_stamp: ValidationStamp.t(),
          replication_tree: %{
            chain: list(bitstring()),
            beacon: list(bitstring()),
            IO: list(bitstring())
          },
          confirmed_validation_nodes: bitstring()
        }

  use ArchEthic.P2P.Message, message_id: 9

  def encode(%__MODULE__{
        address: address,
        validation_stamp: stamp,
        replication_tree: %{
          chain: chain_replication_tree,
          beacon: beacon_replication_tree,
          IO: io_replication_tree
        },
        confirmed_validation_nodes: confirmed_validation_nodes
      }) do
    nb_validation_nodes = length(chain_replication_tree)
    tree_size = chain_replication_tree |> List.first() |> bit_size()

    <<address::binary, ValidationStamp.serialize(stamp)::bitstring, nb_validation_nodes::8,
      tree_size::8, :erlang.list_to_bitstring(chain_replication_tree)::bitstring,
      :erlang.list_to_bitstring(beacon_replication_tree)::bitstring,
      :erlang.list_to_bitstring(io_replication_tree)::bitstring,
      bit_size(confirmed_validation_nodes)::8, confirmed_validation_nodes::bitstring>>
  end

  def decode(message) do
    {address, rest} = Utils.deserialize_address(message)
    {validation_stamp, rest} = ValidationStamp.deserialize(rest)

    <<nb_validations::8, tree_size::8, rest::bitstring>> = rest

    {chain_tree, rest} = deserialize_bit_sequences(rest, nb_validations, tree_size, [])
    {beacon_tree, rest} = deserialize_bit_sequences(rest, nb_validations, tree_size, [])
    {io_tree, rest} = deserialize_bit_sequences(rest, nb_validations, tree_size, [])

    <<nb_cross_validation_nodes::8,
      cross_validation_node_confirmation::bitstring-size(nb_cross_validation_nodes),
      rest::bitstring>> = rest

    {%__MODULE__{
       address: address,
       validation_stamp: validation_stamp,
       replication_tree: %{
         chain: chain_tree,
         beacon: beacon_tree,
         IO: io_tree
       },
       confirmed_validation_nodes: cross_validation_node_confirmation
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

  def process(%__MODULE__{
        address: tx_address,
        validation_stamp: stamp,
        replication_tree: replication_tree,
        confirmed_validation_nodes: confirmed_validation_nodes
      }) do
    Mining.cross_validate(tx_address, stamp, replication_tree, confirmed_validation_nodes)
    %Ok{}
  end
end
