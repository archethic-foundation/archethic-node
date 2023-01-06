defmodule Archethic.P2P.Message.CrossValidate do
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

  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.Mining
  alias Archethic.P2P.Message.Ok

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

  @spec encode(t()) :: bitstring()
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

    <<9::8, address::binary, ValidationStamp.serialize(stamp)::bitstring, nb_validation_nodes::8,
      chain_tree_size::8, :erlang.list_to_bitstring(chain_replication_tree)::bitstring,
      beacon_tree_size::8, :erlang.list_to_bitstring(beacon_replication_tree)::bitstring,
      io_tree_size::8, :erlang.list_to_bitstring(io_replication_tree)::bitstring,
      bit_size(confirmed_validation_nodes)::8, confirmed_validation_nodes::bitstring>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(
        %__MODULE__{
          address: tx_address,
          validation_stamp: stamp,
          replication_tree: replication_tree,
          confirmed_validation_nodes: confirmed_validation_nodes
        },
        _
      ) do
    Mining.cross_validate(tx_address, stamp, replication_tree, confirmed_validation_nodes)
    %Ok{}
  end
end
