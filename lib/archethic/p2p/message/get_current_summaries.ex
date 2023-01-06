defmodule Archethic.P2P.Message.GetCurrentSummaries do
  @moduledoc """
  Represents a message to get the current beacon slots for a subset
  """

  @enforce_keys [:subsets]
  defstruct [:subsets]

  alias Archethic.Crypto
  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.Subset
  alias Archethic.P2P.Message.TransactionSummaryList

  @type t :: %__MODULE__{
          subsets: list(binary())
        }

  @spec encode(t()) :: bitstring()
  def encode(%__MODULE__{subsets: subsets}) do
    subsets_bin = :erlang.list_to_binary(subsets)
    <<32::8, length(subsets)::8, subsets_bin::binary>>
  end

  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionSummaryList.t()
  def process(%__MODULE__{subsets: subsets}, _) do
    transaction_summaries =
      Enum.flat_map(subsets, fn subset ->
        transaction_summaries = BeaconChain.get_summary_slots(subset)

        %Slot{transaction_attestations: transaction_attestations} =
          Subset.get_current_slot(subset)

        Enum.reduce(
          transaction_attestations,
          transaction_summaries,
          &[&1.transaction_summary | &2]
        )
      end)

    %TransactionSummaryList{
      transaction_summaries: transaction_summaries
    }
  end
end
