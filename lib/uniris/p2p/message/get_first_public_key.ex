defmodule Uniris.P2P.Message.GetFirstPublicKey do
  @moduledoc """
  Represents a message to request the first public key from a transaction chain
  """

  @enforce_keys [:address]
  defstruct [:address]

  @type t() :: %__MODULE__{
          address: binary()
        }
end
