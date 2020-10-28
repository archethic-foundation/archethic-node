defmodule Uniris.P2P.Message.GetP2PView do
  @moduledoc """
  Represents a request to get the P2P view from a list of nodes
  """

  defstruct [:node_public_keys]

  @type t :: %__MODULE__{
          node_public_keys: list(Crypto.key())
        }
end
