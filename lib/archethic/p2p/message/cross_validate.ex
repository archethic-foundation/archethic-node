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
