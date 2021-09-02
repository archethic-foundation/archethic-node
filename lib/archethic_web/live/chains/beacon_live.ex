defmodule ArchEthicWeb.BeaconChainLive do
  @moduledoc false
  use ArchEthicWeb, :live_view

  alias ArchEthic.TransactionChain.{
    Transaction,
    TransactionData
  }

  alias ArchEthic.BeaconChain
  alias ArchEthic.BeaconChain.Summary, as: BeaconSummary
  alias ArchEthic.BeaconChain.SummaryTimer
  alias ArchEthic.Crypto
  alias ArchEthic.P2P
  alias ArchEthic.P2P.Node
  # alias ArchEthic.PubSub
  alias ArchEthic.SelfRepair.Sync.BeaconSummaryHandler
  alias ArchEthicWeb.ExplorerView
  alias Phoenix.View

  def fetch_txn_summaries(date1 = %DateTime{},date2 = %DateTime{}) do
    summary_pools = BeaconChain.get_summary_pool(date1, date2)

    Enum.map(summary_pools, fn {subset, nodes_by_summary_time} ->
      Enum.map(nodes_by_summary_time, fn {summary_time, nodes} ->
        {nodes, subset, summary_time}
      end)
    end)
    |> :lists.flatten()
    |> Task.async_stream(
      fn {nodes, subset, summary_time} ->
        beacon_address = Crypto.derive_beacon_chain_address(subset, summary_time, true)
        %Node{network_patch: patch} = P2P.get_node_info()

        beacon_address
        |> BeaconSummaryHandler.download_summary(nodes, patch)
      end,
      on_timeout: :kill_task,
      max_concurrency: 256
    )
    |> Enum.filter(&match?({:ok, {:ok, %Transaction{}}}, &1))
    |> Enum.map(fn {:ok, {:ok, %Transaction{data: %TransactionData{content: content}}}} ->
      {summary, _} = BeaconSummary.deserialize(content)
      %BeaconSummary{transaction_summaries: transaction_summaries} = summary
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
      |> assign(:transactions, list_transactions_by_date(
        Enum.at(beacon_dates,0),
        fetch_txn_summaries(Enum.at(beacon_dates, 0),Enum.at(beacon_dates,1))))
      IO.inspect(new_assign)
    {:ok, new_assign}
  end

  def render(assigns) do
    View.render(ExplorerView, "beacon_chain_index.html", assigns)
  end

  def handle_params(%{"page" => page}, _uri, socket = %{assigns: %{dates: dates}}) do
    case Integer.parse(page) do
      {number, ""} when number > 0 ->
        transactions =
          list_transactions_by_date( Enum.at(dates,number+1),fetch_txn_summaries(Enum.at(dates,number+1),Enum.at(dates,number+2)))
          IO.inspect(transactions)
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

  def get_beacon_dates do
    %Node{enrollment_date: enrollment_date} =
      P2P.list_nodes() |> Enum.sort_by(& &1.enrollment_date, {:asc, DateTime}) |> Enum.at(0)

    enrollment_date
    |> SummaryTimer.previous_summaries()
    |> Enum.sort({:asc, DateTime})
  end

  def list_transactions_by_date(date = %DateTime{}, all_tx) do
    # rm_tx = :lists.delete([], all_tx)

    # rm_tx
    # |> :lists.flatten()
    all_tx
    |> Enum.flat_map(& &1)
    |> Enum.filter(fn %ArchEthic.BeaconChain.Slot.TransactionSummary{
                          address: _,
                          movements_addresses: _,
                          timestamp: timestamp,
                          type: _
                        } ->
      tmsp = DateTime.truncate(timestamp, :second)
      t1 = DateTime.add(date, 60, :second)

      DateTime.truncate(tmsp, :second) >= DateTime.truncate(date, :second) and
        DateTime.truncate(tmsp, :second) < DateTime.truncate(t1, :second)
    end)
  end

#   def list_transactions_by_date(nil, _all_tx), do: []
end
