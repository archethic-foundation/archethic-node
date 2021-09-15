defmodule ArchEthicWeb.BeaconChainLive do
  @moduledoc false
  use ArchEthicWeb, :live_view

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.BeaconChain.SummaryTimer
  alias ArchEthic.Crypto
  alias ArchEthic.Election
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  alias ArchEthic.PubSub
  alias ArchEthic.SelfRepair.Sync.BeaconSummaryHandler
  alias ArchEthicWeb.ExplorerView
  alias Phoenix.View

  defp list_transaction_by_date(date = %DateTime{}) do
    Enum.map(BeaconChain.list_subsets(), fn subset ->
      b_address = Crypto.derive_beacon_chain_address(subset, date, True)
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
    # Todo handle live transactions

    if connected?(socket) do
      # next_summary_time = BeaconChain.next_summary_date(DateTime.utc_now())
      # send(self(), {next_summary_time})
      PubSub.register_to_next_summary_time()
      # we want streaming channels bw closet nodes for all subsets
    end

    dates = get_beacon_dates()

    # if Enum.empty?(dates) do
    # [BeaconChain.next_summary_date(DateTime.utc_now())]
    # else
    beacon_dates = dates
    # end

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
        transactions = list_transaction_by_date(Enum.at(dates, number - 1))

        new_assign =
          socket
          |> assign(:current_date_page, number)
          |> assign(:transactions, transactions)

        {:noreply, new_assign}

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
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  def handle_info(
        {:next_summary_time, next_summary_date},
        socket = %{assigns: %{current_date_page: page, dates: dates}}
      ) do
    # if current_summary_time === next_summary_date do
    #   dates
    #  else
    new_dates = [next_summary_date | dates]
    #  end
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
end
