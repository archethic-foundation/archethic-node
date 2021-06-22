defmodule ArchEthic.P2P.Message.NodeAvailability do
  @moduledoc """
  Represents a message to indicate the availability
  """

  defstruct [:public_key]

  alias ArchEthic.Crypto

  @type t :: %__MODULE__{
          public_key: Crypto.key()
        }
end
