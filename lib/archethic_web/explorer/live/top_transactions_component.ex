defmodule ArchethicWeb.Explorer.ExplorerIndexLive.TopTransactionsComponent do
  @moduledoc """
  Live component for Dashboard Explorer to display recent transactions
  """

  use ArchethicWeb.Explorer, :live_component

  alias ArchethicWeb.Explorer.ExplorerLive.TopTransactionsCache
  import ArchethicWeb.Explorer.ExplorerView

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
