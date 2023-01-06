defmodule Archethic.P2P.Message.NotifyPreviousChain do
  @moduledoc """
  Represents a message used to notify previous chain storage nodes about the last transaction address
  """

  defstruct [:address]

  alias Archethic.Crypto
  alias Archethic.Replication
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          address: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{address: address}, _) do
    Replication.acknowledge_previous_storage_nodes(address)
    %Ok{}
  end
end
