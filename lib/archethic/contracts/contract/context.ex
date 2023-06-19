defmodule Archethic.Contracts.Contract.Context do
  @moduledoc """
  A structure to pass around between nodes that contains details about the contract execution.
  """

  alias Archethic.Contracts.Contract

  @enforce_keys [:status, :trigger, :trigger_type, :timestamp]
  defstruct [
    :status,
    :trigger,
    :trigger_type,
    :timestamp
  ]

  @type status :: :no_output | :tx_output | :failure

  @typedoc """
  Think of trigger as an "instance" of a trigger_type
  """
  @type trigger ::
          {:transaction, binary()}
          | {:oracle, binary()}
          | {:datetime, DateTime.t()}
          | {:interval, DateTime.t()}

  @type t :: %__MODULE__{
          status: status(),
          trigger: trigger(),
          trigger_type: Contract.trigger_type(),
          timestamp: DateTime.t()
        }
end
