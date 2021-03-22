defmodule Uniris.P2P.Message.BatchRequests do
  @moduledoc """
  Represents a message to hold a set of message to execute at once
  """
  defstruct [:requests]

  alias Uniris.P2P.Message

  @type t :: %__MODULE__{
          requests: list(Message.t())
        }
end
