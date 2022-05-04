defmodule Archethic.P2P.Message.NodeAvailability do
  @moduledoc """
  Represents a message to indicate the availability
  """

  defstruct [:public_key]

  alias Archethic.Crypto

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }
end
