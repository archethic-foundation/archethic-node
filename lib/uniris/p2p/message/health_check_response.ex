defmodule Uniris.P2P.Message.HealthCheckResponse do
  @moduledoc """
  Represents a response after the health check of a node
  """
  defstruct [:service]

  @type t :: %__MODULE__{
          status: integer
        }
end
