defmodule Archethic.BeaconChain do
  @moduledoc """
  Manage the beacon chain by providing functions to add to the subsets information and
  to retrieve the beacon storage nodes involved.
  """

  alias __MODULE__.Slot
  alias __MODULE__.Slot.EndOfNodeSync
  alias __MODULE__.Slot.Validation, as: SlotValidation
  alias __MODULE__.SlotTimer
  alias __MODULE__.Subset
  alias __MODULE__.Subset.P2PSampling
  alias __MODULE__.Subset.SummaryCache
  alias __MODULE__.Summary
  alias __MODULE__.SummaryAggregate
  alias __MODULE__.SummaryTimer
  alias __MODULE__.Update

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetBeaconSummaries
  alias Archethic.P2P.Message.GetBeaconSummariesAggregate
  alias Archethic.P2P.Message.BeaconSummaryList
  alias Archethic.P2P.Message.NotFound

  alias Archethic.TaskSupervisor

  alias Archethic.TransactionChain.TransactionSummary

  alias Archethic.DB

  alias Archethic.Utils

  require Logger

  @doc """
  List of all transaction subsets (255 subsets for a byte capacity)

  ## Examples

      BeaconChain.list_subsets()
      [ <<0>>, <<1>>,<<2>>, <<3>> ... <<253>>, <<254>>, <255>>]
  """
  @spec list_subsets() :: list(binary())
  def list_subsets do
    Enum.map(0..255, &:binary.encode_unsigned(&1))
  end

  @doc """
  Get the next beacon summary time
  """
  @spec next_summary_date(DateTime.t()) :: DateTime.t()
  defdelegate next_summary_date(date), to: SummaryTimer, as: :next_summary

  @doc """
  Get the next beacon slot time from a given date
  """
  @spec next_slot(last_sync_date :: DateTime.t()) :: DateTime.t()
  defdelegate next_slot(last_sync_date), to: SlotTimer

  @doc """
  Extract the beacon subset from an address

  ## Examples

      iex> BeaconChain.subset_from_address(<<0, 0, 44, 242, 77, 186, 95, 176, 163,
      ...> 14, 38, 232, 59, 42, 197, 185, 226, 158, 51, 98, 147, 139, 152, 36,
      ...> 27, 22, 30, 92, 31, 167, 66, 94, 115, 4, >>)
      <<44>>
  """
  @spec subset_from_address(binary()) :: binary()
  def subset_from_address(<<_::8, _::8, first_digit::binary-size(1), _::binary>>) do
    first_digit
  end

  @doc """
  Add a node entry into the beacon chain subset
  """
  @spec add_end_of_node_sync(Crypto.key(), DateTime.t()) :: :ok
  def add_end_of_node_sync(
        node_public_key = <<_::8, _::8, subset::binary-size(1), _::binary>>,
        timestamp = %DateTime{}
      )
      when is_binary(node_public_key) do
    Subset.add_end_of_node_sync(subset, %EndOfNodeSync{
      public_key: node_public_key,
      timestamp: timestamp
    })
  end

  @doc """
  Get the transaction address for a beacon chain daily summary based from a subset and date
  """
  @spec summary_transaction_address(binary(), DateTime.t()) :: binary()
  def summary_transaction_address(subset, date = %DateTime{}) when is_binary(subset) do
    Crypto.derive_beacon_chain_address(subset, date, true)
  end

  @doc """
  Return the previous summary time
  """
  @spec previous_summary_time(DateTime.t()) :: DateTime.t()
  defdelegate previous_summary_time(date_from), to: SummaryTimer, as: :previous_summary

  @doc """
  Load a slot in summary cache
  """
  @spec load_slot(Slot.t()) :: :ok | :error
  def load_slot(slot = %Slot{subset: subset, slot_time: slot_time}) do
    if slot_time == SlotTimer.previous_slot(DateTime.utc_now()) do
      Task.Supervisor.start_child(TaskSupervisor, fn ->
        case validate_slot(slot) do
          :ok ->
            Logger.debug("New beacon slot loaded - #{inspect(slot)}",
              beacon_subset: Base.encode16(subset)
            )

            SummaryCache.add_slot(subset, slot)

          {:error, reason} ->
            Logger.error("Invalid beacon slot - #{inspect(reason)}")
        end
      end)

      :ok
    else
      Logger.error("Invalid beacon slot - Invalid slot time")
      :error
    end
  end

  def load_transaction(_), do: :ok

  defp validate_slot(slot = %Slot{}) do
    cond do
      !SlotValidation.valid_transaction_attestations?(slot) ->
        {:error, :invalid_transaction_attestations}

      !SlotValidation.valid_end_of_node_sync?(slot) ->
        {:error, :invalid_end_of_node_sync}

      true ->
        :ok
    end
  end

  @doc """
  List the nodes for the subset to sample the P2P availability
  """
  @spec list_p2p_sampling_nodes(binary()) :: list(Node.t())
  defdelegate list_p2p_sampling_nodes(subset), to: P2PSampling, as: :list_nodes_to_sample

  def config_change(changed_conf) do
    changed_conf
    |> Keyword.get(SummaryTimer)
    |> SummaryTimer.config_change()

    changed_conf
    |> Keyword.get(SlotTimer)
    |> SlotTimer.config_change()
  end

  @doc """
  Get a beacon chain summary representation by loading from the database the transaction
  """
  @spec get_summary(binary()) :: {:ok, Summary.t()} | {:error, :not_found}
  def get_summary(summary_address) when is_binary(summary_address) do
    case DB.get_beacon_summary(summary_address) do
      {:ok, summary} ->
        {:ok, summary}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Write a beacon summary in DB
  """
  @spec write_beacon_summary(Summary.t()) :: :ok
  def write_beacon_summary(summary = %Summary{subset: subset, summary_time: time}) do
    DB.write_beacon_summary(summary)

    Logger.info("Beacon summary stored, subset: #{Base.encode16(subset)}, time: #{time}")
  end

  @doc """
  Get all slots of a subset from summary cache and return unique transaction summaries
  """
  @spec get_summary_slots(binary()) :: list(TransactionSummary.t())
  def get_summary_slots(subset) when is_binary(subset) do
    SummaryCache.stream_current_slots(subset)
    |> Stream.flat_map(fn %Slot{transaction_attestations: transaction_attestations} ->
      transaction_summaries =
        transaction_attestations
        |> Enum.map(& &1.transaction_summary)

      transaction_summaries
    end)
    |> Stream.uniq_by(fn %TransactionSummary{address: address} -> address end)
    |> Enum.to_list()
  end

  @doc """
  Return the previous summary datetimes from a given date
  """
  @spec previous_summary_dates(DateTime.t()) :: Enumerable.t()
  defdelegate previous_summary_dates(date), to: SummaryTimer, as: :previous_summaries

  @doc """
  Return the next summary datetimes from a given date
  """
  @spec next_summary_dates(DateTime.t()) :: Enumerable.t()
  defdelegate next_summary_dates(date), to: SummaryTimer, as: :next_summaries

  @doc """
  Return a list of beacon summaries from a list of transaction addresses
  """
  @spec get_beacon_summaries(list(binary)) :: list(Summary.t())
  def get_beacon_summaries(addresses) do
    addresses
    |> Stream.map(&get_summary/1)
    |> Stream.reject(&match?({:error, :not_found}, &1))
    |> Stream.map(fn {:ok, summary} -> summary end)
    |> Enum.to_list()
  end

  @doc """
   subscribe for beacon updates i.e add to subscribed list takes for given subset and node_public_key
  """
  @spec subscribe_for_beacon_updates(binary(), Crypto.key()) :: :ok
  def subscribe_for_beacon_updates(subset, node_public_key) do
    # check node list and subscribe to subset if exist
    if Utils.key_in_node_list?(P2P.authorized_and_available_nodes(), node_public_key) do
      Subset.subscribe_for_beacon_updates(subset, node_public_key)
    end
  end

  @doc """
   Register for beacon updates i.e send a P2P message for beacon updates
  """
  @spec register_to_beacon_pool_updates(DateTime.t()) :: list
  def register_to_beacon_pool_updates(
        date = %DateTime{} \\ next_slot(DateTime.utc_now()),
        unsubscribe? \\ false
      ) do
    if unsubscribe?, do: Update.unsubscribe()

    Enum.map(list_subsets(), fn subset ->
      nodes = Election.beacon_storage_nodes(subset, date, P2P.authorized_and_available_nodes())

      nodes =
        Enum.reject(nodes, fn node -> node.first_public_key == Crypto.first_node_public_key() end)

      Update.subscribe(nodes, subset)
    end)
  end

  @doc """
  Request from the beacon chains all the summaries for the given dates and aggregate them

  ```
   [0, 1, ...]    Subsets
      / | \
     /  |  \
  [ ]  [ ]  [ ]  Node election for each dates to sync
   |\  /|\  /|
   | \/ | \/ |
   | /\ | /\ |
  [ ]  [ ]  [ ] Partition by node
   |    |    |
  [ ]  [ ]  [ ] Aggregate addresses
   |    |    |
  [ ]  [ ]  [ ] Fetch summaries
   |    |    |
  [ ]  [ ]  [ ] Aggregate and consolidate summaries
   \    |    /
    \   |   /
     \  |  /
      \ | /
       [ ]
  ```
  """
  @spec fetch_and_aggregate_summaries(DateTime.t()) :: SummaryAggregate.t()
  def fetch_and_aggregate_summaries(date = %DateTime{}) do
    authorized_nodes =
      P2P.authorized_and_available_nodes()
      |> Enum.reject(&(&1.first_public_key == Crypto.first_node_public_key()))

    list_subsets()
    |> Flow.from_enumerable(stages: 256)
    |> Flow.flat_map(fn subset ->
      # Foreach subset we compute concurrently the node election
      get_summary_address_by_node(date, subset, authorized_nodes)
    end)
    # We partition by node
    |> Flow.partition(key: {:elem, 0})
    |> Flow.reduce(fn -> %{} end, fn {node, summary_address}, acc ->
      # We aggregate the addresses for a given node
      Map.update(acc, node, [summary_address], &[summary_address | &1])
    end)
    |> Flow.flat_map(fn {node, addresses} ->
      # For this node we fetch the summaries
      fetch_summaries(node, addresses)
    end)
    # We departition to build the final summarie aggregate
    |> Flow.departition(
      fn -> %SummaryAggregate{summary_time: date} end,
      fn summaries, acc ->
        Enum.reduce(summaries, acc, &SummaryAggregate.add_summary(&2, &1))
      end,
      & &1
    )
    |> Enum.to_list()
    |> Enum.at(0)
  end

  defp get_summary_address_by_node(date, subset, authorized_nodes) do
    filter_nodes =
      Enum.filter(authorized_nodes, &(DateTime.compare(&1.authorization_date, date) == :lt))

    summary_address = Crypto.derive_beacon_chain_address(subset, date, true)

    subset
    |> Election.beacon_storage_nodes(date, filter_nodes)
    |> Enum.map(fn node ->
      {node, summary_address}
    end)
  end

  defp fetch_summaries(node, addresses) do
    Logger.info(
      "Self repair start download #{Enum.count(addresses)} summaries on node #{Base.encode16(node.first_public_key)}"
    )

    start_time = System.monotonic_time()

    addresses
    |> Stream.chunk_every(10)
    |> Task.async_stream(fn addresses ->
      case P2P.send_message(node, %GetBeaconSummaries{addresses: addresses}) do
        {:ok, %BeaconSummaryList{summaries: summaries}} ->
          summaries

        _ ->
          []
      end
    end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.flat_map(&elem(&1, 1))
    |> Enum.to_list()
    |> tap(fn _ ->
      :telemetry.execute(
        [:archethic, :self_repair, :summaries_fetch],
        %{
          duration: System.monotonic_time() - start_time
        },
        %{nb_summaries: length(addresses)}
      )
    end)
  end

  @doc """
  Get a beacon summaries aggregate for a given date
  """
  @spec get_summaries_aggregate(DateTime.t()) ::
          {:ok, SummaryAggregate.t()} | {:error, :not_exists}
  defdelegate get_summaries_aggregate(datetime), to: DB, as: :get_beacon_summaries_aggregate

  @doc """
  Persists a beacon summaries aggregate
  """
  @spec write_summaries_aggregate(SummaryAggregate.t()) :: :ok
  defdelegate write_summaries_aggregate(aggregate), to: DB, as: :write_beacon_summaries_aggregate

  @doc """
  Fetch a summaries aggregate for a given date
  """
  @spec fetch_summaries_aggregate(DateTime.t()) ::
          {:ok, SummaryAggregate.t()} | {:error, :not_exists} | {:error, :network_issue}
  def fetch_summaries_aggregate(summary_time = %DateTime{}) do
    storage_nodes =
      summary_time
      |> Crypto.derive_beacon_aggregate_address()
      |> Election.chain_storage_nodes(P2P.authorized_and_available_nodes())

    fetch_summaries_aggregate_from_nodes(summary_time, storage_nodes)
  end

  @spec fetch_summaries_aggregate_from_nodes(DateTime.t(), list(Node.t())) ::
          {:ok, SummaryAggregate.t()} | {:error, :not_exists} | {:error, :network_issue}
  def fetch_summaries_aggregate_from_nodes(summary_time, storage_nodes) do
    conflict_resolver = fn results ->
      # Prioritize results over not found
      with nil <- Enum.find(results, &match?(%SummaryAggregate{}, &1)),
           nil <- Enum.find(results, &match?(%NotFound{}, &1)) do
        %NotFound{}
      else
        res ->
          res
      end
    end

    case P2P.quorum_read(
           storage_nodes,
           %GetBeaconSummariesAggregate{date: summary_time},
           conflict_resolver
         ) do
      {:ok, aggregate = %SummaryAggregate{}} ->
        {:ok, aggregate}

      {:ok, %NotFound{}} ->
        {:error, :not_exists}

      {:error, :network_issue} = e ->
        e
    end
  end
end
