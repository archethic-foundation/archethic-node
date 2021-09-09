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
    |> Stream.flat_map(fn {:ok, {:ok, %BeaconSummary{transaction_summaries: transaction_summaries}}} ->
      transaction_summaries
    end)
  end

  def mount(_params, _session, socket) do
    # Todo handle live transactions
    # if connected?(socket) do
    #   PubSub.register_to_new_transaction_by_type(:beacon)
    #   PubSub.register_to_new_transaction_by_type(:beacon_summary)
    # end

    beacon_dates = get_beacon_dates()

    new_assign =
      socket
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
      {number, ""} when number > 0 ->
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

  def handle_event("goto", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: Routes.live_path(socket, __MODULE__, %{"page" => page}))}
  end

  defp get_beacon_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes() |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime}) |> Enum.at(0)

    enrollment_date
    |> SummaryTimer.previous_summaries()
    |> Enum.sort({:asc, DateTime})
  end
end
