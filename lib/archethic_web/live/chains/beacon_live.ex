defmodule ArchEthicWeb.BeaconChainLive do
  @moduledoc false
  use ArchEthicWeb, :live_view

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Slot.TransactionSummary
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.BeaconChain.SummaryTimer
  alias ArchEthic.Crypto
  alias ArchEthic.Election
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  alias ArchEthic.P2P.Message.RegisterBeaconUpdates
  alias ArchEthic.PubSub
  alias ArchEthic.SelfRepair.Sync.BeaconSummaryHandler
  alias ArchEthicWeb.ExplorerView
  alias Phoenix.View

  defp list_transaction_by_date(date = %DateTime{}) do
    Enum.map(BeaconChain.list_subsets(), fn subset ->
      b_address = Crypto.derive_beacon_chain_address(subset, date, true)
      node_list = P2P.authorized_nodes()
      nodes = Election.beacon_storage_nodes(subset, date, node_list)
      %Node{network_patch: patch} = P2P.get_node_info()

      {b_address, nodes, patch}
    end)
    |> Task.async_stream(
      fn {address, nodes, patch} ->
        BeaconSummaryHandler.download_summary(address, nodes, patch)
      end,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Stream.filter(&match?({:ok, {:ok, %BeaconSummary{}}}, &1))
    |> Stream.flat_map(fn {:ok,
                           {:ok, %BeaconSummary{transaction_summaries: transaction_summaries}}} ->
      transaction_summaries
    end)
  end

  defp list_transaction_by_date(nil), do: []

  def mount(_params, _session, socket) do
    next_summary_time = BeaconChain.next_summary_date(DateTime.utc_now())

    if connected?(socket) do
      PubSub.register_to_next_summary_time()
      register_to_beacon_pool_updates()
      PubSub.register_to_added_new_transaction_summary()
    end

    beacon_dates =
      case get_beacon_dates() |> Enum.to_list() do
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
      |> assign(
        :transactions,
        list_transaction_by_date(Enum.at(beacon_dates, 0))
      )

    {:ok, new_assign}
  end

  def render(assigns) do
    View.render(ExplorerView, "beacon_chain_index.html", assigns)
  end

  def handle_params(%{"page" => page}, _uri, socket = %{assigns: %{dates: dates}}) do
    case Integer.parse(page) do
      {number, ""} when number > 0 and is_list(dates) ->
        if number > length(dates) do
          {:noreply,
           push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => 1}))}
        else
          transactions =
            dates
            |> Enum.at(number - 1)
            |> list_transaction_by_date()

          new_assign =
            socket
            |> assign(:current_date_page, number)
            |> assign(:transactions, transactions)

          {:noreply, new_assign}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_params(%{}, _, socket) do
    {:noreply, socket}
  end

  @spec handle_event(<<_::32>>, map, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("goto", %{"page" => page}, socket) do
    {:noreply, push_redirect(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_info(
        {:added_new_transaction_summary, tx_summary = %TransactionSummary{}},
        socket = %{
          assigns: %{
            current_date_page: page,
            transactions: transactions,
            next_summary_time: next_summary_time,
            dates: dates
          }
        }
      ) do
    new_transactions =
      if page == 1 do
        [tx_summary | transactions |> Enum.to_list()]
      else
        transactions
      end

    new_dates =
      if Enum.at(dates, 0) == next_summary_time do
        dates
      else
        [next_summary_time | dates]
      end

    new_assign =
      socket
      |> assign(:dates, new_dates)
      |> assign(:transactions, new_transactions)

    {:noreply, new_assign}
  end

  def handle_info(
        {:next_summary_time, next_summary_date},
        socket = %{assigns: %{current_date_page: page, dates: dates}}
      ) do
    new_dates = [next_summary_date | dates]

    transactions =
      new_dates
      |> Enum.at(page - 1)
      |> list_transaction_by_date()

    new_next_summary =
      if :gt == DateTime.compare(next_summary_date, DateTime.utc_now()) do
        next_summary_date
      else
        BeaconChain.next_summary_date(DateTime.utc_now())
      end

    new_assign =
      socket
      |> assign(:transactions, transactions)
      |> assign(:dates, new_dates)
      |> assign(:next_summary_time, new_next_summary)

    {:noreply, new_assign}
  end

  defp get_beacon_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes() |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime}) |> Enum.at(0)

    enrollment_date
    |> SummaryTimer.previous_summaries()
    |> Enum.sort({:desc, DateTime})
  end

  defp register_to_beacon_pool_updates do
    date = BeaconChain.next_summary_date(DateTime.utc_now())

    Enum.map(BeaconChain.list_subsets(), fn subset ->
      list_of_nodes_for_this_subset =
        Election.beacon_storage_nodes(subset, date, P2P.authorized_nodes())

      P2P.broadcast_message(list_of_nodes_for_this_subset, %RegisterBeaconUpdates{
        nodePublicKey: Crypto.first_node_public_key(),
        subset: subset
      })
    end)
  end
end
