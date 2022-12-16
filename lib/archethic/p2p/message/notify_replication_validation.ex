defmodule Archethic.P2P.Message.NotifyReplicationValidation do
  @moduledoc false

  @enforce_keys [:address, :node_public_key]
  defstruct [:address, :node_public_key]

  @type t :: %__MODULE__{
          address: binary(),
          node_public_key: binary()
        }

  alias Archethic.Utils

  def serialize(%__MODULE__{address: address, node_public_key: node_public_key}) do
    <<address::binary, node_public_key::binary>>
  end

  def deserialize(bin) when is_bitstring(bin) do
    {address, rest} = Utils.deserialize_address(bin)
    {public_key, rest} = Utils.deserialize_public_key(rest)

    {
      %__MODULE__{
        address: address,
        node_public_key: public_key
      },
      rest
    }
  end
end
