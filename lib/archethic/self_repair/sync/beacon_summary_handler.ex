defmodule Archethic.SelfRepair.Sync.BeaconSummaryHandler do
  @moduledoc false

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Subset.P2PSampling
  alias Archethic.BeaconChain.Summary, as: BeaconSummary

  alias Archethic.Crypto

  alias Archethic.DB

  alias Archethic.P2P
  alias Archethic.P2P.Message.GetBeaconSummary
  alias Archethic.P2P.Message.NotFound
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.SelfRepair.Sync.BeaconSummaryAggregate
  alias __MODULE__.TransactionHandler

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain

  alias Archethic.Utils

  require Logger

  @doc """
  """
  @spec get_full_beacon_summary(DateTime.t(), binary(), list(Node.t())) :: BeaconSummary.t()
  def get_full_beacon_summary(summary_time, subset, nodes) do
    summary_address = Crypto.derive_beacon_chain_address(subset, summary_time, true)

    conflict_resolver = fn results ->
      acc = %{
        transaction_attestations: [],
        node_availabilities: [],
        node_average_availabilities: [],
        end_of_node_synchronizations: []
      }

      results
      |> Enum.filter(&match?(%BeaconSummary{}, &1))
      |> Enum.reduce(acc, &do_reduce_beacon_summaries/2)
      |> aggregate_summary(summary_time, subset)
    end

    case P2P.quorum_read(
           nodes,
           %GetBeaconSummary{address: summary_address},
           conflict_resolver,
           length(nodes)
         ) do
      {:ok, summary = %BeaconSummary{}} ->
        summary

      _ ->
        %BeaconSummary{summary_time: summary_time, subset: subset}
    end
  end

  defp do_reduce_beacon_summaries(
         %BeaconSummary{
           transaction_attestations: transaction_attestations,
           node_availabilities: node_availabilities,
           node_average_availabilities: node_average_availabilities,
           end_of_node_synchronizations: end_of_node_synchronizations
         },
         acc
       ) do
    valid_attestations? =
      Enum.all?(transaction_attestations, fn attestation ->
        ReplicationAttestation.validate(attestation) == :ok
      end)

    if valid_attestations? do
      acc
      |> Map.update!(
        :transaction_attestations,
        &Enum.concat(transaction_attestations, &1)
      )
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
    else
      acc
    end
  end

  defp aggregate_summary(
         %{
           transaction_attestations: transaction_attestations,
           node_availabilities: node_availabilities,
           node_average_availabilities: node_average_availabilities,
           end_of_node_synchronizations: end_of_node_synchronizations
         },
         summary_time,
         subset
       ) do
    %BeaconSummary{
      subset: subset,
      summary_time: summary_time,
      transaction_attestations:
        Enum.uniq_by(List.flatten(transaction_attestations), & &1.transaction_summary.address),
      node_availabilities: aggregate_node_availabilities(node_availabilities),
      node_average_availabilities:
        aggregate_node_average_availabilities(node_average_availabilities),
      end_of_node_synchronizations: end_of_node_synchronizations
    }
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
      Enum.sum(avg_availabilities) / length(avg_availabilities)
    end)
  end

  @doc """
  Download the beacon summary from the closest nodes given
  """
  @spec download_summary(Crypto.versioned_hash(), list(Node.t()), binary()) ::
          {:ok, BeaconSummary.t() | NotFound.t()} | {:error, any()}
  def download_summary(_beacon_address, [], _), do: {:ok, %NotFound{}}

  def download_summary(beacon_address, nodes, patch) do
    conflict_resolver = fn results ->
      acc = %{
        transaction_attestations: [],
        node_availabilities: [],
        node_average_availabilities: []
      }

      %{transaction_attestations: transaction_attestations} =
        results
        |> Enum.filter(&match?(%BeaconSummary{}, &1))
        |> Enum.reduce(acc, &do_reduce_beacon_summaries/2)

      %BeaconSummary{transaction_attestations: transaction_attestations}
    end

    nodes
    |> P2P.nearest_nodes(patch)
    |> P2P.quorum_read(
      %GetBeaconSummary{address: beacon_address},
      conflict_resolver,
      length(nodes)
    )
  end

  @doc """
  Process beacon summary to synchronize the transactions involving.

  Each transactions from the beacon summary will be analyzed to determine
  if the node is a storage node for this transaction. If so, it will download the
  transaction from the closest storage nodes and replicate it locally.

  The P2P view will also be updated if some node information are inside the beacon chain to determine
  the readiness or the availability of a node.

  Also, the  number of transaction received during the beacon summary interval will be stored.
  """
  @spec process_summary_aggregate(BeaconSummaryAggregate.t(), binary()) :: :ok
  def process_summary_aggregate(
        %BeaconSummaryAggregate{
          summary_time: summary_time,
          transaction_summaries: transaction_summaries,
          p2p_availabilities: p2p_availabilities
        },
        node_patch
      ) do
    transaction_summaries
    |> Enum.reject(&TransactionChain.transaction_exists?(&1.address))
    |> Enum.filter(&TransactionHandler.download_transaction?/1)
    |> synchronize_transactions(node_patch)

    p2p_availabilities
    |> Enum.reduce(%{}, fn {subset,
                            %{
                              node_availabilities: node_availabilities,
                              node_average_availabilities: node_average_availabilities,
                              end_of_node_synchronizations: end_of_node_synchronizations
                            }},
                           acc ->
      sync_node(end_of_node_synchronizations)

      reduce_p2p_availabilities(
        subset,
        summary_time,
        node_availabilities,
        node_average_availabilities,
        acc
      )
    end)
    |> Enum.each(&update_availabilities/1)

    update_statistics(summary_time, length(transaction_summaries))
  end

  defp synchronize_transactions([], _node_patch), do: :ok

  defp synchronize_transactions(transaction_summaries, node_patch) do
    Logger.info("Need to synchronize #{Enum.count(transaction_summaries)} transactions")
    Logger.debug("Transaction to sync #{inspect(transaction_summaries)}")

    Task.Supervisor.async_stream_nolink(
      TaskSupervisor,
      transaction_summaries,
      &TransactionHandler.download_transaction(&1, node_patch),
      on_timeout: :kill_task
    )
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.each(fn {:ok, tx} ->
      TransactionHandler.process_transaction(tx)
    end)
    |> Stream.run()
  end

  defp sync_node(end_of_node_synchronizations) do
    end_of_node_synchronizations
    |> Enum.each(fn public_key -> P2P.set_node_globally_synced(public_key) end)
  end

  defp reduce_p2p_availabilities(
         subset,
         time,
         node_availabilities,
         node_average_availabilities,
         acc
       ) do
    node_list = Enum.filter(P2P.list_nodes(), &(DateTime.diff(&1.enrollment_date, time) <= 0))

    subset_node_list = P2PSampling.list_nodes_to_sample(subset, node_list)

    node_availabilities
    |> Utils.bitstring_to_integer_list()
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {available_bit, index}, acc ->
      node = Enum.at(subset_node_list, index)
      avg_availability = Enum.at(node_average_availabilities, index)

      if available_bit == 1 and Node.synced?(node) do
        Map.put(acc, node, %{available?: true, average_availability: avg_availability})
      else
        Map.put(acc, node, %{available?: false, average_availability: avg_availability})
      end
    end)
  end

  defp update_availabilities(
         {%Node{first_public_key: node_key},
          %{available?: available?, average_availability: avg_availability}}
       ) do
    DB.register_p2p_summary(node_key, DateTime.utc_now(), available?, avg_availability)

    if available? do
      P2P.set_node_globally_available(node_key)
    else
      P2P.set_node_globally_unavailable(node_key)
      P2P.set_node_globally_unsynced(node_key)
    end

    P2P.set_node_average_availability(node_key, avg_availability)
  end

  defp update_statistics(_date, 0), do: :ok

  defp update_statistics(date, nb_transactions) do
    previous_summary_time =
      date
      |> Utils.truncate_datetime()
      |> BeaconChain.previous_summary_time()

    nb_seconds = abs(DateTime.diff(previous_summary_time, date))
    tps = nb_transactions / nb_seconds

    DB.register_tps(date, tps, nb_transactions)

    Logger.info(
      "TPS #{tps} on #{Utils.time_to_string(date)} with #{nb_transactions} transactions"
    )

    PubSub.notify_new_tps(tps, nb_transactions)
  end
end
