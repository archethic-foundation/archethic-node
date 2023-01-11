defmodule Archethic.P2P.Message.NotifyReplicationValidation do
  @moduledoc false

  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }

  alias Archethic.Utils

  def serialize(%__MODULE__{address: address}) do
    <<address::binary>>
  end

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
