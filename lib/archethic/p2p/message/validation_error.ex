defmodule Archethic.P2P.Message.ValidationError do
  @moduledoc """
  Represents an error message
  """
  alias ArchethicWeb.TransactionSubscriber
  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok

  defstruct [:context, :reason, :address]

  @type t :: %__MODULE__{
          context: :invalid_transaction | :network_issue,
          reason: binary(),
          address: binary()
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{context: context, reason: reason, address: address}, _) do
    TransactionSubscriber.report_error(address, context, reason)
    %Ok{}
  end
end
