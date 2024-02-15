defmodule Archethic.SelfRepair.Sync do
  @moduledoc false

  alias Archethic.{
    BeaconChain,
    Crypto,
    DB,
    Election,
    P2P,
    PubSub,
    SelfRepair,
    TaskSupervisor,
    TransactionChain,
    Utils
  }

  alias Archethic.BeaconChain.{
    ReplicationAttestation,
    Summary,
    SummaryAggregate
  }

  alias Archethic.P2P.{
    Node,
    Message
  }

  alias Archethic.BeaconChain.Subset.P2PSampling
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionSummary

  alias __MODULE__.TransactionHandler

  require Logger

  @bootstrap_info_last_sync_date_key "last_sync_time"

  @doc """
  Return the last synchronization date from the previous cycle of self repair

  If there are not previous stored date:
  - Try to the first enrollment date of the listed nodes
  - Otherwise take the current date
  """
  @spec last_sync_date() :: DateTime.t() | nil
  def last_sync_date do
    case DB.get_bootstrap_info(@bootstrap_info_last_sync_date_key) do
      nil ->
        Logger.info("Not previous synchronization date")
        Logger.info("We are using the default one")
        default_last_sync_date()

      timestamp ->
        date =
          timestamp
          |> String.to_integer()
          |> DateTime.from_unix!()

        Logger.info("Last synchronization date #{DateTime.to_string(date)}")
        date
    end
  end

  defp default_last_sync_date do
    case P2P.list_nodes() do
      [] ->
        nil

      nodes ->
        %Node{enrollment_date: enrollment_date} =
          nodes
          |> Enum.reject(&(&1.enrollment_date == nil))
          |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime})
          |> Enum.at(0)

        Logger.info(
          "We are taking the first node's enrollment date - #{DateTime.to_string(enrollment_date)}"
        )

        enrollment_date
    end
  end

  @doc """
  Persist the last sync date
  """
  @spec store_last_sync_date(DateTime.t()) :: :ok
  def store_last_sync_date(date = %DateTime{}) do
    timestamp =
      date
      |> DateTime.to_unix()
      |> Integer.to_string()

    DB.set_bootstrap_info(@bootstrap_info_last_sync_date_key, timestamp)

    Logger.info("Last sync date updated: #{DateTime.to_string(date)}")
  end

  @doc """
  Retrieve missing transactions from the missing beacon chain slots
  since the last sync date provided

  Beacon chain pools are retrieved from the given latest synchronization
  date including all the beacon subsets (i.e <<0>>, <<1>>, etc.)

  Once retrieved, the transactions are downloaded and stored if not exists locally
  """
  @spec load_missed_transactions(last_sync_date :: DateTime.t(), download_nodes :: list(Node.t())) ::
          :ok | {:error, :unreachable_nodes}
  def load_missed_transactions(last_sync_date, download_nodes) do
    last_summary_time = BeaconChain.previous_summary_time(DateTime.utc_now())

    if DateTime.compare(last_summary_time, last_sync_date) == :gt do
      Logger.info(
        "Fetch missed transactions from last sync date: #{DateTime.to_string(last_sync_date)}"
      )

      do_load_missed_transactions(last_sync_date, last_summary_time, download_nodes)
    else
      Logger.info("Already synchronized for #{DateTime.to_string(last_sync_date)}")

      # We skip the self-repair because the last synchronization time have been already synchronized
      :ok
    end
  end

  defp do_load_missed_transactions(last_sync_date, last_summary_time, download_nodes) do
    start = System.monotonic_time()

    # Process first the old aggregates
    fetch_summaries_aggregates(last_sync_date, last_summary_time, download_nodes)
    |> Stream.each(&process_summary_aggregate(&1, download_nodes))
    |> Stream.run()

    # Then process the last one to have the last P2P view
    last_aggregate = BeaconChain.fetch_and_aggregate_summaries(last_summary_time, download_nodes)
    ensure_download_last_aggregate(last_aggregate, download_nodes)

    aggregate_with_local_summaries(last_aggregate, last_summary_time)
    |> verify_attestations_threshold()
    |> process_summary_aggregate(download_nodes)

    :telemetry.execute([:archethic, :self_repair], %{duration: System.monotonic_time() - start})
    Archethic.Bootstrap.NetworkConstraints.persist_genesis_address()
  end

  defp fetch_summaries_aggregates(last_sync_date, last_summary_time, download_nodes) do
    dates =
      last_sync_date
      |> BeaconChain.next_summary_dates()
      # Take only the previous summaries before the last one
      |> Stream.take_while(fn date ->
        DateTime.compare(date, last_summary_time) ==
          :lt
      end)

    # Fetch the beacon summaries aggregate
    Task.Supervisor.async_stream(
      TaskSupervisor,
      dates,
      fn date ->
        Logger.debug("Fetch summary aggregate for #{date}")

        storage_nodes =
          date
          |> Crypto.derive_beacon_aggregate_address()
          |> Election.chain_storage_nodes(download_nodes)

        BeaconChain.fetch_summaries_aggregate(date, storage_nodes)
      end,
      max_concurrency: 2
    )
    |> Stream.filter(fn
      {:ok, {:ok, %SummaryAggregate{}}} ->
        true

      {:ok, {:error, :not_exists}} ->
        false

      {:ok, _} ->
        raise SelfRepair.Error,
          function: "fetch_summaries_aggregates",
          message: "Previous summary aggregate not fetched"
    end)
    |> Stream.map(fn {:ok, {:ok, aggregate}} -> aggregate end)
  end

  defp ensure_download_last_aggregate(last_aggregate, download_nodes) do
    # Make sure the last beacon aggregate have been synchronized
    # from remote nodes to avoid self-repair to be acknowledged if those
    # cannot be reached
    # If number of authorized node is <= 2 and current node is part of it
    # we accept the self repair as the other node may be unavailable and so
    # we need to do the self even if no other node respond
    with true <- P2P.authorized_node?(),
         true <- length(download_nodes) <= 2 do
      :ok
    else
      _ ->
        if SummaryAggregate.empty?(last_aggregate) do
          raise SelfRepair.Error,
            function: "ensure_download_last_aggregate",
            message: "Last aggregate not fetched"
        end

        :ok
    end
  end

  defp aggregate_with_local_summaries(summary_aggregate, last_summary_time) do
    BeaconChain.list_subsets()
    |> Task.async_stream(fn subset ->
      summary_address = Crypto.derive_beacon_chain_address(subset, last_summary_time, true)
      BeaconChain.get_summary(summary_address)
    end)
    |> Enum.reduce(summary_aggregate, fn
      {:ok, {:ok, summary = %Summary{}}}, acc ->
        SummaryAggregate.add_summary(acc, summary)

      _, acc ->
        acc
    end)
    |> SummaryAggregate.aggregate()
  end

  defp verify_attestations_threshold(summary_aggregate) do
    {filtered_summary_aggregate, refused_attestations} =
      SummaryAggregate.filter_reached_threshold(summary_aggregate)

    postpone_refused_attestations(refused_attestations)

    filtered_summary_aggregate
  end

  defp postpone_refused_attestations(attestations) do
    slot_time = DateTime.utc_now() |> BeaconChain.next_slot()
    nodes = P2P.authorized_and_available_nodes(slot_time)

    Enum.each(
      attestations,
      fn attestation = %ReplicationAttestation{
           transaction_summary: %TransactionSummary{address: address, type: type},
           confirmations: confirmations
         } ->
        # Postpone only if we are the current beacon slot node
        # (otherwise all nodes would postpone as the self repair is run on all nodes)
        slot_node? =
          BeaconChain.subset_from_address(address)
          |> Election.beacon_storage_nodes(
            slot_time,
            nodes,
            Election.get_storage_constraints()
          )
          |> Utils.key_in_node_list?(Crypto.first_node_public_key())

        if slot_node? do
          Logger.debug(
            "Attestation postponed to next summary with #{length(confirmations)} confirmations",
            transaction_address: Base.encode16(address),
            transaction_type: type
          )

          # Notification will be catched by subset and add the attestation in current Slot
          PubSub.notify_replication_attestation(attestation)
        end
      end
    )
  end

  @doc """
  Process beacon summary to synchronize the transactions involving.

  Each transactions from the beacon summary will be analyzed to determine
  if the node is a storage node for this transaction. If so, it will download the
  transaction from the closest storage nodes and replicate it locally.

  The P2P view will also be updated if some node information are inside the beacon chain to determine
  the readiness or the availability of a node.

  Also, the  number of transaction received and the fees burned during the beacon summary interval will be stored.

  At the end of the execution, the summaries aggregate will persisted locally if the node is member of the shard of the summary
  """
  @spec process_summary_aggregate(SummaryAggregate.t(), list(Node.t())) :: :ok
  def process_summary_aggregate(
        aggregate = %SummaryAggregate{
          summary_time: summary_time,
          replication_attestations: attestations,
          p2p_availabilities: p2p_availabilities,
          availability_adding_time: availability_adding_time
        },
        download_nodes
      ) do
    start_time = System.monotonic_time()

    nodes_including_self = [P2P.get_node_info() | download_nodes] |> P2P.distinct_nodes()

    attestations_to_sync =
      attestations
      |> adjust_attestations(download_nodes)
      |> Stream.filter(&TransactionHandler.download_transaction?(&1, nodes_including_self))
      |> Enum.sort_by(& &1.transaction_summary.timestamp, {:asc, DateTime})

    synchronize_transactions(attestations_to_sync, download_nodes)

    :telemetry.execute(
      [:archethic, :self_repair, :process_aggregate],
      %{duration: System.monotonic_time() - start_time},
      %{nb_transactions: length(attestations_to_sync)}
    )

    availability_update = DateTime.add(summary_time, availability_adding_time)

    previous_available_nodes = P2P.authorized_and_available_nodes()

    p2p_availabilities
    |> Enum.reduce(%{}, fn {subset,
                            %{
                              node_availabilities: node_availabilities,
                              node_average_availabilities: node_average_availabilities,
                              end_of_node_synchronizations: end_of_node_synchronizations,
                              network_patches: network_patches
                            }},
                           acc ->
      sync_node(end_of_node_synchronizations)

      reduce_p2p_availabilities(
        subset,
        summary_time,
        node_availabilities,
        node_average_availabilities,
        network_patches,
        acc
      )
    end)
    |> Enum.map(&update_availabilities(&1, availability_update))
    |> DB.register_p2p_summary()

    new_available_nodes = P2P.authorized_and_available_nodes(availability_update)

    if Archethic.up?() do
      SelfRepair.start_notifier(
        previous_available_nodes,
        new_available_nodes,
        availability_update
      )
    end

    update_statistics(summary_time, attestations)

    store_aggregate(aggregate, new_available_nodes)
    store_last_sync_date(summary_time)
  end

  # To avoid beacon chain database migration we have to support both summaries with genesis address and without
  # Hence, we need to adjust or revised the attestation to include the genesis addresses
  # which is not present in the version 1 of transaction's summary.
  # Also to unify the handling of attestation post AEIP-21, the genesis addresses are included in movements
  defp adjust_attestations([], _), do: []

  defp adjust_attestations(attestations, download_nodes) do
    if Enum.any?(attestations, &(&1.transaction_summary.version <= 2)) do
      # log each 5%
      nb_attestations = length(attestations)
      log_index_rate = ceil(nb_attestations / 20)

      Logger.info("Adjusting #{nb_attestations} attestations")

      Task.async_stream(attestations, &adjust_attestation(&1, download_nodes),
        timeout: Message.get_max_timeout(),
        max_concurrency: System.schedulers_online() * 2,
        ordered: false
      )
      |> Stream.with_index(1)
      |> Stream.map(fn {{:ok, attestation}, index} ->
        if rem(index, log_index_rate) == 0,
          do: Logger.debug("Processed #{trunc(index / nb_attestations * 100)}% attestations")

        attestation
      end)
    else
      attestations
    end
  end

  defp adjust_attestation(
         attestation = %ReplicationAttestation{
           transaction_summary:
             tx_summary = %TransactionSummary{
               address: tx_address,
               version: version
             }
         },
         download_nodes
       )
       when version == 1 do
    genesis_task =
      Task.async(fn ->
        storage_nodes = Election.chain_storage_nodes(tx_address, download_nodes)

        case TransactionChain.fetch_genesis_address(tx_address, storage_nodes) do
          {:ok, genesis_address} ->
            genesis_address

          {:error, reason} ->
            raise SelfRepair.Error,
              function: "adjust_attestation",
              message: "Failed to fetch genesis address with error #{inspect(reason)}",
              address: tx_address
        end
      end)

    io_addresses_task =
      Task.async(fn ->
        TransactionSummary.resolve_movements_addresses(tx_summary, download_nodes)
      end)

    adjusted_tx_summary = %TransactionSummary{
      tx_summary
      | genesis_address: Task.await(genesis_task),
        movements_addresses: Task.await(io_addresses_task)
    }

    %ReplicationAttestation{attestation | transaction_summary: adjusted_tx_summary}
  end

  defp adjust_attestation(
         attestation = %ReplicationAttestation{
           transaction_summary: tx_summary = %TransactionSummary{version: version}
         },
         download_nodes
       )
       when version == 2 do
    resolved_movements_addresses =
      TransactionSummary.resolve_movements_addresses(tx_summary, download_nodes)

    adjusted_tx_summary = %TransactionSummary{
      tx_summary
      | movements_addresses: resolved_movements_addresses
    }

    %ReplicationAttestation{attestation | transaction_summary: adjusted_tx_summary}
  end

  defp adjust_attestation(attestation, _), do: attestation

  defp synchronize_transactions([], _), do: :ok

  defp synchronize_transactions(attestations, download_nodes) do
    Logger.info("Need to synchronize #{Enum.count(attestations)} transactions")
    Logger.debug("Transaction to sync #{inspect(attestations)}")

    Task.Supervisor.async_stream(
      TaskSupervisor,
      attestations,
      fn attestation ->
        tx = TransactionHandler.download_transaction(attestation, download_nodes)
        consolidated_attestation = consolidate_recipients(attestation, tx)
        {consolidated_attestation, tx}
      end,
      max_concurrency: System.schedulers_online() * 2,
      timeout: Message.get_max_timeout() + 2000
    )
    |> Stream.each(fn {:ok, {attestation, tx}} ->
      :ok = TransactionHandler.process_transaction(attestation, tx, download_nodes)
    end)
    |> Stream.run()
  end

  defp consolidate_recipients(
         attestation = %ReplicationAttestation{
           transaction_summary:
             tx_summary = %TransactionSummary{
               version: 1,
               movements_addresses: movements_addresses
             }
         },
         %Transaction{validation_stamp: %ValidationStamp{recipients: recipients = [_ | _]}}
       ) do
    authorized_nodes = P2P.authorized_and_available_nodes()

    consolidated_movements_addresses =
      recipients
      |> Task.async_stream(
        fn recipient ->
          genesis_nodes = Election.chain_storage_nodes(recipient, authorized_nodes)

          case TransactionChain.fetch_genesis_address(recipient, genesis_nodes) do
            {:ok, genesis_address} ->
              [recipient, genesis_address]

            {:error, reason} ->
              raise SelfRepair.Error,
                function: "consolidate_recipients",
                message: "Failed to fetch genesis address with error #{inspect(reason)}",
                address: recipient
          end
        end,
        max_concurrency: length(recipients)
      )
      |> Stream.flat_map(fn {:ok, addresses} -> addresses end)
      |> Enum.concat(movements_addresses)

    adjusted_summary = %TransactionSummary{
      tx_summary
      | movements_addresses: consolidated_movements_addresses
    }

    %ReplicationAttestation{attestation | transaction_summary: adjusted_summary}
  end

  defp consolidate_recipients(attestation, _tx), do: attestation

  defp sync_node(end_of_node_synchronizations) do
    end_of_node_synchronizations
    |> Enum.each(fn public_key -> P2P.set_node_globally_synced(public_key) end)
  end

  defp reduce_p2p_availabilities(
         subset,
         time,
         node_availabilities,
         node_average_availabilities,
         network_patches,
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
      network_patch = Enum.at(network_patches, index, node.geo_patch)
      available? = available_bit == 1 and node.synced?

      Map.put(acc, node, %{
        available?: available?,
        average_availability: avg_availability,
        network_patch: network_patch
      })
    end)
  end

  defp update_availabilities(
         {%Node{first_public_key: node_key},
          %{
            available?: available?,
            average_availability: avg_availability,
            network_patch: network_patch
          }},
         availability_update
       ) do
    if available? do
      P2P.set_node_globally_available(node_key, availability_update)
    else
      P2P.set_node_globally_unavailable(node_key, availability_update)
      P2P.set_node_globally_unsynced(node_key)
    end

    P2P.set_node_average_availability(node_key, avg_availability)
    P2P.update_node_network_patch(node_key, network_patch)

    %Node{availability_update: availability_update} = P2P.get_node_info!(node_key)

    {node_key, available?, avg_availability, availability_update, network_patch}
  end

  defp update_statistics(date, []) do
    tps = DB.get_latest_tps()
    DB.register_stats(date, tps, 0, 0)
  end

  defp update_statistics(date, attestations) do
    nb_transactions = length(attestations)

    previous_summary_time =
      date
      |> Utils.truncate_datetime()
      |> BeaconChain.previous_summary_time()

    nb_seconds = abs(DateTime.diff(previous_summary_time, date))
    tps = nb_transactions / nb_seconds

    acc = 0

    burned_fees =
      attestations
      |> Enum.reduce(acc, fn %ReplicationAttestation{
                               transaction_summary: %TransactionSummary{fee: fee}
                             },
                             acc ->
        acc + fee
      end)

    DB.register_stats(date, tps, nb_transactions, burned_fees)

    Logger.info(
      "TPS #{tps} on #{Utils.time_to_string(date)} with #{nb_transactions} transactions"
    )

    Logger.info("Burned fees #{burned_fees} on #{Utils.time_to_string(date)}")

    PubSub.notify_new_tps(tps, nb_transactions)
  end

  defp store_aggregate(
         aggregate = %SummaryAggregate{summary_time: summary_time},
         new_available_nodes
       ) do
    node_list = [P2P.get_node_info() | new_available_nodes] |> P2P.distinct_nodes()

    should_store? =
      summary_time
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.chain_storage_nodes(node_list)
      |> Utils.key_in_node_list?(Crypto.first_node_public_key())

    if should_store? do
      BeaconChain.write_summaries_aggregate(aggregate)
      Logger.info("Summary written to disk for #{summary_time}")
    else
      :ok
    end
  end
end
