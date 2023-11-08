defmodule ArchethicWeb.Explorer.ExplorerIndexLive.TopTransactionsComponent do
  @moduledoc """
  Live component for Dashboard Explorer to display recent transactions
  """

  use ArchethicWeb.Explorer, :live_component

  alias ArchethicWeb.Explorer.ExplorerLive.TopTransactionsCache

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
    <div>
      <div class="text_regular is-multiline">Latest transactions</div>
      <br/><br/>
      <%= for tx <- @transactions do %>
        <div class="columns list-card">
          <div class="column list-card-item-address is-12-mobile is-6-tablet is-8-desktop">
            <%= link to: Routes.live_path(@socket, ArchethicWeb.Explorer.TransactionDetailsLive, Base.encode16(tx.address)) do%>
              <%= Base.encode16(tx.address) %>
            <% end %>
          </div>
          <div class="column list-card-item is-6-mobile is-3-tablet is-2-desktop">
            <%= format_date(tx.timestamp) %>
          </div>
          <div class="column list-card-item is-6-mobile is-3-tablet is-2-desktop">
            <div class="tag is-light is-info"><%= tx.type %></div>
          </div>
        </div>
        <div style="height: 20px;"></div>
      <% end %>
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
