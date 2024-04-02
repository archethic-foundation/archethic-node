defmodule Archethic.P2P.Message.NotifyPreviousChain do
  @moduledoc """
  Represents a message used to notify previous chain storage nodes about the last transaction address
  """

  defstruct [:address]

  alias Archethic.Utils
  alias Archethic.Replication
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          address: binary()
        }

  @spec process(__MODULE__.t(), Message.metadata()) :: Ok.t()
  def process(%__MODULE__{address: address}, _) do
    Replication.acknowledge_previous_storage_nodes(address)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {address, rest} = Utils.deserialize_address(rest)
    {%__MODULE__{address: address}, rest}
  end
end
