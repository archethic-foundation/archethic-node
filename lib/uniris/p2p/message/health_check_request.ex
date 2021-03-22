defmodule Uniris.P2P.Message.HealthCheckRequest do
  @moduledoc """
  Represents a request to check the health of a list of node
  """
  alias Uniris.Crypto

  defstruct [:node_public_keys]

  @type t :: %__MODULE__{
          node_public_keys: list(Crypto.key())
        }
end
