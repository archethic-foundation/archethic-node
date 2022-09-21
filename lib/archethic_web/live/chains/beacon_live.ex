defmodule ArchethicWeb.BeaconChainLive do
  @moduledoc false
  use ArchethicWeb, :live_view

  alias Archethic.BeaconChain

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetCurrentSummaries
  alias Archethic.P2P.Message.TransactionSummaryList

  alias Archethic.PubSub

  alias Archethic.TransactionChain.TransactionSummary
  alias ArchethicWeb.ExplorerView
  alias ArchethicWeb.TransactionCache

  alias Phoenix.View

  require Logger

  def mount(_params, _session, socket) do
    next_summary_time = BeaconChain.next_summary_date(DateTime.utc_now())

    if connected?(socket) do
      PubSub.register_to_next_summary_time()
      PubSub.register_to_current_epoch_of_slot_time()
      PubSub.register_to_new_transaction_attestations()
      # register for client to able to get the current added transaction to the beacon pool
      Task.start(fn -> BeaconChain.register_to_beacon_pool_updates() end)
    end

    beacon_dates =
      case get_beacon_dates() do
        [] ->
          [next_summary_time]

        dates ->
          [next_summary_time | dates]
      end

    new_assign =
      socket
      |> assign(:next_summary_time, next_summary_time)
      |> assign(:dates, beacon_dates)
      |> assign(:current_date_page, 1)
      |> assign(:update_time, DateTime.utc_now())
      |> assign(:transactions, [])
      |> assign(:fetching, true)

    {:ok, new_assign}
  end

  def render(assigns) do
    View.render(ExplorerView, "beacon_chain_index.html", assigns)
  end

  def handle_params(params, _uri, socket = %{assigns: %{dates: dates}}) do
    page = Map.get(params, "page", "1")

    case Integer.parse(page) do
      {1, ""} ->
        send(self(), :initial_load)

        new_assign =
          socket
          |> assign(:current_date_page, 1)
          |> assign(:transactions, [])
          |> assign(:fetching, true)

        {:noreply, new_assign}

      {number, ""} when number > 1 and number <= length(dates) ->
        new_assign =
          socket
          |> assign(:current_date_page, number)
          |> assign(:transactions, [])
          |> assign(:fetching, true)

        date = Enum.at(dates, number - 1)
        send(self(), {:load_at, date})

        {:noreply, new_assign}

      _ ->
        {:noreply,
         push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}
    end
  end

  def handle_params(%{}, _, socket) do
    {:noreply, socket}
  end

  def handle_event("goto", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_info(
        :initial_load,
        socket
      ) do
    new_socket =
      socket
      |> assign(:transactions, list_transactions_from_current_slots())
      |> assign(:update_time, DateTime.utc_now())
      |> assign(:fetching, false)

    {:noreply, new_socket}
  end

  def handle_info({:load_at, date}, socket) do
    # Try to fetch from the cache, other fetch from the beacon summary
    {:ok, transactions} =
      TransactionCache.resolve(date, fn ->
        list_transactions_from_summary(date)
      end)

    new_assign =
      socket
      |> assign(:fetching, false)
      |> assign(:transactions, transactions)

    {:noreply, new_assign}
  end

  def handle_info(
        {:new_transaction_attestation, tx_summary = %TransactionSummary{}},
        socket = %{
          assigns:
            assigns = %{
              current_date_page: page,
              transactions: transactions
            }
        }
      ) do
    if page == 1 and !Enum.any?(transactions, fn tx -> tx.address == tx_summary.address end) do
      # Only update the transaction listed when you are on the first page
      new_socket =
        case Map.get(assigns, :summary_passed?) do
          true ->
            socket
            |> assign(:transactions, [tx_summary | transactions])
            |> assign(:summary_passed?, false)
            |> assign(:update_time, DateTime.utc_now())
            |> assign(:fetching, false)

          _ ->
            socket
            |> update(:transactions, &[tx_summary | &1])
            |> assign(:update_time, DateTime.utc_now())
            |> assign(:fetching, false)
        end

      {:noreply, new_socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(
        {:next_summary_time, next_summary_date},
        socket = %{
          assigns: %{
            current_date_page: page,
            dates: dates
          }
        }
      ) do
    new_dates = [next_summary_date | dates]

    if page == 1 do
      new_assign =
        socket
        |> assign(:transactions, [])
        |> assign(:dates, new_dates)
        |> assign(:next_summary_time, next_summary_date)
        |> assign(:update_time, DateTime.utc_now())

      {:noreply, new_assign}
    else
      {:noreply,
       push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page + 1}))}
    end
  end

  def handle_info(
        {:current_epoch_of_slot_timer, date},
        socket
      ) do
    # We refresh the live feed subscription at each slot time
    BeaconChain.register_to_beacon_pool_updates(date, true)

    {:noreply, socket}
  end

  defp get_beacon_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes()
      |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime})
      |> Enum.at(0)

    enrollment_date
    |> BeaconChain.previous_summary_dates()
    |> Enum.sort({:desc, DateTime})
  end

  defp list_transactions_from_summary(date = %DateTime{}) do
    [date]
    |> BeaconChain.fetch_summary_aggregates()
    |> Enum.flat_map(& &1.transaction_summaries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp list_transactions_from_summary(nil), do: []

  # Slots which are already has been added
  # Real time transaction can be get from pubsub
  def list_transactions_from_current_slots(date = %DateTime{} \\ DateTime.utc_now()) do
    %Node{network_patch: patch} = P2P.get_node_info()

    authorized_nodes = P2P.authorized_and_available_nodes()

    ref_time = DateTime.truncate(date, :millisecond)

    next_summary_date = BeaconChain.next_summary_date(ref_time)

    BeaconChain.list_subsets()
    |> Flow.from_enumerable(stages: 256)
    |> Flow.flat_map(fn subset ->
      # Foreach subset and date we compute concurrently the node election
      subset
      |> Election.beacon_storage_nodes(next_summary_date, authorized_nodes)
      |> Enum.filter(&Node.locally_available?/1)
      |> P2P.nearest_nodes(patch)
      |> Enum.take(3)
      |> Enum.map(&{&1, subset})
    end)
    # We partition by node
    |> Flow.partition(key: {:elem, 0})
    |> Flow.reduce(fn -> %{} end, fn {node, subset}, acc ->
      # We aggregate the subsets for a given node
      Map.update(acc, node, [subset], &[subset | &1])
    end)
    |> Flow.flat_map(fn {node, addresses} ->
      # For this node we fetch the summaries
      fetch_summaries(node, addresses)
    end)
    |> Stream.uniq_by(& &1.address)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp fetch_summaries(node, subsets) do
    subsets
    |> Stream.chunk_every(10)
    |> Task.async_stream(fn subsets ->
      case P2P.send_message(node, %GetCurrentSummaries{subsets: subsets}) do
        {:ok, %TransactionSummaryList{transaction_summaries: transaction_summaries}} ->
          transaction_summaries

        _ ->
          []
      end
    end)
    |> Stream.filter(&match?({:ok, _}, &1))
    |> Stream.flat_map(&elem(&1, 1))
    |> Enum.to_list()
  end
end
