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

  @spec process(__MODULE__.t(), Crypto.key()) :: TransactionSummaryList.t()
  def process(%__MODULE__{subsets: subsets}, _) do
    transaction_summaries =
      Task.async_stream(
        subsets,
        fn subset ->
          %Slot{transaction_attestations: transaction_attestations} =
            Subset.get_current_slot(subset)

          transaction_attestations
          |> Enum.map(& &1.transaction_summary)
          |> Enum.concat(BeaconChain.get_summary_slots(subset))
        end,
        on_timeout: :kill_task
      )
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Enum.flat_map(fn {:ok, x} -> x end)

    %TransactionSummaryList{
      transaction_summaries: transaction_summaries
    }
  end

  @spec serialize(t()) :: bitstring()
  def serialize(%__MODULE__{subsets: subsets}) do
    subsets_bin = :erlang.list_to_binary(subsets)
    <<length(subsets)::16, subsets_bin::binary>>
  end

  @spec deserialize(bitstring()) :: {t(), bitstring}
  def deserialize(<<nb_subsets::16, subsets_bin::binary-size(nb_subsets), rest::bitstring>>) do
    subsets = for <<subset::8 <- subsets_bin>>, do: <<subset>>
    {%__MODULE__{subsets: subsets}, rest}
  end
end
