defmodule ArchEthic.P2P.Message.GetFirstPublicKey do
  @moduledoc """
  Represents a message to request the first public key from a transaction chain
  """

  @enforce_keys [:public_key]
  defstruct [:public_key]

  @type t() :: %__MODULE__{
          public_key: binary()
        }
end
