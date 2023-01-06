defmodule Archethic.P2P.Message.BeaconUpdate do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  @enforce_keys [:transaction_attestations]
  defstruct [:transaction_attestations]

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok

  @type t :: %__MODULE__{
          transaction_attestations: list(ReplicationAttestation.t())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: Ok.t()
  def process(%__MODULE__{transaction_attestations: transaction_attestations}, sender) do
    Enum.each(transaction_attestations, fn %ReplicationAttestation{
                                             transaction_summary: tx_summary
                                           } ->
      process(tx_summary, sender)
    end)

    %Ok{}
  end
end
