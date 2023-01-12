defmodule Archethic.P2P.Message.BeaconUpdate do
  @moduledoc """
  Represents a message to get a beacon updates
  """

  @enforce_keys [:transaction_attestations]
  defstruct [:transaction_attestations]

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.Crypto
  alias Archethic.P2P.Message.Ok

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

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

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{transaction_attestations: transaction_attestations}) do
    transaction_attestations_bin =
      transaction_attestations
      |> Enum.map(&ReplicationAttestation.serialize/1)
      |> :erlang.list_to_bitstring()

    encoded_transaction_attestations_len = length(transaction_attestations) |> VarInt.from_value()

    <<encoded_transaction_attestations_len::binary, transaction_attestations_bin::bitstring>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<rest::bitstring>>) do
    {nb_transaction_attestations, rest} = rest |> VarInt.get_value()

    {transaction_attestations, rest} =
      Utils.deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    {
      %__MODULE__{
        transaction_attestations: transaction_attestations
      },
      rest
    }
  end
end
