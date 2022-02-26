defmodule ArchEthic.SelfRepair.Sync.BeaconSummaryAggregate do
  @moduledoc """
  Represents an aggregate of multiple beacon summary from multiple subsets for a given date

  This will help the self-sepair to maintain an aggregated and ordered view of items to synchronize and to resolve
  """

  defstruct [:summary_time, transaction_summaries: [], p2p_availabilities: %{}]

  alias ArchEthic.BeaconChain.ReplicationAttestation
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.TransactionChain.TransactionSummary

  @type t :: %__MODULE__{
          summary_time: DateTime.t(),
          transaction_summaries: list(TransactionSummary.t()),
          p2p_availabilities: %{
            (subset :: binary()) => %{
              node_availabilities: bitstring(),
              node_average_availabilities: list(float())
            }
          }
        }

  @doc """
  Initialize the aggregate by defining the summary time for example

  If the aggregate is already initialized, the call will be skipped
  """
  @spec initialize(t(), BeaconSummary.t()) :: t()
  def initialize(
        aggregate = %__MODULE__{summary_time: nil},
        %BeaconSummary{summary_time: summary_time}
      ) do
    %{aggregate | summary_time: summary_time}
  end

  def initialize(
        aggregate = %__MODULE__{},
        _summary
      ) do
    aggregate
  end

  @doc """
  Add a transaction summaries to the aggregate by providing uniqueness and sorting
  """
  @spec add_transaction_summaries(t(), BeaconSummary.t()) :: t()
  def add_transaction_summaries(
        aggregate = %__MODULE__{},
        %BeaconSummary{transaction_attestations: transaction_attestations}
      ) do
    transaction_attestations
    |> Enum.reduce(aggregate, fn %ReplicationAttestation{transaction_summary: transaction_summary},
                                 acc ->
      Map.update!(acc, :transaction_summaries, fn transaction_summaries ->
        [transaction_summary | transaction_summaries]
        |> Enum.uniq_by(& &1.address)
        |> Enum.sort_by(& &1.timestamp, {:asc, DateTime})
      end)
    end)
  end

  @doc """
  Add P2P availabilities to the aggregate

  It extracts node's availability from the bitstring availabilities and map its average availability
  """
  @spec add_p2p_availabilities(
          t(),
          BeaconSummary.t()
        ) :: t()
  def add_p2p_availabilities(
        aggregate = %__MODULE__{},
        %BeaconSummary{
          subset: subset,
          node_availabilities: node_availabilities,
          node_average_availabilities: node_average_availabilities
        }
      )
      when bit_size(node_availabilities) > 0 and length(node_average_availabilities) > 0 do
    Map.update!(
      aggregate,
      :p2p_availabilities,
      &Map.put(&1, subset, %{
        node_availabilities: node_availabilities,
        node_average_availabilities: node_average_availabilities
      })
    )
  end

  def add_p2p_availabilities(aggregate = %__MODULE__{}, _), do: aggregate

  @doc """
  Determine when the aggregate is empty
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{transaction_summaries: [], p2p_availabilities: p2p_availabilities})
      when map_size(p2p_availabilities) == 0,
      do: true

  def empty?(%__MODULE__{}), do: false
end
