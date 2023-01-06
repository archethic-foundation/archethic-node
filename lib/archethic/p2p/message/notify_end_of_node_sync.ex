defmodule Archethic.P2P.Message.NotifyEndOfNodeSync do
  @moduledoc """
  Represents a message to request to add an information in the beacon chain regarding a node readyness

  This message is used during the node bootstrapping.
  """
  @enforce_keys [:node_public_key, :timestamp]
  defstruct [:node_public_key, :timestamp]

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          node_public_key: Crypto.key(),
          timestamp: DateTime.t()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{node_public_key: public_key, timestamp: timestamp}, _) do
    BeaconChain.add_end_of_node_sync(public_key, timestamp)
    %Ok{}
  end
end
