defmodule ArchEthic.P2P.Message.AddMiningContext do
  @moduledoc """
  Represents a message to request the add of the context of the mining from cross validation nodes
  to the coordinator
  """
  @enforce_keys [
    :address,
    :validation_node_public_key,
    :chain_storage_nodes_view,
    :beacon_storage_nodes_view,
    :previous_storage_nodes_public_keys
  ]
  defstruct [
    :address,
    :validation_node_public_key,
    :chain_storage_nodes_view,
    :beacon_storage_nodes_view,
    :previous_storage_nodes_public_keys
  ]

  alias ArchEthic.Crypto

  @type t :: %__MODULE__{
          address: Crypto.versioned_hash(),
          validation_node_public_key: Crypto.key(),
          chain_storage_nodes_view: bitstring(),
          beacon_storage_nodes_view: bitstring(),
          previous_storage_nodes_public_keys: list(Crypto.key())
        }
end
