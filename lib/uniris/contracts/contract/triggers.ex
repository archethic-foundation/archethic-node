defmodule Uniris.Contracts.Contract.Triggers do
  @moduledoc """
  Represents the smart contract triggers
  """

  defstruct [:datetime, :interval]

  @typedoc """
  Smart contract triggers are defined by:
  - Datetime: DateTime when the contract must be triggered
  - Interval: Recurrent when the contract must be triggered (Cron like)
  """
  @type t :: %__MODULE__{
          datetime: DateTime.t(),
          interval: binary()
        }
end
