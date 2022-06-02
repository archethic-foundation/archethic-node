defmodule Archethic.SelfRepair.Sync.BeaconSummaryAggregate do
  @moduledoc """
  Represents an aggregate of multiple beacon summary from multiple subsets for a given date

  This will help the self-sepair to maintain an aggregated and ordered view of items to synchronize and to resolve
  """

  defstruct [:summary_time, transaction_summaries: [], p2p_availabilities: %{}]

  alias Archethic.BeaconChain.Summary, as: BeaconSummary
  alias Archethic.TransactionChain.TransactionSummary
  alias Archethic.Crypto

  @type t :: %__MODULE__{
          summary_time: DateTime.t(),
          transaction_summaries: list(TransactionSummary.t()),
          p2p_availabilities: %{
            (subset :: binary()) => %{
              node_availabilities: bitstring(),
              node_average_availabilities: list(float()),
              end_of_node_synchronizations: list(Crypto.key())
            }
          }
        }

  @doc """
  Aggregate a new BeaconChain's summary
  """
  @spec add_summary(t(), BeaconSummary.t()) :: t()
  def add_summary(
        agg = %__MODULE__{},
        %BeaconSummary{
          subset: subset,
          transaction_attestations: attestations,
          node_availabilities: node_availabilities,
          node_average_availabilities: node_average_availabilities,
          end_of_node_synchronizations: end_of_node_synchronizations
        }
      ) do
    transaction_summaries =
      attestations
      |> Enum.map(& &1.transaction_summary)
      |> Enum.concat(agg.transaction_summaries)
      |> Enum.uniq_by(& &1.address)
      |> Enum.sort_by(& &1.timestamp, {:asc, DateTime})

    p2p_availabilities =
      Map.put(agg.p2p_availabilities, subset, %{
        node_availabilities: node_availabilities,
        node_average_availabilities: node_average_availabilities,
        end_of_node_synchronizations: end_of_node_synchronizations
      })

    %{agg | transaction_summaries: transaction_summaries, p2p_availabilities: p2p_availabilities}
  end

  @doc """
  Determine when the aggregate is empty
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{transaction_summaries: [], p2p_availabilities: p2p_availabilities})
      when map_size(p2p_availabilities) == 0,
      do: true

  def empty?(%__MODULE__{}), do: false
end
