defmodule Migration_1_0_8 do
  @moduledoc false

  alias Archethic.TaskSupervisor

  alias Archethic.BeaconChain.ReplicationAttestation
  alias Archethic.BeaconChain.Summary
  alias Archethic.BeaconChain.SummaryAggregate
  alias Archethic.DB.EmbeddedImpl
  alias Archethic.DB.EmbeddedImpl.ChainWriter

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.Utils
  alias Archethic.Utils.VarInt

  def run() do
    upgrade_summary_aggregates()
    upgrade_beacon_summaries()
  end

  defp upgrade_summary_aggregates() do
    db_path = EmbeddedImpl.db_path()
    aggregate_dir = ChainWriter.base_beacon_aggregate_path(db_path)
    paths = Path.wildcard("#{aggregate_dir}/*")

    # For each aggregate of the dir
    Task.Supervisor.async_stream(
      TaskSupervisor,
      paths,
      fn aggregate_path ->
        File.read!(aggregate_path)
        |> deserialize_aggregate()
        |> elem(0)
        |> migrate_aggregate
        |> EmbeddedImpl.write_beacon_summaries_aggregate()
      end,
      shutdown: :brutal_kill,
      timeout: :infinity,
      ordered: false
    )
    |> Stream.run()
  end

  defp migrate_aggregate(aggregate = %SummaryAggregate{replication_attestations: tx_summaries}) do
    replication_attestations =
      Task.Supervisor.async_stream(
        TaskSupervisor,
        tx_summaries, 
        fn tx_summary ->
          create_attestation(tx_summary)
        end,
        shutdown: :brutal_kill,
        max_concurency: System.schedulers_online() * 10
      )
      |> Enum.map(fn {:ok, replication_attestation} -> replication_attestation end)

    %SummaryAggregate{aggregate | replication_attestations: replication_attestations}
  end

  defp upgrade_beacon_summaries() do
    db_path = EmbeddedImpl.db_path()
    summaries_dir = ChainWriter.base_beacon_path(db_path)
    paths = Path.wildcard("#{summaries_dir}/*")

    # For each summary of the dir
    Task.Supervisor.async_stream(
      TaskSupervisor,
      paths,
      fn summary_path ->
        new_summary = File.read!(summary_path)
        |> deserialize_summary()
        |> elem(0)
        |> migrate_summary()

        File.rm(summary_path)
        EmbeddedImpl.write_beacon_summary(new_summary)
      end,
      shutdown: :brutal_kill,
      timeout: :infinity,
      ordered: false
    )
  end

  defp migrate_summary(summary = %Summary{transaction_attestations: attestations}) do
    new_attestations =
      Task.Supervisor.async_stream(
        TaskSupervisor,
        attestations,
        fn %ReplicationAttestation{
             transaction_summary: tx_summary
           } ->
          create_attestation(tx_summary)
        end,
        shutdown: :brutal_kill,
        max_concurency: System.schedulers_online() * 10
      )
      |> Enum.map(fn {:ok, replication_attestation} -> replication_attestation end)

    %Summary{summary | transaction_attestations: new_attestations}
  end

  defp create_attestation(tx_summary) do
    new_tx_summary = TransactionSummary.transform("1.0.8", tx_summary)
    %ReplicationAttestation{version: 1, transaction_summary: new_tx_summary}
  end

  # This function is the same as SummaryAggregate.deserialize() but it use the
  # old transaction summary deserialization
  defp deserialize_aggregate(<<1::8, timestamp::32, rest::bitstring>>) do
    {nb_tx_summaries, rest} = VarInt.get_value(rest)

    {tx_summaries, <<nb_p2p_availabilities::8, rest::bitstring>>} =
      deserialize_transaction_summaries(rest, nb_tx_summaries, [])

    {p2p_availabilities, <<availability_adding_time::16, rest::bitstring>>} =
      deserialize_p2p_availabilities(rest, nb_p2p_availabilities, %{})

    {
      %SummaryAggregate{
        version: 1,
        summary_time: DateTime.from_unix!(timestamp),
        replication_attestations: tx_summaries,
        p2p_availabilities: p2p_availabilities,
        availability_adding_time: availability_adding_time
      },
      rest
    }
  end

  defp deserialize_p2p_availabilities(<<>>, _, acc), do: {acc, <<>>}

  defp deserialize_p2p_availabilities(rest, nb_p2p_availabilities, acc)
       when map_size(acc) == nb_p2p_availabilities do
    {acc, rest}
  end

  defp deserialize_p2p_availabilities(
         <<subset::binary-size(1), rest::bitstring>>,
         nb_p2p_availabilities,
         acc
       ) do
    {nb_node_availabilities, rest} = VarInt.get_value(rest)

    <<node_availabilities::bitstring-size(nb_node_availabilities),
      node_avg_availabilities_bin::binary-size(nb_node_availabilities), rest::bitstring>> = rest

    node_avg_availabilities =
      node_avg_availabilities_bin
      |> :erlang.binary_to_list()
      |> Enum.map(fn avg -> avg / 100 end)

    {nb_end_of_sync, rest} = VarInt.get_value(rest)
    {end_of_node_sync, rest} = Utils.deserialize_public_key_list(rest, nb_end_of_sync, [])

    deserialize_p2p_availabilities(
      rest,
      nb_p2p_availabilities,
      Map.put(
        acc,
        subset,
        %{
          node_availabilities: node_availabilities,
          node_average_availabilities: node_avg_availabilities,
          end_of_node_synchronizations: end_of_node_sync,
          network_patches: []
        }
      )
    )
  end

  # This function is the same as Summary.deserialize() but it use the
  # old transaction summary deserialization
  def deserialize_summary(<<1::8, subset::8, summary_timestamp::32, rest::bitstring>>) do
    {nb_transaction_attestations, rest} = rest |> VarInt.get_value()

    {transaction_attestations, rest} =
      deserialize_transaction_attestations(rest, nb_transaction_attestations, [])

    <<nb_availabilities::16, availabilities::bitstring-size(nb_availabilities), rest::bitstring>> =
      rest

    <<node_average_availabilities_bin::binary-size(nb_availabilities), rest::bitstring>> = rest

    {nb_end_of_sync, rest} = rest |> VarInt.get_value()

    {end_of_node_synchronizations, <<availability_adding_time::16, rest::bitstring>>} =
      Utils.deserialize_public_key_list(rest, nb_end_of_sync, [])

    node_average_availabilities = for <<avg::8 <- node_average_availabilities_bin>>, do: avg / 100

    {%Summary{
       subset: <<subset>>,
       summary_time: DateTime.from_unix!(summary_timestamp),
       availability_adding_time: availability_adding_time,
       transaction_attestations: transaction_attestations,
       node_availabilities: availabilities,
       node_average_availabilities: node_average_availabilities,
       end_of_node_synchronizations: end_of_node_synchronizations
     }, rest}
  end

  # This function is the same as Utils.deserialize_transaction_attestations() but it use the
  # old transaction summary deserialization
  def deserialize_transaction_attestations(rest, 0, _acc), do: {[], rest}

  def deserialize_transaction_attestations(rest, nb_attestations, acc)
      when nb_attestations == length(acc),
      do: {Enum.reverse(acc), rest}

  def deserialize_transaction_attestations(rest, nb_attestations, acc) do
    {attestation, rest} = deserialize_attestation(rest)
    deserialize_transaction_attestations(rest, nb_attestations, [attestation | acc])
  end

  # This function is the same as ReplicationAttestation.deserialize() but it use the
  # old transaction summary deserialization
  def deserialize_attestation(<<1::8, rest::bitstring>>) do
    {tx_summary, <<nb_confirmations::8, rest::bitstring>>} =
      TransactionSummary.deserialize_old(rest)

    {confirmations, rest} = deserialize_confirmations(rest, nb_confirmations, [])

    {%ReplicationAttestation{
       version: 1,
       transaction_summary: tx_summary,
       confirmations: confirmations
     }, rest}
  end

  defp deserialize_confirmations(rest, nb_replicas_signature, acc)
       when length(acc) == nb_replicas_signature do
    {Enum.reverse(acc), rest}
  end

  defp deserialize_confirmations(rest, 0, _acc), do: {[], rest}

  defp deserialize_confirmations(
         <<position::8, sig_size::8, signature::binary-size(sig_size), rest::bitstring>>,
         nb_replicas_signature,
         acc
       ) do
    deserialize_confirmations(rest, nb_replicas_signature, [{position, signature} | acc])
  end

  # This function is the same as Utils.deserialize_transaction_summaries() but it use the
  # old transaction summary deserialization
  defp deserialize_transaction_summaries(rest, 0, _acc), do: {[], rest}

  defp deserialize_transaction_summaries(rest, nb_transaction_summaries, acc)
       when nb_transaction_summaries == length(acc),
       do: {Enum.reverse(acc), rest}

  defp deserialize_transaction_summaries(rest, nb_transaction_summaries, acc) do
    {transaction_summary, rest} = TransactionSummary.deserialize_old(rest)
    deserialize_transaction_summaries(rest, nb_transaction_summaries, [transaction_summary | acc])
  end
end
