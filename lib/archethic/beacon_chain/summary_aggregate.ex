defmodule Archethic.BeaconChain.SummaryAggregate do
  @moduledoc """
  Represents an aggregate of multiple beacon summary from multiple subsets for a given date

  This will help the self-sepair to maintain an aggregated and ordered view of items to synchronize and to resolve
  """

  defstruct [:summary_time, transaction_summaries: [], p2p_availabilities: %{}]

  alias Archethic.Crypto

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Summary, as: BeaconSummary

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils

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
          summary_time: summary_time,
          transaction_attestations: transaction_attestations,
          node_availabilities: node_availabilities,
          node_average_availabilities: node_average_availabilities,
          end_of_node_synchronizations: end_of_node_synchronizations
        }
      ) do
    valid_attestations? =
      Enum.all?(transaction_attestations, fn attestation ->
        ReplicationAttestation.validate(attestation) == :ok
      end)

    if valid_attestations? do
      agg
      |> Map.update!(
        :transaction_summaries,
        fn prev ->
          transaction_attestations
          |> Enum.map(& &1.transaction_summary)
          |> Enum.concat(prev)
        end
      )
      |> update_in(
        [
          Access.key(:p2p_availabilities, %{}),
          Access.key(subset, %{
            node_availabilities: [],
            node_average_availabilities: [],
            end_of_node_synchronizations: []
          })
        ],
        fn prev ->
          prev
          |> Map.update!(
            :node_availabilities,
            &Enum.concat(&1, [Utils.bitstring_to_integer_list(node_availabilities)])
          )
          |> Map.update!(
            :node_average_availabilities,
            &Enum.concat(&1, [node_average_availabilities])
          )
          |> Map.update!(
            :end_of_node_synchronizations,
            &Enum.concat(&1, end_of_node_synchronizations)
          )
        end
      )
      |> Map.update(:summary_time, summary_time, fn
        nil -> summary_time
        prev -> prev
      end)
    else
      agg
    end
  end

  @doc """
  Aggregate summaries batch
  """
  @spec aggregate(t()) :: t()
  def aggregate(agg = %__MODULE__{}) do
    agg
    |> Map.update!(:transaction_summaries, fn transactions ->
      transactions
      |> Enum.uniq_by(& &1.address)
      |> Enum.sort_by(& &1.timestamp, {:asc, DateTime})
    end)
    |> Map.update!(:p2p_availabilities, fn availabilities_by_subject ->
      availabilities_by_subject
      |> Enum.map(fn {subset, data} ->
        {subset,
         data
         |> Map.update!(:node_availabilities, &aggregate_node_availabilities/1)
         |> Map.update!(:node_average_availabilities, &aggregate_node_average_availabilities/1)}
      end)
      |> Enum.into(%{})
    end)
  end

  defp aggregate_node_availabilities(node_availabilities) do
    node_availabilities
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.map(fn availabilities ->
      # Get the mode of the availabilities
      frequencies = Enum.frequencies(availabilities)
      online_frequencies = Map.get(frequencies, 1, 0)
      offline_frequencies = Map.get(frequencies, 0, 0)

      if online_frequencies >= offline_frequencies do
        1
      else
        0
      end
    end)
    |> List.flatten()
    |> Enum.map(&<<&1::1>>)
    |> :erlang.list_to_bitstring()
  end

  defp aggregate_node_average_availabilities(avg_availabilities) do
    avg_availabilities
    |> Enum.zip()
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.map(fn avg_availabilities ->
      Float.round(Enum.sum(avg_availabilities) / length(avg_availabilities), 3)
    end)
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
