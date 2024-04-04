defmodule Archethic.P2P.Message.GetCurrentReplicationsAttestations do
  @moduledoc """
  Represents a message to get the current beacon slots for a subset
  """

  @enforce_keys [:subsets]
  defstruct [:subsets]

  alias Archethic.Crypto
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Subset
  alias Archethic.P2P.Message.ReplicationAttestationList

  @type t :: %__MODULE__{
          subsets: list(binary())
        }

  @spec process(__MODULE__.t(), Crypto.key()) :: ReplicationAttestationList.t()
  def process(%__MODULE__{subsets: subsets}, _) do
    replications_attestations =
      Enum.flat_map(subsets, fn subset ->
        %Slot{transaction_attestations: replication_attestations} =
          Subset.get_current_slot(subset)

        replication_attestations
      end)

    %ReplicationAttestationList{
      replications_attestations: replications_attestations
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{subsets: subsets}) do
    subsets_bin = :erlang.list_to_binary(subsets)
    <<length(subsets)::16, subsets_bin::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<nb_subsets::16, rest::binary>>) do
    subsets_bin = :binary.part(rest, 0, nb_subsets)
    subsets = for <<subset::8 <- subsets_bin>>, do: <<subset>>
    {%__MODULE__{subsets: subsets}, <<>>}
  end
end
