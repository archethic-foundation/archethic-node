defmodule Uniris.P2P.Message.SubscribeTransactionValidation do
  @moduledoc """
  Represents message to subscribe to a transaction validation for a given address
  """

  @enforce_keys [:address]
  defstruct [:address]

  @type t :: %__MODULE__{
          address: binary()
        }
end
