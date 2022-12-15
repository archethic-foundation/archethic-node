defmodule Archethic.P2P.Message.ReplicatePendingTransactionChain do
  @moduledoc false

  defstruct [:address]

  alias Archethic.Utils

  @type t() :: %__MODULE__{
          address: binary()
        }

  def serialize(%__MODULE__{address: address}) do
    address
  end

  def deserialize(bin) do
    {address, rest} = Utils.deserialize_address(bin)

    {
      %__MODULE__{
        address: address
      },
      rest
    }
  end
end
