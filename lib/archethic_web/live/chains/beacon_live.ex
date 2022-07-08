defmodule ArchethicWeb.BeaconChainLive do
  @moduledoc false
  use ArchethicWeb, :live_view

  alias Archethic.BeaconChain
  alias Archethic.BeaconChain.Slot
  alias Archethic.BeaconChain.SummaryTimer

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node

  alias Archethic.PubSub

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.TransactionData
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
      BeaconChain.register_to_beacon_pool_updates()
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
      |> assign(:live_cache, [])
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
        socket = %{assigns: %{live_cache: live_cache}}
      ) do
    # Fetch from the latest transaction on the chain
    transactions = list_transaction_from_chain()

    # Integrate the transactions updates from the live feed
    all_txs = Enum.sort_by(live_cache ++ transactions, & &1.timestamp, {:desc, DateTime})

    new_socket =
      socket
      |> assign(:transactions, all_txs)
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
            |> assign(:transactions, Enum.uniq([tx_summary | transactions]))
            |> update(:live_cache, &[tx_summary | &1])
            |> assign(:summary_passed?, false)
            |> assign(:update_time, DateTime.utc_now())

          _ ->
            socket
            |> update(:transactions, &Enum.uniq([tx_summary | &1]))
            |> update(:live_cache, &[tx_summary | &1])
            |> assign(:update_time, DateTime.utc_now())
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
            dates: dates
          }
        }
      ) do
    new_dates = [next_summary_date | dates]

    [last_date | _] = dates

    # Flush into cache the transactions from the chain for the last beacon cycle
    TransactionCache.put(
      last_date,
      list_transaction_from_chain(last_date)
    )

    new_assign =
      socket
      |> assign(:transactions, [])
      |> assign(:live_cache, [])
      |> assign(:dates, new_dates)
      |> assign(:next_summary_time, next_summary_date)
      |> assign(:update_time, DateTime.utc_now())

    {:noreply, new_assign}
  end

  def handle_info(
        {:current_epoch_of_slot_timer, date},
        socket
      ) do
    # We refresh the live feed subscription at each slot time
    BeaconChain.register_to_beacon_pool_updates(date)

    {:noreply, socket}
  end

  defp get_beacon_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes()
      |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime})
      |> Enum.at(0)

    enrollment_date
    |> SummaryTimer.previous_summaries()
    |> Enum.sort({:desc, DateTime})
  end

  defp list_transactions_from_summary(date = %DateTime{}) do
    [date]
    |> BeaconChain.fetch_summary_aggregates()
    |> Enum.flat_map(& &1.transaction_summaries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp list_transactions_from_summary(nil), do: []

  defp list_transaction_from_chain(date = %DateTime{} \\ DateTime.utc_now()) do
    %Node{network_patch: patch} = P2P.get_node_info()

    node_list = P2P.authorized_nodes()

    ref_time = DateTime.truncate(date, :millisecond)

    genesis_date = BeaconChain.previous_summary_time(ref_time)
    next_summary_date = BeaconChain.next_summary_date(ref_time)

    BeaconChain.list_subsets()
    |> Flow.from_enumerable()
    |> Flow.map(fn subset ->
      address = Crypto.derive_beacon_chain_address(subset, genesis_date)

      nodes =
        subset
        |> Election.beacon_storage_nodes(next_summary_date, node_list)
        |> P2P.nearest_nodes(patch)

      {address, nodes, subset}
    end)
    |> Flow.partition(key: {:elem, 2})
    |> Flow.reduce(fn -> [] end, fn {address, nodes, _subset}, acc ->
      transactions =
        case TransactionChain.fetch_last_address_remotely(address, nodes) do
          {:ok, last_address} ->
            last_address
            |> TransactionChain.stream_remotely(nodes)
            |> Stream.flat_map(& &1)
            |> Stream.filter(&(&1.type == :beacon))
            |> Stream.map(&deserialize_beacon_transaction/1)
            |> Enum.to_list()

          {:error, :network_issue} ->
            []
        end

      transactions ++ acc
    end)
    |> Enum.to_list()
    |> List.flatten()
    |> Enum.uniq_by(& &1.address)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp deserialize_beacon_transaction(%Transaction{
         type: :beacon,
         data: %TransactionData{content: content}
       }) do
    {slot, _} = Slot.deserialize(content)
    %Slot{transaction_attestations: transaction_attestations} = slot
    Enum.map(transaction_attestations, & &1.transaction_summary)
  end
end
