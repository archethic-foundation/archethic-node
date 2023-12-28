defmodule ArchethicWeb.Explorer.BeaconChainLive do
  @moduledoc false
  use ArchethicWeb.Explorer, :live_view

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.SummaryAggregate

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.TransactionChain.TransactionSummary
  alias ArchethicWeb.Explorer.TransactionCache
  alias ArchethicWeb.Explorer.Components.TransactionsList

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
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  def handle_info(
        :initial_load,
        socket
      ) do
    new_socket =
      socket
      |> assign(:transactions, Archethic.list_transactions_summaries_from_current_slot())
      |> assign(:update_time, DateTime.utc_now())
      |> assign(:fetching, false)

    {:noreply, new_socket}
  end

  def handle_info({:load_at, date}, socket = %{assigns: %{current_date_page: 2}}) do
    # Try to fetch from the cache, other fetch from the beacon summaries
    {:ok, transactions} =
      TransactionCache.resolve(date, fn ->
        list_transactions_from_summaries(date)
      end)

    new_assign =
      socket
      |> assign(:fetching, false)
      |> assign(:transactions, transactions)

    {:noreply, new_assign}
  end

  def handle_info({:load_at, date}, socket) do
    # Try to fetch from the cache, other fetch from the beacon aggregate
    {:ok, transactions} =
      TransactionCache.resolve(date, fn ->
        list_transactions_from_aggregate(date)
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

  defp list_transactions_from_summaries(date = %DateTime{}) do
    {%SummaryAggregate{replication_attestations: attestations}, _} =
      Archethic.fetch_and_aggregate_summaries(date)
      |> SummaryAggregate.aggregate()
      |> SummaryAggregate.filter_reached_threshold()

    attestations
    |> Enum.map(& &1.transaction_summary)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp list_transactions_from_summaries(nil), do: []

  defp list_transactions_from_aggregate(date = %DateTime{}) do
    case Archethic.fetch_summaries_aggregate(date) do
      {:ok, %SummaryAggregate{replication_attestations: attestations}} ->
        attestations
        |> Enum.map(& &1.transaction_summary)
        |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})

      _ ->
        []
    end
  end

  defp list_transactions_from_aggregate(nil), do: []
end
