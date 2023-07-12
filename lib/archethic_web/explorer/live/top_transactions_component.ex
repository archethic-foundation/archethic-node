defmodule ArchethicWeb.ExplorerIndexLive.TopTransactionsComponent do
  @moduledoc """
  Live component for Dashboard Explorer to display recent transactions
  """

  use ArchethicWeb, :live_component

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
      case TopTransactionsCache.get() do
        [] ->
          txns = fetch_last_transactions()
          push_txns_to_cache(txns)
          txns

        txs ->
          txs
      end

    socket = socket |> assign(assigns) |> assign(transactions: transactions)
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="box mb-2">
      <div class="columns">
        <div class="column"><span class="heading is-size-7">Latest transactions</span></div>
      </div>
      <div class="columns">
        <div class="column">
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
      </div>
    </div>
    """
  end

  defp push_txns_to_cache(txns) when is_list(txns) do
    txns
    |> Enum.each(fn txn ->
      TopTransactionsCache.push(txn)
    end)
  end

  defp fetch_last_transactions(n \\ 5) do
    Archethic.list_transactions_summaries_from_current_slot()
    |> Enum.take(n)
  end
end
