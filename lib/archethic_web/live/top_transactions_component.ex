defmodule ArchethicWeb.ExplorerIndexLive.TopTransactionsComponent do
  @moduledoc """
    Live component for Dashboard Explorer to display last 10 transactions
  """

  use ArchethicWeb, :live_component

  alias Archethic.BeaconChain

  alias Archethic.Election

  alias Archethic.P2P
  alias Archethic.P2P.Node
  alias Archethic.P2P.Message.GetCurrentSummaries
  alias Archethic.P2P.Message.TransactionSummaryList

  alias ArchethicWeb.ExplorerLive.TopTransactionsCache

  def mount(socket) do
    socket =
      socket
      |> assign(:transactions, [])

    {:ok, socket}
  end

  def update(
        %{transaction: transaction} = _assigns,
        socket
      )
      when not is_nil(transaction) do
    TopTransactionsCache.push(transaction)
    transactions = TopTransactionsCache.get()

    socket =
      socket
      |> assign(:transactions, transactions)

    {:ok, socket}
  end

  def update(assigns, socket) do
    transactions =
      case length(TopTransactionsCache.get()) do
        l when l < 10 ->
          txns = fetch_last_transactions()
          # Below code won't const much performace as atmost 10 transaction will be pushed.
          txns
          |> Enum.each(fn txn ->
            TopTransactionsCache.push(txn)
          end)

          txns

        _ ->
          TopTransactionsCache.get()
      end

    socket = socket |> assign(assigns) |> assign(transactions: transactions)
    {:ok, socket}
  end

  def render(assigns) do
    ~L"""
      <div class="box mb-2">
        <p>Latest Txns</p>
      <div>
      <div>
        <%= for tx <- @transactions do %>
          <div class="columns">
            <div class="column is-7-desktop">
              <%= link to: Routes.live_path(@socket, ArchethicWeb.TransactionDetailsLive, Base.encode16(tx.address)) do%>
                <span class="text_wrap has-text-primary is-size-6"><%= Base.encode16(tx.address) %></span>
                <% end %>
            </div>
            <div class="column is-2-desktop is-size-6">
              <%= format_date(tx.timestamp) %>
            </div>
            <div class="column is-2-desktop is-size-6">
              <span class="tag is-light is-info"><%= tx.type %></span>
            </div>
          </div>
        <% end %>
      </div>
    """
  end

  defp fetch_previous_dates(time = %DateTime{}, txns) when length(txns) < 10 do
    previous_time = BeaconChain.previous_summary_time(time)
    txns = txns ++ list_transactions_from_summary(previous_time)
    fetch_previous_dates(previous_time, txns)
  end

  defp fetch_previous_dates(_time = %DateTime{}, txns) when length(txns) >= 10 do
    txns
  end

  defp fetch_last_transactions(n \\ 10) do
    txns = list_transactions_from_current_slots()

    if length(txns) < n do
      fetch_previous_dates(DateTime.utc_now(), txns)
    else
      txns
      |> Enum.take(n)
    end
  end

  defp list_transactions_from_current_slots(date = %DateTime{} \\ DateTime.utc_now()) do
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

  defp list_transactions_from_summary(date = %DateTime{}) do
    [date]
    |> BeaconChain.fetch_summary_aggregates()
    |> Enum.flat_map(& &1.transaction_summaries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end
end
