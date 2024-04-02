defmodule Archethic.P2P.Message.NotifyReplicationValidation do
  @moduledoc false

  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }

  alias Archethic.Utils
  alias Archethic.Mining
  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.Ok

  @spec process(t(), Message.metadata()) :: Ok.t()
  def process(%__MODULE__{address: address}, %{sender_public_key: node_public_key}) do
    Mining.notify_replication_validation(address, node_public_key)
    %Ok{}
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(bin) when is_bitstring(bin) do
    {address, rest} = Utils.deserialize_address(bin)

    {
      %__MODULE__{
        address: address
      },
      rest
    }
  end
end
